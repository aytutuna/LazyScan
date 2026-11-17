using System.IO;
using LazyScan.App.Services;
using Xunit;

namespace LazyScan.App.Tests;

// The Saved tab lists the folders a file name template makes under the save folder.
public class SavedFilesListTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("LazyScan-list-tests-").FullName;

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); }
        catch (IOException) { }
    }

    private void Touch(string relative)
    {
        string path = Path.Combine(_folder, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, [1]);
    }

    [Fact]
    public void ListsFilesInSubfoldersAndSkipsHiddenOnes()
    {
        Touch("top.pdf");
        Touch(Path.Combine("2026", "08", "Scan 1.pdf"));
        Touch(Path.Combine("2026", "notes.docx"));
        Touch(Path.Combine(".hidden", "Scan 2.pdf"));
        Touch(Path.Combine("2026", ".Scan 3.pdf"));
        Touch(Path.Combine("2026", "other.dat"));

        var names = SavedFiles.List(_folder)!.Select(f => Path.GetRelativePath(_folder, f.Path)).Order().ToList();

        Assert.Equal(
            [Path.Combine("2026", "08", "Scan 1.pdf"), Path.Combine("2026", "notes.docx"), "top.pdf"],
            names);
    }

    [Fact]
    public void StopsBelowTheDepthLimit()
    {
        Touch(Path.Combine("a", "b", "c", "d", "ok.pdf"));
        Touch(Path.Combine("a", "b", "c", "d", "e", "deep.pdf"));

        var names = SavedFiles.List(_folder)!.Select(f => f.Name).ToList();

        Assert.Equal(["ok.pdf"], names);
    }

    [Theory]
    [InlineData(FileAttributes.Offline, true)]
    [InlineData((FileAttributes)0x40000, true)]
    [InlineData((FileAttributes)0x400000, true)]
    [InlineData(FileAttributes.Archive, false)]
    [InlineData((FileAttributes)0, false)]
    public void OnlyCloudPlaceholdersAreOnlineOnly(FileAttributes attributes, bool expected)
    {
        Assert.Equal(expected, new SavedFile(@"C:\scans\a.jpg", DateTime.Now, 1, attributes).IsOnlineOnly);
    }

    [Fact]
    public async Task OnlineOnlyFilesGetNoThumbnail()
    {
        string path = Path.Combine(_folder, "a.png");
        File.WriteAllBytes(path, [1]);
        var file = new SavedFile(path, DateTime.Now, 1, (FileAttributes)0x400000);

        Assert.Null(await SavedFiles.LoadThumbnailAsync(file, 64));
    }

    [Fact]
    public void ListKeepsTheFileAttributes()
    {
        Touch("a.pdf");

        Assert.True(SavedFiles.List(_folder)!.Single().Attributes.HasFlag(FileAttributes.Archive));
    }
}
