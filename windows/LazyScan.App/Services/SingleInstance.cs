using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Text;

namespace LazyScan.App.Services;

/// <summary>
/// One Lazy Scan per Windows session. The first process owns a named mutex and listens on a named pipe; a
/// later one sends its command-line arguments there and exits, so a <c>.lsdoc</c> opened in File Explorer
/// reaches the queue in progress. Both names are per user session and are plain names, so they work the
/// same unpackaged and under the Store package.
/// </summary>
public sealed class SingleInstance : IDisposable
{
    private readonly string _name;
    private readonly Mutex _mutex;
    private readonly CancellationTokenSource _stop = new();

    private SingleInstance(string name, Mutex mutex)
    {
        _name = name;
        _mutex = mutex;
    }

    public static string DefaultName => $"LazyScan.{Environment.UserName}.{Process.GetCurrentProcess().SessionId}";

    /// <summary>The instance for <paramref name="name"/> when this process is the first; null when another one runs.</summary>
    public static SingleInstance? TryOwn(string name)
    {
        var mutex = new Mutex(true, @"Local\" + name, out bool created);
        if (created) return new SingleInstance(name, mutex);
        mutex.Dispose();
        return null;
    }

    /// <summary>Hands <paramref name="args"/> to the first instance; false when it does not answer in time.</summary>
    public static bool Send(string name, IEnumerable<string> args, int timeoutMs = 3000)
    {
        try
        {
            using var client = new NamedPipeClientStream(".", name, PipeDirection.Out, PipeOptions.CurrentUserOnly);
            client.Connect(timeoutMs);
            AllowSetForegroundWindow(-1);
            using var writer = new StreamWriter(client, new UTF8Encoding(false));
            foreach (var arg in args) writer.WriteLine(arg);
            return true;
        }
        catch (Exception e) when (e is TimeoutException or IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    /// <summary>Calls <paramref name="onArgs"/> on a pool thread for each set of arguments another process sends.</summary>
    public void Listen(Action<string[]> onArgs)
    {
        // The first pipe exists when this returns, so a process started right after cannot find none.
        var first = TryCreateServer();
        if (first is not null) _ = Task.Run(() => Serve(first, onArgs));
    }

    private NamedPipeServerStream? TryCreateServer()
    {
        try
        {
            return new NamedPipeServerStream(_name, PipeDirection.In, 1,
                PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    private async Task Serve(NamedPipeServerStream first, Action<string[]> onArgs)
    {
        NamedPipeServerStream? next = first;
        while (!_stop.IsCancellationRequested)
        {
            var server = next ?? TryCreateServer();
            if (server is null) return;
            next = null;
            await using var _ = server;
            try
            {
                await server.WaitForConnectionAsync(_stop.Token);
                using var reader = new StreamReader(server, new UTF8Encoding(false));
                var args = new List<string>();
                while (await reader.ReadLineAsync(_stop.Token) is { } line) args.Add(line);
                onArgs([.. args]);
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (IOException)
            {
                // A client that left halfway; the next one is served.
            }
        }
        if (next is not null) await next.DisposeAsync();
    }

    public void Dispose()
    {
        _stop.Cancel();
        _mutex.Dispose();
    }

    [DllImport("user32.dll")]
    private static extern bool AllowSetForegroundWindow(int processId);
}
