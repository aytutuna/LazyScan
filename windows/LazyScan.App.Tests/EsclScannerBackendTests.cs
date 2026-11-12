using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using LazyScan.App.Scanning;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

// Twin of the connection cases of Tests/LazyScanTests/EsclScannerBackendTests.swift: when a scanner
// has a pinned certificate its plain HTTP address is never used, and a scanner never trusted keeps it.

public sealed class EsclScannerBackendTests : IDisposable
{
    private readonly string _directory;
    private readonly TcpListener _plain = new(IPAddress.Loopback, 0);
    private int _plainConnections;

    public EsclScannerBackendTests()
    {
        _directory = Path.Combine(Path.GetTempPath(), "LazyScanTests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_directory);
        _plain.Start();
        _ = ServePlainAsync();
    }

    public void Dispose()
    {
        _plain.Stop();
        try { Directory.Delete(_directory, recursive: true); } catch (IOException) { }
    }

    private async Task ServePlainAsync()
    {
        string body = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "Escl", "capabilities-platen-duplex-adf.xml"));
        byte[] reply = Encoding.UTF8.GetBytes(
            $"HTTP/1.1 200 OK\r\nContent-Type: text/xml\r\nContent-Length: {Encoding.UTF8.GetByteCount(body)}\r\nConnection: close\r\n\r\n{body}");
        try
        {
            while (true)
            {
                using var client = await _plain.AcceptTcpClientAsync();
                Interlocked.Increment(ref _plainConnections);
                var stream = client.GetStream();
                var head = new byte[4096];
                await stream.ReadAtLeastAsync(head, 1, throwOnEndOfStream: false);
                await stream.WriteAsync(reply);
            }
        }
        catch (Exception e) when (e is ObjectDisposedException or SocketException or IOException)
        {
        }
    }

    private static int ClosedPort()
    {
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        int port = ((IPEndPoint)listener.LocalEndpoint).Port;
        listener.Stop();
        return port;
    }

    /// <summary>A scanner whose HTTPS address nothing listens at, and whose plain HTTP address answers.</summary>
    private (EsclScannerBackend Backend, ScannerAddress Secure) Scanner(EsclTrustStore trust)
    {
        var secure = ScannerAddress.Create(secure: true, "127.0.0.1", ClosedPort(), "eSCL")!;
        var plain = ScannerAddress.Create(secure: false, "127.0.0.1", ((IPEndPoint)_plain.LocalEndpoint).Port, "eSCL")!;
        var endpoint = new EsclEndpoint
        {
            Key = "uuid:hp",
            Name = "HP M479",
            Txt = EsclTxtRecord.Parse(null),
            Addresses = [secure, plain],
        };
        var backend = new EsclScannerBackend(new EsclHostList(_directory), trust, discover: false,
                                             new EsclClientOptions { RequestTimeout = TimeSpan.FromSeconds(5) }, [endpoint]);
        backend.StartBrowsing();
        return (backend, secure);
    }

    [Fact]
    public async Task APinnedScannerWhoseHttpsDoesNotAnswerIsNeverReachedOverPlainHttp()
    {
        var trust = new EsclTrustStore(_directory);
        var (backend, secure) = Scanner(trust);
        trust.Trust(new string('a', 64), null, secure.Authority, "HP M479");

        var error = await Assert.ThrowsAsync<ScanException>(() => backend.OpenSessionAsync("escl:uuid:hp"));

        Assert.Contains("HP M479 did not answer securely, so Lazy Scan did not use its unencrypted address. "
                        + "Check that the scanner is on and reachable, then try again.", error.Message);
        Assert.Equal(0, Volatile.Read(ref _plainConnections));
        backend.StopBrowsing();
    }

    [Fact]
    public async Task AScannerNeverTrustedFallsBackToPlainHttp()
    {
        var (backend, _) = Scanner(new EsclTrustStore(_directory));

        await backend.OpenSessionAsync("escl:uuid:hp");

        Assert.True(Volatile.Read(ref _plainConnections) > 0);
        backend.StopBrowsing();
    }
}
