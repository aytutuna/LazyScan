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
