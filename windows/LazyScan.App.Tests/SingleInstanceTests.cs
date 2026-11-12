using LazyScan.App.Services;
using Xunit;

namespace LazyScan.App.Tests;

public sealed class SingleInstanceTests
{
    private static string NewName() => "LazyScan.Tests-" + Guid.NewGuid().ToString("N");

    [Fact]
    public void OnlyTheFirstProcessOwnsTheName()
    {
        var name = NewName();
        using var first = SingleInstance.TryOwn(name);
        Assert.NotNull(first);
        // Another thread stands in for another process: a mutex is not exclusive to the thread that made it.
        SingleInstance? second = null;
        var t = new Thread(() => second = SingleInstance.TryOwn(name));
        t.Start();
        t.Join();
        Assert.Null(second);
    }

    [Fact]
    public async Task ArgumentsSentReachTheFirstInstance()
    {
        var name = NewName();
        using var first = SingleInstance.TryOwn(name)!;
        var got = new TaskCompletionSource<string[]>();
        first.Listen(args => got.TrySetResult(args));

        Assert.True(SingleInstance.Send(name, [@"C:\Scans\My Receipt.lsdoc", "x"]));

        Assert.Equal([@"C:\Scans\My Receipt.lsdoc", "x"], await got.Task.WaitAsync(TimeSpan.FromSeconds(5)));
    }

    [Fact]
    public void SendFailsWhenNothingListens()
    {
        Assert.False(SingleInstance.Send(NewName(), ["a"], timeoutMs: 200));
    }
}
