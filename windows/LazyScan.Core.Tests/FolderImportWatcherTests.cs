using LazyScan.Core;
using Xunit;

namespace LazyScan.Core.Tests;

public sealed class FolderImportWatcherTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(), "LazyScanTests-" + Guid.NewGuid().ToString("N"));
    private DateTimeOffset _now = new(2026, 11, 14, 9, 0, 0, TimeSpan.Zero);
    private readonly FolderImportWatcher _watcher;

    public FolderImportWatcherTests()
    {
        Directory.CreateDirectory(_folder);
        _watcher = new FolderImportWatcher(_folder, () => _now);
    }

    public void Dispose()
    {
        _watcher.Dispose();
        Directory.Delete(_folder, recursive: true);
    }

    private string Put(string name, string content = "x", int minutesOld = 0)
    {
        string path = Path.Combine(_folder, name);
        File.WriteAllText(path, content);
        File.SetLastWriteTimeUtc(path, new DateTime(2026, 11, 14, 8, 0, 0, DateTimeKind.Utc).AddMinutes(-minutesOld));
        return path;
    }

    private void Settle()
    {
        _watcher.Poll();
        _now += FolderImportWatcher.SettleTime;
        _watcher.Poll();
    }

    [Fact]
    public void FilesThatWereThereAtTheStartAreNotImported()
    {
        Put("old.jpg");
        _watcher.Poll();
        Settle();
        Assert.Empty(_watcher.TakeReady());
    }

    [Fact]
    public void SkippedPath_ThatSettlesIsNotHandedOut()
    {
        _watcher.Poll();
        string saved = Put("saved.pdf");
        string other = Put("other.jpg");
        _watcher.Skip([saved]);
        Settle();
        Assert.Equal([other], _watcher.TakeReady());
    }

    [Fact]
    public void NewImage_IsReadyOnceItsSizeHasBeenSteadyForTheSettleTime()
    {
        _watcher.Poll();
        string path = Put("new.jpg");
        _watcher.Poll();
        Assert.Equal(0, _watcher.Pending);
        _now += FolderImportWatcher.SettleTime;
        _watcher.Poll();
        Assert.Equal(1, _watcher.Pending);
        Assert.Equal([path], _watcher.TakeReady());
    }

    [Fact]
    public void FileStillGrowing_WaitsForItsNewSize()
    {
        _watcher.Poll();
        string path = Put("scan.png", "x");
        _watcher.Poll();
        _now += FolderImportWatcher.SettleTime;
        File.AppendAllText(path, "more");
        _watcher.Poll();
        Assert.Equal(0, _watcher.Pending);
        _now += FolderImportWatcher.SettleTime;
        _watcher.Poll();
        Assert.Equal(1, _watcher.Pending);
    }

    [Fact]
    public void ATakenFile_IsNotOfferedAgain_UntilItChanges()
    {
        _watcher.Poll();
        Put("a.jpg");
        Settle();
        Assert.Single(_watcher.TakeReady());
        Settle();
        Assert.Empty(_watcher.TakeReady());
        Put("a.jpg", "changed", minutesOld: 5);
        Settle();
        Assert.Single(_watcher.TakeReady());
    }

    [Fact]
    public void ReadyFiles_AreHandedOutOldestFirst_AndOtherTypesAndFoldersAreIgnored()
    {
        _watcher.Poll();
        string newer = Put("b.jpg", minutesOld: 1);
        string older = Put("c.PDF", minutesOld: 9);
        Put("notes.txt");
        Directory.CreateDirectory(Path.Combine(_folder, "sub"));
        File.WriteAllText(Path.Combine(_folder, "sub", "deep.jpg"), "x");
        Settle();
        Assert.Equal([older, newer], _watcher.TakeReady());
    }

    [Fact]
    public void FilesThatWaitAreKeptUntilTaken()
    {
        _watcher.Poll();
        Put("a.jpg", minutesOld: 3);
        Put("b.jpg", minutesOld: 2);
        Settle();
        Settle();
        Assert.Equal(2, _watcher.Pending);
        Assert.Equal(2, _watcher.TakeReady().Count);
        Assert.Equal(0, _watcher.Pending);
    }

    [Fact]
    public void FolderThatIsNotThere_IsReportedAndWatchedAgainWhenItComesBack()
    {
        var changes = 0;
        using var missing = new FolderImportWatcher(Path.Combine(_folder, "gone"), () => _now);
        missing.Changed += (_, _) => changes++;
        missing.Poll();
        Assert.Equal(FolderImportState.Missing, missing.State);
        Assert.Equal(1, changes);
        Directory.CreateDirectory(Path.Combine(_folder, "gone"));
        missing.Poll();
        Assert.Equal(FolderImportState.Watching, missing.State);
        Assert.Equal(2, changes);
    }

    [Fact]
    public void ChangedIsRaisedWhenNewFilesAreReady()
    {
        var changes = 0;
        _watcher.Changed += (_, _) => changes++;
        _watcher.Poll();
        Put("a.jpg");
        Settle();
        Assert.Equal(1, changes);
    }

    [Theory]
    [InlineData(@"C:\Scans", @"C:\Scans", true)]
    [InlineData(@"C:\Scans", @"c:\scans\", true)]
    [InlineData(@"C:\Scans", @"C:\Scans\Print", true)]
    [InlineData(@"C:\Scans\Print", @"C:\Scans", true)]
    [InlineData(@"C:\Scans\Sub\..", @"C:\Scans\Print", true)]
    [InlineData(@"C:\Scans", @"C:\Scans2", false)]
    [InlineData(@"C:\Scans", @"D:\Scans", false)]
    [InlineData(@"D:\", @"D:\Scans", true)]
    [InlineData(@" ", @"D:\Scans", false)]
    [InlineData(@"C:\Inbox", @"C:\Scans", false)]
    public void OverlapsMeansTheSameFolderOrOneInsideTheOther(string a, string b, bool expected)
    {
        Assert.Equal(expected, FolderImportWatcher.Overlaps(a, b));
        Assert.Equal(expected, FolderImportWatcher.Overlaps(b, a));
    }
}
