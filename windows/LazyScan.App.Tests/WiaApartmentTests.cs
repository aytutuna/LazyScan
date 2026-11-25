using LazyScan.App.Scanning;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

[Collection(WallClockCollection.Name)]
public sealed class WiaApartmentTests
{
    [Fact]
    public async Task ACallThatNeverReturnsFaultsWithNotRespondingAndLaterCallsFailAtOnce()
    {
        using var release = new ManualResetEventSlim();
        try
        {
            var hung = await Assert.ThrowsAsync<ScanException>(() =>
                WiaApartment.Run(() => { release.Wait(); return 1; }, TimeSpan.FromMilliseconds(100), "Acme 5"));
            Assert.Contains("Acme 5 is not responding. Turn it off and on again, then try again.", hung.Message);

            var started = DateTime.UtcNow;
            var next = await Assert.ThrowsAsync<ScanException>(() =>
                WiaApartment.Run(() => 2, TimeSpan.FromSeconds(30), "Other 6"));
            Assert.Contains("Acme 5 is not responding", next.Message);
            Assert.True(DateTime.UtcNow - started < TimeSpan.FromSeconds(5));
        }
        finally
        {
            release.Set();
        }

        Assert.Equal(3, await WaitUntilItRuns(() => 3));
    }

    [Fact]
    public async Task ACallThatReturnsInTimeGivesItsResult()
    {
        Assert.Equal(7, await WiaApartment.Run(() => 7, TimeSpan.FromSeconds(30), "Acme 5"));
    }

    [Fact]
    public async Task ACancelPressedWhileTheWiaThreadIsBusyStopsTheScanBeforeItStarts()
    {
        using var gate = new ManualResetEventSlim();
        var busy = WiaApartment.Run(() => { gate.Wait(); return 0; }, TimeSpan.FromSeconds(30), "Acme 5");
        try
        {
            var messages = new List<string>();
            var session = new WiaScannerSession(new ScannerInfo("wia:1", "Acme 5", "USB"), "none", () => { })
            {
                ProgressHandler = progress => messages.Add(progress.Message)
            };
            var scan = session.PerformScanAsync(new ScanSettings(), null);
            session.CancelScan();
            Assert.Contains("Cancelling: the scanner is finishing this pass.", messages);

            gate.Set();
            var error = await Assert.ThrowsAsync<ScanException>(() => scan);
            Assert.Equal(ScanErrorKind.Cancelled, error.Kind);
        }
        finally
        {
            gate.Set();
            await busy;
        }
    }

    [Fact]
    public async Task ASilentTransferEndsInAnErrorAndLaterCallsFailAtOnce()
    {
        using var release = new ManualResetEventSlim();
        try
        {
            var silent = await Assert.ThrowsAsync<ScanException>(() => WiaApartment.RunWatched(watch =>
            {
                watch(TimeSpan.FromMilliseconds(100));
                release.Wait();
                return 1;
            }, "Acme 5", CancellationToken.None, TimeSpan.FromSeconds(30)));
            Assert.Contains("Acme 5 is not responding", silent.Message);

            var next = await Assert.ThrowsAsync<ScanException>(() =>
                WiaApartment.RunWatched(_ => 2, "Other 6", CancellationToken.None, TimeSpan.FromSeconds(30)));
            Assert.Contains("Acme 5 is not responding", next.Message);
        }
        finally
        {
            release.Set();
        }

        Assert.Equal(3, await WaitUntilItRuns(() => 3));
    }

    [Fact]
    public async Task AScanWhoseCallsAllReturnInTimeIsNeverCutShort()
    {
        int result = await WiaApartment.RunWatched(watch =>
        {
            for (int sheet = 0; sheet < 5; sheet++)
            {
                watch(TimeSpan.FromMilliseconds(400));
                Thread.Sleep(150);
                watch(Timeout.InfiniteTimeSpan);
            }
            Thread.Sleep(600); // between calls the clock is off
            return 5;
        }, "Acme 5", CancellationToken.None, TimeSpan.FromSeconds(30));
        Assert.Equal(5, result);
    }

