using System.IO;
using LazyScan.App.Services;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

public sealed class PageSpoolTests : IDisposable
{
    private readonly string _root;

    public PageSpoolTests()
    {
        _root = Path.Combine(Path.GetTempPath(), "LazyScanTests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_root);
    }

    public void Dispose()
    {
        try
        {
            Directory.Delete(_root, recursive: true);
        }
        catch (IOException)
        {
        }
    }

    private string Abandoned(bool withQueue)
    {
        string folder = Path.Combine(_root, Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        File.WriteAllBytes(Path.Combine(folder, "page.png"), [1]);
        if (withQueue) File.WriteAllText(Path.Combine(folder, QueueRecord.FileName), "{}");
        Directory.SetCreationTimeUtc(folder, DateTime.UtcNow.AddHours(-1));
        return folder;
    }

    [Fact]
    public void Sweep_RemovesAnAbandonedFolder_ButKeepsOneWithAQueueRecord()
    {
        string plain = Abandoned(withQueue: false);
        string kept = Abandoned(withQueue: true);

        var left = PageSpool.SweepAbandoned(_root);

        Assert.False(Directory.Exists(plain));
        Assert.True(File.Exists(Path.Combine(kept, "page.png")));
        Assert.True(File.Exists(Path.Combine(kept, QueueRecord.FileName)));
        Assert.Equal([kept], left);
    }

    [Fact]
    public void Sweep_LeavesAFolderAliveInstanceHoldsOutOfTheLeftBehind()
    {
        var running = new PageSpool(_root);
        File.WriteAllText(Path.Combine(running.Directory, QueueRecord.FileName), "{}");

        var left = PageSpool.SweepAbandoned(_root);

        Assert.Empty(left);
        Assert.True(Directory.Exists(running.Directory));
        running.Dispose();
    }

    [Fact]
    public void ANewSpool_ListsTheFolderOfAnInstanceThatDidNotClose()
    {
        string kept = Abandoned(withQueue: true);

        using var spool = new PageSpool(_root);

        Assert.Equal([kept], spool.LeftBehind);
    }

    [Fact]
    public void ASecondSpool_SkipsAFolderTheFirstOneListed()
    {
        string kept = Abandoned(withQueue: true);

        using var first = new PageSpool(_root);
        using var second = new PageSpool(_root);

        Assert.Equal([kept], first.LeftBehind);
        Assert.Empty(second.LeftBehind);
    }

    [Fact]
    public void Dispose_DeletesTheFolderWithItsQueueRecord()
    {
        var spool = new PageSpool(_root);
        File.WriteAllText(Path.Combine(spool.Directory, QueueRecord.FileName), "{}");

        spool.Dispose();

        Assert.False(Directory.Exists(spool.Directory));
    }
}
