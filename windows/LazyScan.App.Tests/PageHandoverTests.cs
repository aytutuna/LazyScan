using LazyScan.App.Scanning;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

public class PageHandoverTests
{
    private static ScannedPage Page(int number) => new(new RgbaImage(1, 1, new byte[4]), number, ColorMode.Color);

    [Fact]
    public async Task PagesArriveInOrder_AndTheScanWaitsForTheCaller()
    {
        var delivered = 0;
        var passed = new List<int>();
        var inHand = new TaskCompletionSource();
        var release = new TaskCompletionSource();

        var run = PageHandover.Run(async emit =>
        {
            await Task.Run(async () =>
            {
                for (int i = 1; i <= 6; i++)
                {
                    await emit(Page(i));
                    Interlocked.Increment(ref delivered);
                }
            });
        }, async page =>
        {
            if (passed.Count == 0)
            {
                inHand.SetResult();
                await release.Task;
            }
            passed.Add(page.Dpi);
        });

        await inHand.Task;
        await Task.Delay(100);
        // The caller still holds page 1: the scan has gone no further than a page or two ahead.
        Assert.True(delivered <= 2, $"{delivered} pages left the scan while the caller held one");
        release.SetResult();
        await run;

        Assert.Equal([1, 2, 3, 4, 5, 6], passed);
    }

    [Fact]
    public async Task ThePagesBeforeAFailureAreStillPassed_ThenItIsThrown()
    {
        var passed = new List<int>();
        var error = await Assert.ThrowsAsync<ScanException>(() => PageHandover.Run(async emit =>
        {
            await emit(Page(1));
            await emit(Page(2));
            throw ScanException.ScanFailed("jam");
        }, page =>
        {
            passed.Add(page.Dpi);
            return Task.CompletedTask;
        }));

        Assert.Equal([1, 2], passed);
        Assert.NotNull(error);
    }

    [Fact]
    public async Task AFailingCaller_StopsTheScan()
    {
        int emitted = 0;
        Exception? scanSaw = null;
        await Assert.ThrowsAsync<InvalidOperationException>(() => PageHandover.Run(async emit =>
        {
            try
            {
                for (int i = 1; i <= 100; i++)
                {
                    await emit(Page(i));
                    emitted++;
                }
            }
            catch (Exception e)
            {
                scanSaw = e;
                throw;
            }
        }, _ => throw new InvalidOperationException("no room")));

        Assert.True(emitted < 100);
        Assert.IsAssignableFrom<OperationCanceledException>(scanSaw);
    }
}
