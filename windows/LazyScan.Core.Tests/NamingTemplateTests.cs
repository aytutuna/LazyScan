using LazyScan.Core;
using Xunit;

namespace LazyScan.Core.Tests;

// Port of Tests/LazyScanTests/NamingTemplateTests.swift — the same cases, so the two
// implementations stay behaviorally identical.

public class NamingTemplateTests
{
    /// <summary>2026-08-13 14:05:09, so formatter output is deterministic.</summary>
    private static DateTime FixedDate() => new(2026, 8, 13, 14, 5, 9);

    private static string Render(string template, int counter = 1,
                                 ScanIntent intent = ScanIntent.Document, int? index = null) =>
        new NamingTemplate(template).BaseFilename(counter, FixedDate(), intent, index);

    [Fact]
    public void DateToken() => Assert.Equal("2026-08-13", Render("{date}"));

    [Fact]
    public void TimeToken() => Assert.Equal("14.05.09", Render("{time}"));

    [Fact]
    public void YearMonthDayTokens()
    {
        Assert.Equal("2026", Render("{year}"));
        Assert.Contains(Render("{month}"), new[] { "08", "8" });
        Assert.Equal("13", Render("{day}"));
    }

    [Fact]
    public void CounterToken()
    {
        Assert.Equal("7", Render("{counter}", counter: 7));
        Assert.Equal("123", Render("{counter}", counter: 123));
    }

    [Fact]
    public void FilesOfOneSaveShareTheCounterAndTimeAndDifferByIndex()
    {
        string[] names = Enumerable.Range(1, 3).Select(i => Render("{time} {counter}", counter: 7, index: i)).ToArray();
        Assert.Equal(new[] { "14.05.09 7 1", "14.05.09 7 2", "14.05.09 7 3" }, names);
    }

    [Fact]
    public void CounterZeroPadding()
    {
        Assert.Equal("0007", Render("{counter:4}", counter: 7));
        Assert.Equal("0123", Render("{counter:4}", counter: 123));
    }

    [Fact]
    public void IntentToken()
    {
        Assert.Equal("Document", Render("{intent}", intent: ScanIntent.Document));
        Assert.Equal("Photos", Render("{intent}", intent: ScanIntent.Photo));
    }

    [Fact]
    public void IntentTokenStaysEnglishInAnotherLanguage()
    {
        Loc.Table = new Dictionary<string, string> { ["Document"] = "Belge", ["Photos"] = "Fotoğraflar" };
        try
        {
            Assert.Equal("Document", Render("{intent}", intent: ScanIntent.Document));
            Assert.Equal("Photos", Render("{task}", intent: ScanIntent.Photo));
        }
        finally { Loc.Table = null; }
    }

    [Fact]
    public void IndexTokenSubstituted() => Assert.Equal("Photo 7", Render("Photo {index}", index: 7));

    [Fact]
    public void IndexNullLeavesNoResidue()
    {
        string result = Render("Photo {index}", index: null);
        Assert.DoesNotContain("{", result);
        Assert.DoesNotContain("}", result);
        Assert.Equal("Photo", result.Trim());
    }

    [Fact]
    public void IndexAppendedWhenTokenAbsent()
    {
        string result = Render("Photo", index: 3);
        Assert.StartsWith("Photo", result);
        Assert.Contains("3", result);
    }

    [Fact]
    public void UnknownTokenPassesThrough() => Assert.Equal("{bogus}", Render("{bogus}"));

    [Fact]
    public void Sanitization() => Assert.Equal("a/b-c", Render("a/b:c"));

    [Fact]
    public void SlashesMakeFolders()
    {
        Assert.Equal("2026/08/Scan 1", Render("{year}/{month}/Scan {counter}"));
        Assert.Equal("a/b/c", Render(" a /b / c"));
    }

    [Fact]
    public void FoldersCannotLeaveTheSaveFolder()
    {
        Assert.Equal("x", Render("../x"));
        Assert.Equal("a/x", Render("a/../../x"));
        Assert.Equal("a/x", Render("a/./x"));
        Assert.Equal("a/x", Render("/a//x"));
        Assert.Equal("-x", Render("..\\x"));
        Assert.Equal("Scan", Render("../.."));
        Assert.Equal("a/Scan", Render("a/"));
    }

    [Fact]
    public void ReservedCharactersSanitized() =>
        Assert.Equal("a-b-c-d-e-f-g-h-i", Render("a\\b*c?d\"e<f>g|h\ni"));

