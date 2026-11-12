using LazyScan.Core;
using Xunit;

namespace LazyScan.Core.Tests;

// Twin of Tests/LazyScanTests/SaveFailureTests.swift: the same cases.

public class SaveErrorsTests
{
    private static readonly string Folder = Path.GetTempPath();
    private static readonly string Name = Path.GetFileName(Folder.TrimEnd(Path.DirectorySeparatorChar));

    [Fact]
    public void DiskFull_NamesTheFolderAndKeepsThePages()
    {
        var full = new IOException("There is not enough space on the disk.", unchecked((int)0x80070070));
        Assert.Equal($"There is not enough space to save in “{Name}”. The pages are still in the queue.",
                     SaveErrors.Describe(full, Folder));
    }

    [Fact]
    public void RefusedFolder_SaysItMayBeReadOnly()
    {
        var denied = new UnauthorizedAccessException(@"Access to the path 'C:\Scans\.1234.pdf.tmp' is denied.");
        string text = SaveErrors.Describe(denied, Folder);
        Assert.Equal($"Files cannot be saved in “{Name}”. It may be read-only. Choose another folder. The pages are still in the queue.", text);
        Assert.DoesNotContain(".tmp", text);
    }

    [Fact]
    public void WriteProtectedMedium_SaysItMayBeReadOnly()
    {
        var locked = new IOException("The media is write protected.", unchecked((int)0x80070013));
        Assert.Equal($"Files cannot be saved in “{Name}”. It may be read-only. Choose another folder. The pages are still in the queue.",
                     SaveErrors.Describe(locked, Folder));
    }

    [Fact]
    public void MissingFolder()
    {
        string gone = Path.Combine(Folder, "Gone-" + Guid.NewGuid().ToString("N"));
        string expected = $"The folder “{Path.GetFileName(gone)}” was not found. Choose another folder. The pages are still in the queue.";
        Assert.Equal(expected, SaveErrors.Describe(new DirectoryNotFoundException(), gone));
        Assert.Equal(expected, SaveErrors.Describe(new IOException("The system cannot find the path."), gone));
    }

    [Fact]
    public void UnknownReason_StillNamesTheFolderNotTheTempFile()
    {
        var other = new IOException("The file .1234.pdf.tmp is bad.");
        Assert.Equal($"Could not save in “{Name}”. The pages are still in the queue.", SaveErrors.Describe(other, Folder));
    }

    [Fact]
    public void NotSavedReason_DoesNotRepeatThePagesNote()
    {
        var error = new UnauthorizedAccessException();
        string reason = SavePlan.FailureReason(SaveErrors.Describe(error, Folder));
        Assert.Equal($"Files cannot be saved in “{Name}”. It may be read-only. Choose another folder.", reason);
        Assert.Equal("The disk is full.", SavePlan.FailureReason("The disk is full."));
        Assert.Equal("The disk is full.", SavePlan.FailureReason(ScanException.ExportFailed("The disk is full.").Message));
    }

    [Fact]
    public void WritingTextIntoAMissingFolder_FailsWithTheSentence()
    {
        string gone = Path.Combine(Folder, "Gone-" + Guid.NewGuid().ToString("N"));
        var e = Assert.Throws<ScanException>(() => TextExport.WriteNewFile([1, 2, 3], Path.Combine(gone, "a.txt")));
        Assert.Contains("was not found", e.Message);
        Assert.DoesNotContain(".tmp", e.Message);
    }
}
