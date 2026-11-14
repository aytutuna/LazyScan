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
}