    [Fact]
    public void LeadingDotsAreStripped()
    {
        Assert.Equal("scan 1", Render(".scan {counter}"));
        Assert.Equal("scan", Render(" ..  scan"));
        Assert.Equal("Scan", Render("."));
    }

    [Fact]
    public void DeviceNamesGetAnUnderscore()
    {
        Assert.Equal("Con_", Render("{label}", new NamingContext(1, FixedDate(), ScanIntent.Document) { Label = "Con" }));
        Assert.Equal("nul_", Render("{label}", new NamingContext(1, FixedDate(), ScanIntent.Document) { Label = "nul" }));
        Assert.Equal("com1_.x", Render("com1.x"));
        Assert.Equal("a/Aux_/Lpt9_", Render("a/Aux/Lpt9"));
        Assert.Equal("Console", Render("Console"));
        Assert.Equal("Com10", Render("Com10"));
    }

    [Fact]
    public void TrailingDotsAreStripped()
    {
        Assert.Equal("scan", Render("scan..."));
        Assert.Equal("a/scan", Render("a./scan. "));
        Assert.Equal("Con_", Render("Con."));
    }

    [Fact]
    public void FitToPathLengthCutsTheName()
    {
        string dir = "C:\\" + new string('d', 237);
        string fitted = NamingTemplate.FitToPathLength(dir, new string('n', 100), "pdf");
        Assert.True(fitted.Length >= 5);
        Assert.True(Path.Combine(dir, fitted + " 99.pdf").Length < 260);
        Assert.Equal("short", NamingTemplate.FitToPathLength(@"C:\Scans", "short", "pdf"));
    }

    [Fact]
    public void FitToPathLengthCountsSubfolders()
    {
        string fitted = NamingTemplate.FitToPathLength("C:\\" + new string('d', 200), "2026/" + new string('n', 100), "pdf");
        Assert.StartsWith("2026/", fitted);
        Assert.True(Path.Combine("C:\\" + new string('d', 200), fitted + " 99.pdf").Length < 260);
    }

    [Fact]
    public void FitToPathLengthRefusesAFolderThatIsTooLong()
    {
        var e = Assert.Throws<ScanException>(() =>
            NamingTemplate.FitToPathLength("C:\\" + new string('d', 252), "Scan", "pdf"));
        Assert.Equal(ScanErrorKind.ExportFailed, e.Kind);
        Assert.Equal("Saving failed: The path of the save folder is too long. Choose a folder with a shorter path. The pages are still in the queue.", e.Message);
    }

    [Fact]
    public void CombinedTemplate() =>
        Assert.Equal("Scan 2026-08-13 4", Render("Scan {date} {counter}", counter: 4));

    // MARK: - NamingContext and {task}

    private static string Render(string template, NamingContext context) =>
        new NamingTemplate(template).BaseFilename(context);

    [Fact]
    public void TaskToken_IsTheTasksFileLabel()
    {
        var context = new NamingContext(1, FixedDate(), ScanIntent.Photo) { Task = ScanTask.PhotoRestore };
        Assert.Equal("Restored photo 2026-08-13", Render("{task} {date}", context));
        Assert.Equal("Document 3", Render("{task} {counter}",
            new NamingContext(3, FixedDate(), ScanIntent.Document) { Task = ScanTask.Feeder }));
        Assert.Equal("Scan", Render("{task}",
            new NamingContext(1, FixedDate(), ScanIntent.Document) { Task = ScanTask.QuickScan }));
    }

    [Fact]
    public void TaskToken_WithoutATask_IsTheIntent()
    {
        Assert.Equal("Photos 2026-08-13", Render("{task} {date}", new NamingContext(1, FixedDate(), ScanIntent.Photo)));
        Assert.Equal("Document", Render("{task}", new NamingContext(1, FixedDate(), ScanIntent.Document)));
        // The old overload has no task.
        Assert.Equal("Photos", Render("{task}", intent: ScanIntent.Photo));
    }

    [Fact]
    public void Context_GivesTheSameNamesAsTheOldOverload()
    {
        foreach (string template in new[] { "Scan {date} {counter}", "{counter:3} {intent} {time}", "Photo", "Photo {index}" })
        {
            foreach (int? index in new int?[] { null, 4 })
            {
                Assert.Equal(Render(template, counter: 12, intent: ScanIntent.Photo, index: index),
                             Render(template, new NamingContext(12, FixedDate(), ScanIntent.Photo) { Index = index }));
            }
        }
    }

