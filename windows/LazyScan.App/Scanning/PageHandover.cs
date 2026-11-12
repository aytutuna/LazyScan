using System.Threading.Channels;
using LazyScan.Core;

namespace LazyScan.App.Scanning;

/// <summary>
/// Hands the pages a backend scans on its own thread to the caller one at a time, as they arrive.
/// The backend waits whenever the caller still has a page to finish, so a long stack is never held
/// in memory ahead of the caller.
/// </summary>
internal static class PageHandover
{
    /// <summary>
    /// Runs <paramref name="scan"/>, which calls the function it is given for every page (and waits for
    /// room before going on), and passes each page to <paramref name="onPage"/> on the caller's context.
    /// Returns when the scan is over and every page was passed; throws what the scan threw, after the
    /// pages it delivered. If <paramref name="onPage"/> throws, the scan is told to stop and its own
    /// outcome is dropped.
    /// </summary>
    public static async Task Run(Func<Func<ScannedPage, Task>, Task> scan, Func<ScannedPage, Task> onPage)
    {
        var channel = Channel.CreateBounded<ScannedPage>(1);
        using var abandon = new CancellationTokenSource();

        async Task Scan()
        {
            try
            {
                await scan(page => channel.Writer.WriteAsync(page, abandon.Token).AsTask()).ConfigureAwait(false);
            }
            finally
            {
                channel.Writer.TryComplete();
            }
        }

        var scanning = Scan();
        try
        {
            await foreach (var page in channel.Reader.ReadAllAsync())
            {
                await onPage(page);
            }
        }
        catch
        {
            abandon.Cancel();
            try
            {
                await scanning.ConfigureAwait(false);
            }
            catch
            {
                // Told to stop: what the scan made of that is of no interest.
            }
            throw;
        }
        await scanning;
    }
}