    [Fact]
    public async Task CancelEndsTheScanAfterTheGraceWithoutMarkingTheScannerAsHung()
    {
        using var release = new ManualResetEventSlim();
        using var cancel = new CancellationTokenSource();
        var scan = WiaApartment.RunWatched(watch =>
        {
            watch(TimeSpan.FromMinutes(5));
            release.Wait();
            return 1;
        }, "Acme 5", cancel.Token, TimeSpan.FromMilliseconds(200));
        try
        {
            await Task.Delay(100);
            cancel.Cancel();
            var error = await Assert.ThrowsAsync<ScanException>(() => scan);
            Assert.Equal(ScanErrorKind.Cancelled, error.Kind);
        }
        finally
        {
            release.Set();
        }

        Assert.Equal(4, await WaitUntilItRuns(() => 4));
    }

    [Fact]
    public async Task AScannerThatStaysSilentAfterCancelIsStillReportedToTheNextCall()
    {
        using var release = new ManualResetEventSlim();
        using var cancel = new CancellationTokenSource();
        var scan = WiaApartment.RunWatched(watch =>
        {
            watch(TimeSpan.FromMilliseconds(600));
            release.Wait();
            return 1;
        }, "Acme 5", cancel.Token, TimeSpan.FromMilliseconds(100));
        try
        {
            await Task.Delay(100);
            cancel.Cancel();
            await Assert.ThrowsAsync<ScanException>(() => scan);
            await Task.Delay(1200);
            var next = await Assert.ThrowsAsync<ScanException>(() =>
                WiaApartment.RunWatched(_ => 2, "Other 6", CancellationToken.None, TimeSpan.FromSeconds(30)));
            Assert.Contains("Acme 5 is not responding", next.Message);
        }
        finally
        {
            release.Set();
        }

        Assert.Equal(4, await WaitUntilItRuns(() => 4));
    }

    [Fact]
    public async Task ACancelThatTheScannerAnswersInTimeGivesTheJobsOwnResult()
    {
        using var cancel = new CancellationTokenSource();
        int result = await WiaApartment.RunWatched(watch =>
        {
            watch(TimeSpan.FromMinutes(5));
            cancel.Cancel();
            Thread.Sleep(100);
            watch(Timeout.InfiniteTimeSpan);
            return 9;
        }, "Acme 5", cancel.Token, TimeSpan.FromSeconds(30));
        Assert.Equal(9, result);
    }

    [Fact]
    public void TheFeederStopsAtTheSheetLimitAndSaysSo()
    {
        var image = new RgbaImage(1, 1, new byte[4]);
        var emitted = new List<RgbaImage>();
        int count = WiaScannerSession.PullSheets(() => image, emitted.Add, _ => { }, CancellationToken.None, 3, out var stop);
        Assert.Equal(3, count);
        Assert.Equal(3, emitted.Count);
        Assert.Contains("more than 3 sheets", stop!.Reason);
        Assert.Contains("3 pages", stop.Message(count));
    }

    [Fact]
    public void AnEmptyFeederEndsTheBatchWithoutAStop()
    {
        var image = new RgbaImage(1, 1, new byte[4]);
        int calls = 0;
        int count = WiaScannerSession.PullSheets(
            () => ++calls <= 2 ? image : throw ScanException.ForProblem(ScannerProblem.FeederEmpty),
            _ => { }, _ => { }, CancellationToken.None, 300, out var stop);
        Assert.Equal(2, count);
        Assert.Null(stop);
    }

    private static async Task<int> WaitUntilItRuns(Func<int> work)
    {
        // The flag clears when the hung call returns, which is just after it is released.
        for (int attempt = 0; ; attempt++)
        {
            try
            {
                return await WiaApartment.Run(work, TimeSpan.FromSeconds(30), "Acme 5");
            }
            catch (ScanException) when (attempt < 50)
            {
                await Task.Delay(100);
            }
        }
    }
}