    [Fact]
    public void Context_IndexAndTaskTogether()
    {
        var context = new NamingContext(7, FixedDate(), ScanIntent.Photo) { Index = 2, Task = ScanTask.Photos };
        Assert.Equal("Photo 7 2", Render("{task} {counter}", context));
        Assert.Equal("Photo 2 of batch 7", Render("{task} {index} of batch {counter}", context));
    }

    [Fact]
    public void DocDateToken_IsTheDocumentsDate()
    {
        var context = new NamingContext(41, FixedDate(), ScanIntent.Document)
        {
            Task = ScanTask.Receipt,
            DocumentDate = new DocumentDate(2026, 3, 5),
        };
        Assert.Equal("Receipt 2026-03-05 41", Render("{task} {docdate} {counter}", context));
        // {date} stays the scan date.
        Assert.Equal("2026-03-05 scanned 2026-08-13", Render("{docdate} scanned {date}", context));
    }

    [Fact]
    public void LabelToken_IsTheDocumentsName_Sanitized()
    {
        var context = new NamingContext(14, FixedDate(), ScanIntent.Document) { Task = ScanTask.Batch, Label = "Invoice 0042" };
        Assert.Equal("Document Invoice 0042 2026-08-13 14", Render("Document {label} {date} {counter}", context));
        Assert.Equal("Invoice 0042", Render("{label}", context with { Label = "  Invoice 0042 " }));
        // Characters a file name cannot hold become "-"; tokens in a name are not expanded.
        Assert.Equal("ACME-Smith - 2026 Q3", Render("{label}", context with { Label = "ACME/Smith : 2026 Q3" }));
        // A name never makes folders, as a template's slash does.
        Assert.Equal("2026/ACME-", Render("{year}/{label}", context with { Label = "ACME/.." }));
        Assert.Equal("{date} 14", Render("{label} {counter}", context with { Label = "{date}" }));
    }

    [Fact]
    public void LabelToken_ALongName_IsCutBetweenCharacters_SoTheFileNameFits()
    {
        var context = new NamingContext(14, FixedDate(), ScanIntent.Document) { Task = ScanTask.Batch };
        // 120 bytes of UTF-8 at most.
        Assert.Equal(new string('a', 120), Render("{label}", context with { Label = new string('a', 300) }));
        Assert.Equal(new string('a', 120), Render("{label}", context with { Label = new string('a', 120) }));
        // Three bytes each: 40 of them; four bytes each (two UTF-16 units): 30, never half of one.
        Assert.Equal(new string('文', 40), Render("{label}", context with { Label = new string('文', 50) }));
        string emoji = string.Concat(Enumerable.Repeat("😀", 31));
        Assert.Equal(string.Concat(Enumerable.Repeat("😀", 30)), Render("{label}", context with { Label = emoji }));
        // Cut before a space: no space is left at the end.
        Assert.Equal("Document " + new string('b', 119) + " 2026-08-13 14",
                     Render("Document {label} {date} {counter}", context with { Label = new string('b', 119) + " cut here" }));
        string longest = Render("Document {label} {date} {counter}", context with { Label = new string('c', 1000) });
        Assert.True(System.Text.Encoding.UTF8.GetByteCount(longest) < 255, longest);
    }

    [Fact]
    public void LabelToken_WithoutAName_IsEmpty_AndTheDocumentsIndexIsAdded()
    {
        var context = new NamingContext(14, FixedDate(), ScanIntent.Document) { Task = ScanTask.Batch };
        Assert.Equal("Document 2026-08-13 14", Render("Document {label} {date} {counter}", context));
        Assert.Equal("Document 2026-08-13 14", Render("Document {label} {date} {counter}", context with { Label = "   " }));
        // The documents of a split queue are numbered like the photos of a batch.
        Assert.Equal("Document 2026-08-13 14 2", Render("Document {label} {date} {counter}", context with { Index = 2 }));
        Assert.Equal("Document Lease 2026-08-13 15 3",
                     Render("Document {label} {date} {counter}", context with { Counter = 15, Index = 3, Label = "Lease" }));
        // The old overload has no name.
        Assert.Equal("Scan", Render("{label}"));
    }

    [Fact]
    public void LabelWithoutTheToken_IsAppendedBeforeTheIndex()
    {
        var context = new NamingContext(14, FixedDate(), ScanIntent.Document) { Label = "Lease" };
        Assert.Equal("Scan 2026-08-13 14 Lease", Render("Scan {date} {counter}", context));
        Assert.Equal("Scan 2026-08-13 14 Lease 3", Render("Scan {date} {counter}", context with { Index = 3 }));
        Assert.Equal("Scan 2026-08-13 14", Render("Scan {date} {counter}", context with { Label = "   " }));
        // A template with {label} puts the name there only.
        Assert.Equal("Lease 14", Render("{label} {counter}", context));
    }

