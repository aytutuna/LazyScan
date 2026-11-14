using LazyScan.App.Scanning.Twain;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

public class TwainThreadTests
{
    [Fact]
    public async Task WorkBehindABusyCall_SaysItWaits_AndItsLimitCountsFromPickup()
    {
        var thread = new TwainThread();
        var release = new ManualResetEventSlim();
        var first = thread.RunAsync(() =>
        {
            release.Wait(TimeSpan.FromSeconds(30));
            return 1;
        }, TimeSpan.FromSeconds(60));

        int waiting = 0;
        var second = thread.RunWithStartLimitAsync(started =>
        {
            started();
            return 2;
        }, TimeSpan.FromMilliseconds(300), onWaiting: () => waiting++);

        await Task.Delay(1000);
        Assert.Equal(1, waiting);
        release.Set();
        await first;
        Assert.Equal(2, await second);
    }

    [Fact]
    public async Task WorkThatNeverStarts_StillGivesNotResponding_AfterItsLimit()
    {
        var thread = new TwainThread();
        var release = new ManualResetEventSlim();
        var ex = await Assert.ThrowsAsync<ScanException>(() => thread.RunWithStartLimitAsync<int>(_ =>
        {
            release.Wait(TimeSpan.FromSeconds(30));
            return 0;
        }, TimeSpan.FromMilliseconds(300)));
        release.Set();
        Assert.Equal(TwainThread.NotResponding().Message, ex.Message);
    }

    [Fact]
    public async Task WorkBehindACallThatNeverReturns_GivesNotResponding()
    {
        var thread = new TwainThread();
        var release = new ManualResetEventSlim();
        _ = thread.RunAsync(() =>
        {
            release.Wait(TimeSpan.FromSeconds(30));
            return 1;
        }, TimeSpan.FromMilliseconds(300));
        var ex = await Assert.ThrowsAsync<ScanException>(() =>
            thread.RunWithStartLimitAsync(started => { started(); return 2; }, TimeSpan.FromSeconds(60)));
        release.Set();
        Assert.Equal(TwainThread.NotResponding().Message, ex.Message);
    }

    [Fact]
    public async Task WorkWaitingForItsTurn_CanBeCancelled()
    {
        var thread = new TwainThread();
        var release = new ManualResetEventSlim();
        _ = thread.RunAsync(() =>
        {
            release.Wait(TimeSpan.FromSeconds(30));
            return 1;
        }, TimeSpan.FromSeconds(60));
        using var cancel = new CancellationTokenSource(200);
        await Assert.ThrowsAsync<ScanException>(() =>
            thread.RunWithStartLimitAsync(started => { started(); return 2; }, TimeSpan.FromSeconds(60), cancel.Token));
        release.Set();
    }
}
