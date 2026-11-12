using LazyScan.App.Scanning.Twain;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

// TwainScannerBackend over a stand-in for the helper: a helper that fails or hangs while listing
// or opening is reported as an error and the backend keeps working.
public class TwainBackendTests
{
    private sealed class FakeHost(Func<TwainHelperSourceList> list, Func<string, ITwainTransport> open) : ITwainHelperHost
    {
        public TwainHelperSourceList ListSources() => list();
        public ITwainTransport Open(string name) => open(name);
        public void Close(ITwainTransport source) { }
    }

    private static Task Changed(TwainScannerBackend backend)
    {
        var changed = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        backend.DevicesChanged += () => changed.TrySetResult();
        return changed.Task.WaitAsync(TimeSpan.FromSeconds(60));
    }

    [Fact]
    public async Task AHelperThatFailsListing_IsReported_AsFailed()
    {
        var host = new FakeHost(() => throw ScanException.SessionFailed(() => "the helper stopped."),
                                _ => throw new InvalidOperationException());
        using var backend = new TwainScannerBackend(host);
        var changed = Changed(backend);
        backend.StartBrowsing();
        await changed;

        Assert.Equal(TwainAvailability.Failed, backend.Availability);
        Assert.Empty(backend.Devices);
        backend.StopBrowsing();
    }

    [Fact]
    public async Task AHelperThatHangsListing_IsReported_AsFailedAfterTheLimit()
    {
        var release = new ManualResetEventSlim();
        var host = new FakeHost(() =>
        {
            release.Wait(TimeSpan.FromSeconds(60));
            return new TwainHelperSourceList(TwainAvailability.Available, []);
        }, _ => throw new InvalidOperationException());
        var options = new TwainHelperOptions("unused", StartTimeout: TimeSpan.Zero,
                                             Timeouts: TwainHelperTimeouts.Default with { Hello = TimeSpan.Zero, ListSources = TimeSpan.FromSeconds(1) });
        using var backend = new TwainScannerBackend(host, options);
        var changed = Changed(backend);
        backend.StartBrowsing();
        await changed;

        Assert.Equal(TwainAvailability.Failed, backend.Availability);
        release.Set();
        backend.StopBrowsing();
    }

    [Fact]
    public async Task AHelperThatFailsOpening_ThrowsAScanException_AndListingStaysUsable()
    {
        var host = new FakeHost(() => new TwainHelperSourceList(TwainAvailability.Available, [new TwainHelperSource("Acme Scan")]),
                                _ => throw ScanException.SessionFailed(() => "the helper stopped."));
        using var backend = new TwainScannerBackend(host);
        var changed = Changed(backend);
        backend.StartBrowsing();
        await changed;

        Assert.Single(backend.Devices);
        await Assert.ThrowsAsync<ScanException>(() => backend.OpenSessionAsync("twain:Acme Scan"));
        Assert.Single(backend.Devices);
        backend.StopBrowsing();
    }
}