    [Fact]
    public void DocDateToken_WithoutADocumentDate_IsTheScanDate()
    {
        Assert.Equal("Receipt 2026-08-13 2", Render("Receipt {docdate} {counter}",
            new NamingContext(2, FixedDate(), ScanIntent.Document) { Task = ScanTask.Receipt }));
        // The old overload has no document date.
        Assert.Equal("2026-08-13", Render("{docdate}"));
        // In a batch the index is still added.
        Assert.Equal("Receipt 2026-03-05 3",
                     Render("Receipt {docdate}", new NamingContext(9, FixedDate(), ScanIntent.Document)
                     {
                         Index = 3,
                         DocumentDate = new DocumentDate(2026, 3, 5),
                     }));
    }

    [Fact]
    public void UniquePathLooksInTheFolderTheNameNames()
    {
        string dir = Path.Combine(Path.GetTempPath(), $"NamingTemplateTests-{Guid.NewGuid()}");
        Directory.CreateDirectory(Path.Combine(dir, "2026"));
        try
        {
            File.WriteAllBytes(Path.Combine(dir, "2026", "Scan.pdf"), []);
            Assert.Equal(Path.Combine(dir, "2026", "Scan 2.pdf"),
                         Path.GetFullPath(NamingTemplate.UniquePath(dir, "2026/Scan", "pdf")));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void UniquePathSuffixes()
    {
        string dir = Path.Combine(Path.GetTempPath(), $"NamingTemplateTests-{Guid.NewGuid()}");
        Directory.CreateDirectory(dir);
        try
        {
            string first = NamingTemplate.UniquePath(dir, "Report", "pdf");
            Assert.Equal("Report.pdf", Path.GetFileName(first));
            File.WriteAllBytes(first, []);

            string second = NamingTemplate.UniquePath(dir, "Report", "pdf");
            Assert.Equal("Report 2.pdf", Path.GetFileName(second));
            File.WriteAllBytes(second, []);

            string third = NamingTemplate.UniquePath(dir, "Report", "pdf");
            Assert.Equal("Report 3.pdf", Path.GetFileName(third));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void MoveToFreePathMovesToAFreeName()
    {
        string dir = Path.Combine(Path.GetTempPath(), $"NamingTemplateTests-{Guid.NewGuid()}");
        Directory.CreateDirectory(dir);
        try
        {
            string source = Path.Combine(dir, ".tmp");
            File.WriteAllText(source, "new");
            string target = Path.Combine(dir, "Report.pdf");
            Assert.Equal(target, NamingTemplate.MoveToFreePath(source, target));
            Assert.Equal("new", File.ReadAllText(target));
            Assert.False(File.Exists(source));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void MoveToFreePathNeverOverwritesAndTakesTheNextFreeSuffix()
    {
        string dir = Path.Combine(Path.GetTempPath(), $"NamingTemplateTests-{Guid.NewGuid()}");
        Directory.CreateDirectory(dir);
        try
        {
            // The name was free when it was picked, then two other files landed.
            string target = Path.Combine(dir, "Report.pdf");
            File.WriteAllText(target, "first");
            File.WriteAllText(Path.Combine(dir, "Report 2.pdf"), "second");
            string source = Path.Combine(dir, ".tmp");
            File.WriteAllText(source, "new");

            string written = NamingTemplate.MoveToFreePath(source, target);

            Assert.Equal(Path.Combine(dir, "Report 3.pdf"), written);
            Assert.Equal("first", File.ReadAllText(target));
            Assert.Equal("second", File.ReadAllText(Path.Combine(dir, "Report 2.pdf")));
            Assert.Equal("new", File.ReadAllText(written));
            Assert.False(File.Exists(source));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void MoveToFreePathRethrowsOtherFailures()
    {
        string dir = Path.Combine(Path.GetTempPath(), $"NamingTemplateTests-{Guid.NewGuid()}");
        Directory.CreateDirectory(dir);
        try
        {
            // A missing source is not a name collision: no retry loop, the error surfaces.
            Assert.Throws<FileNotFoundException>(() =>
                NamingTemplate.MoveToFreePath(Path.Combine(dir, "missing"), Path.Combine(dir, "Report.pdf")));
            Assert.Empty(Directory.GetFiles(dir));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }
}
