using LazyScan.Core;
using Xunit;

namespace LazyScan.Core.Tests;

// Twin of Tests/LazyScanTests/StatusLineTests.swift: the status line's six words.
public class StatusLineTests
{
    private static StatusDetail Added(int count, int? queue, int blank = 0, int split = 0, StatusWarning? warning = null) =>
        new(new StatusHead.PagesAdded(count, queue, blank, split), warning is null ? null : [warning]);

    [Fact]
    public void Short_IsShortAndFactual()
    {
        var cases = new (string Message, StatusDetail Detail, string Expected)[]
        {
            ("Added 1 page — 3 in queue. Scan more or Save PDF.", Added(1, 3), "Page 3 added"),
            ("Added 6 pages, both sides of each sheet — 6 in queue. Scan more or Save PDF. 1 looks blank and will be skipped.",
             Added(6, 6, blank: 1), "6 pages added · 1 blank"),
            ("Added 2 pages — 4 in queue. Scan more or Save PDF. 1 spread split into pages. Spine shadow softened on 2 pages.",
             Added(2, 4, split: 1), "2 pages added · 1 spread split"),
            ("Added 2 pages from Aytu's iPhone — 3 in queue.", Added(2, 3), "2 pages added"),
            ("Added 1 page to Contract.pdf (now 4 pages, 1.1 MB)", Added(1, null), "1 page added"),
            ("Saved 3-page PDF: Scan 2026-10-20 1.pdf (497.7 KB)", new(new StatusHead.Saved()), "Saved"),
            (@"Saved 3 photos to C:\Users\me\files", new(new StatusHead.SavedFiles(3, FileKind.Photo)), "Saved 3 photos"),
            ("Saved 2 receipts: a.pdf, b.pdf", new(new StatusHead.SavedFiles(2, FileKind.Receipt)), "Saved 2 receipts"),
            ("Saved 1 PDF (7 pages): A.pdf", new(new StatusHead.SavedFiles(1, FileKind.Pdf)), "Saved 1 PDF"),
            ("Found 3 photos.", new(new StatusHead.Found(3, FileKind.Photo)), "Found 3 photos"),
            ("Found 1 receipt.", new(new StatusHead.Found(1, FileKind.Receipt)), "Found 1 receipt"),
            ("Front scanned. Turn the card over where it lies and scan the back, or skip it.", new(), "Front scanned"),
            ("Back scanned. Check the sides, then save.", new(), "Back scanned"),
            ("Page queue cleared.", new(new StatusHead.QueueCleared()), "Queue cleared"),
            ("Ready — Demo Scanner", new(), "Ready — Demo Scanner"),
            ("Overview ready — drag on the preview to select an area, then Scan.", new(), "Overview ready"),
            ("Overview ready — tap the preview to choose the scan area, then Scan.", new(), "Overview ready"),
            ("Scanning…", new(), "Scanning…"),
            ("Reading the text of page 3 of 12…", new(new StatusHead.ReadingPage(3, 12)), "Reading page 3 of 12…"),
            ("Reading the text of page 3…", new(new StatusHead.ReadingPage(3, null)), "Reading page 3…"),
            ("Adding 3 pages to Scan 2026-10-20 1.pdf…", new(new StatusHead.AddingPages(3)), "Adding 3 pages…"),
            ("Sent the ruler test page to Office Laser. At real size each square measures 1 inch.",
             new(new StatusHead.SentToPrinter()), "Sent to the printer"),
            ("3 pages sent to MacBook.", new(), "3 pages sent to MacBook"),
            ("9 pages · 3 documents.", new(), "9 pages · 3 documents"),
            ("9 pages · 3 documents · 2 separator pages skipped.", new(), "9 pages · 3 documents"),
            ("12 pages · 4 documents · 2 separator pages and 1 blank skipped.", new(), "12 pages · 4 documents"),
            ("24 pages · 5 blank skipped.", new(), "24 pages · 5 blank skipped"),
        };
        foreach (var (message, detail, expected) in cases)
        {
            Assert.Equal(expected, StatusLine.Short(message, detail));
        }
    }

    [Fact]
    public void Short_CutsAtASentenceThatOpensWithAnIsolate()
    {
        var saved = System.Globalization.CultureInfo.CurrentUICulture;
        try
        {
            System.Globalization.CultureInfo.CurrentUICulture = System.Globalization.CultureInfo.GetCultureInfo("ar");
            Assert.Equal("Document \u20682\u2069 starts at page \u20685\u2069",
                StatusLine.Short("Document \u20682\u2069 starts at page \u20685\u2069. \u20685\u2069 pages follow."));;
        }
        finally
        {
            System.Globalization.CultureInfo.CurrentUICulture = saved;
        }
    }

    [Fact]
    public void Short_ReadsCountsWithThousandsSeparators()
    {
        var culture = System.Globalization.CultureInfo.CurrentCulture;
        try
        {
            System.Globalization.CultureInfo.CurrentCulture = System.Globalization.CultureInfo.GetCultureInfo("en-US");
            Assert.Equal("Page 1,000 added", StatusLine.Short("Added 1 page — 1,000 in queue.", Added(1, 1000)));
            Assert.Equal("Found 1,200 photos", StatusLine.Short("Found 1,200 photos.", new(new StatusHead.Found(1200, FileKind.Photo))));
        }
        finally
        {
            System.Globalization.CultureInfo.CurrentCulture = culture;
        }
    }

    [Fact]
    public void Short_ReadyForATask_NamesTheScannerInstead()
    {
        var ready = new StatusDetail(new StatusHead.ReadyForTask());
        Assert.Equal("Ready — Demo Scanner", StatusLine.Short("Ready for “Document to PDF”.", ready, "Demo Scanner"));
        Assert.Equal("Ready", StatusLine.Short("Ready for “Document to PDF”.", ready));
        Assert.Equal("", StatusLine.Short("   "));
    }

    [Theory]
    [InlineData("Could not connect to the Epson Perfection V600 Photo scanner over the network.")]
    [InlineData("Scanned 3 front sides before the feeder stopped. Load the rest of the stack and scan, or turn it over.")]
    [InlineData("The ID card task ended during the scan. Nothing of the card was kept.")]
    [InlineData("A very long message without any punctuation that goes on and on about nothing in particular")]
    public void Short_NeverShowsMoreThanSixWords(string message)
    {
        string shown = StatusLine.Short(message);
        Assert.InRange(StatusLine.Words(shown), 1, StatusLine.MaxWords);
    }

    [Fact]
    public void Short_OfALongSentence_EndsWithAnEllipsis()
    {
        Assert.Equal("A very long message without any…",
                     StatusLine.Short("A very long message without any punctuation that goes on and on about nothing in particular"));
        Assert.Equal("Could not connect to the Epson…",
                     StatusLine.Short("Could not connect to the Epson Perfection V600 Photo scanner over the network."));
        Assert.Equal("Scanned 3 front sides before the…",
                     StatusLine.Short("Scanned 3 front sides before the feeder stopped. Load the rest of the stack and scan, or turn it over."));
    }

    /// <summary>The status after settings met a scanner, as the apps build it: the message, then each note.</summary>
    private static (string Message, StatusDetail Detail) WithNotes(string message, ScanSettings settings, ScannerCapabilities capabilities,
                                                                   StatusHead? head = null)
    {
        var notes = SettingsAdapter.Adapt(settings, capabilities).Notes;
        Assert.NotEmpty(notes);
        return ($"{message} {string.Join(" ", notes.Select(n => n.Message))}", new StatusDetail(head, notes.Select(n => n.Warning).ToList(), message));
    }

    [Fact]
    public void Short_KeepsASettingChangedForTheScanner_AsAShortWarning()
    {
        // A preset at 600 dpi on a scanner that tops out at 300.
        var resolution = WithNotes("Applied preset “Invoices”.", new ScanSettings { Resolution = 600 },
                                   new ScannerCapabilities { SupportedResolutions = [150, 300] });
        Assert.Equal("Applied preset “Invoices” · 300 dpi used", StatusLine.Short(resolution.Message, resolution.Detail));
        // A longer preset name leaves no room: the warning wins.
        var longName = WithNotes("Applied preset “Monthly office invoices”.", new ScanSettings { Resolution = 600 },
                                 new ScannerCapabilities { SupportedResolutions = [150, 300] });
        Assert.Equal("300 dpi used", StatusLine.Short(longName.Message, longName.Detail));
        // A scanner without a flatbed connects: no full stop before the note, and the name stays.
        var feeder = WithNotes("Ready — Demo Scanner", new ScanSettings { Source = ScanSource.Flatbed },
                               new ScannerCapabilities { Sources = [ScanSource.DocumentFeeder], FeederSizeInches = new(8.5, 14) });
        Assert.Equal("Ready — Demo Scanner · feeder used", StatusLine.Short(feeder.Message, feeder.Detail));
        // A task is picked: "Ready — device" and the note.
        var picked = WithNotes("Ready for “Document to PDF”.", new ScanSettings { Source = ScanSource.Flatbed },
                               new ScannerCapabilities { Sources = [ScanSource.DocumentFeeder], FeederSizeInches = new(8.5, 14) },
                               new StatusHead.ReadyForTask());
        Assert.Equal("Ready — Demo Scanner · feeder used", StatusLine.Short(picked.Message, picked.Detail, "Demo Scanner"));
        var flatbed = WithNotes("Ready — Demo Scanner", new ScanSettings { Source = ScanSource.DocumentFeeder },
                                new ScannerCapabilities { Sources = [ScanSource.Flatbed] });
        Assert.Equal("Ready — Demo Scanner · flatbed used", StatusLine.Short(flatbed.Message, flatbed.Detail));
        var paper = WithNotes("Ready — Demo Scanner", new ScanSettings { PaperSize = PaperSize.Legal },
                              new ScannerCapabilities());
        Assert.Equal("Ready — Demo Scanner · paper size Automatic", StatusLine.Short(paper.Message, paper.Detail));
        var sides = WithNotes("Ready — Demo Scanner", new ScanSettings { Source = ScanSource.DocumentFeeder, Duplex = DuplexMode.Both },
                              new ScannerCapabilities { Sources = [ScanSource.DocumentFeeder], FeederSizeInches = new(8.5, 14) });
        Assert.Equal("Ready — Demo Scanner · two-sided by hand", StatusLine.Short(sides.Message, sides.Detail));
        // Every note at once: as many as fit, then how many more.
        var all = WithNotes("Ready — Demo Scanner",
                            new ScanSettings { Source = ScanSource.Flatbed, Duplex = DuplexMode.Both, PaperSize = PaperSize.Legal, Resolution = 600 },
                            new ScannerCapabilities { Sources = [ScanSource.DocumentFeeder], FeederSizeInches = new(8.5, 11), SupportedResolutions = [300] });
        Assert.Equal("Feeder used · two-sided by hand +2", StatusLine.Short(all.Message, all.Detail));
        foreach (var status in new[] { resolution, longName, feeder, picked, flatbed, paper, sides, all })
        {
            Assert.InRange(StatusLine.Words(StatusLine.Short(status.Message, status.Detail, "Demo Scanner")), 1, StatusLine.MaxWords);
        }
    }

    [Fact]
    public void Short_ATwoSidedScanThatCameBackOneSided_SaysSo()
    {
        Assert.Equal("3 pages added · one side only", StatusLine.Short(
            "Added 3 pages, one side of each sheet: the scanner did not scan both sides — 3 in queue. Scan more or Save PDF.",
            Added(3, 3, warning: new StatusWarning.OneSideOnly())));
        Assert.Equal("Page 4 added · one side only", StatusLine.Short(
            "Added 1 page, one side of each sheet: the scanner did not scan both sides — 4 in queue. Scan more or Save PDF.",
            Added(1, 4, warning: new StatusWarning.OneSideOnly())));
    }

    private static void WithTable(Dictionary<string, string> table, Action body)
    {
        Loc.Table = table;
        try { body(); }
        finally { Loc.Table = null; }
    }

    [Fact]
    public void Short_CutsTheFirstSentence_OfTextWithoutCase()
    {
        Assert.Equal("\u0627\u0644\u0648\u062C\u0647 \u0645\u0645\u0633\u0648\u062D",
                     StatusLine.Short("\u0627\u0644\u0648\u062C\u0647 \u0645\u0645\u0633\u0648\u062D. \u0627\u0642\u0644\u0628 \u0627\u0644\u0628\u0637\u0627\u0642\u0629 \u0648\u0627\u0645\u0633\u062D \u0627\u0644\u062E\u0644\u0641 \u0623\u0648 \u062A\u062C\u0627\u0648\u0632\u0647."));
        Assert.Equal("\u8868\u9762\u3092\u30B9\u30AD\u30E3\u30F3\u3057\u307E\u3057\u305F",
                     StatusLine.Short("\u8868\u9762\u3092\u30B9\u30AD\u30E3\u30F3\u3057\u307E\u3057\u305F\u3002\u88CF\u9762\u3092\u30B9\u30AD\u30E3\u30F3\u3057\u3066\u304F\u3060\u3055\u3044\u3002"));
    }

    [Fact]
    public void Short_WorksWithTextInAnyLanguage()
    {
        WithTable(new()
        {
            ["{0} page added|other"] = "{0} sayfa eklendi",
            ["Page {0} added"] = "{0}. sayfa eklendi",
            ["Saved {0} photo|other"] = "{0} fotoğraf kaydedildi",
            ["Saved"] = "Kaydedildi",
            ["Queue cleared"] = "Sıra temizlendi",
            ["{0} dpi used"] = "{0} dpi kullanıldı",
            ["One side only"] = "Tek yüz",
            ["one side only|after another fact"] = "tek yüz",
            ["Feeder used"] = "Besleyici",
        }, () =>
        {
            // Nothing in the sentence is read: any words do for the same kind of message.
            Assert.Equal("3 sayfa eklendi · tek yüz",
                         StatusLine.Short("Kuyruğa 3 sayfa eklendi.", Added(3, 5, warning: new StatusWarning.OneSideOnly())));
            Assert.Equal("5. sayfa eklendi", StatusLine.Short("Kuyruğa bir sayfa eklendi.", Added(1, 5)));
            Assert.Equal("3 fotoğraf kaydedildi",
                         StatusLine.Short("3 fotoğraf kaydedildi: C:\\x", new(new StatusHead.SavedFiles(3, FileKind.Photo))));
            Assert.Equal("Sıra temizlendi", StatusLine.Short("Sıra temizlendi.", new(new StatusHead.QueueCleared())));
            // Under the saved files' bar: "Saved", with the warnings.
            Assert.Equal("Kaydedildi · 600 dpi kullanıldı",
                         StatusLine.Shown("Dosya kaydedildi.", new(new StatusHead.Saved(), [new StatusWarning.DpiUsed(600)]), null,
                                          reviewShown: false, savedShown: true));
            Assert.Equal(["Besleyici", "300 dpi kullanıldı"],
                         StatusLine.Warnings(new(null, [new StatusWarning.FeederUsed(), new StatusWarning.DpiUsed(300)])));
        });
    }

    [Fact]
    public void Short_CountsTheEnglishWords_WhateverTheLanguage()
    {
        WithTable(new() { ["feeder used|after another fact"] = "besleyici kullanıldı bu sefer lütfen not alın" }, () =>
        {
            var detail = Added(3, 3, warning: new StatusWarning.FeederUsed());
            Assert.Equal("3 pages added · besleyici kullanıldı bu sefer lütfen not alın", StatusLine.Short("Added 3 pages — 3 in queue.", detail));
        });
    }

    [Fact]
    public void Words_CountsTokensWithALetterOrDigit()
    {
        Assert.Equal(3, StatusLine.Words("Ready — Demo Scanner"));
        Assert.Equal(5, StatusLine.Words("6 pages added · 1 blank"));
        Assert.Equal(0, StatusLine.Words(" — · "));
    }

    [Fact]
    public void Saved_WithASettingChangedForTheScanner_KeepsTheWarning()
    {
        // Capabilities read after a scan saved at once add their note to "Saved …".
        var notes = SettingsAdapter.Adapt(new ScanSettings { Resolution = 1200 },
                                          new ScannerCapabilities { SupportedResolutions = [300, 600] }).Notes;
        string message = $"Saved Scan 2026-10-20 1.pdf (412 KB) {string.Join(" ", notes.Select(n => n.Message))}";
        var detail = new StatusDetail(new StatusHead.Saved(), notes.Select(n => n.Warning).ToList(), "Saved Scan 2026-10-20 1.pdf (412 KB)");
        Assert.Equal(["600 dpi used"], StatusLine.Warnings(detail));
        Assert.Equal("Saved · 600 dpi used", StatusLine.Shown(message, detail, null, reviewShown: false, savedShown: true));
        Assert.Equal("Saved · 600 dpi used", StatusLine.Short(message, detail));
        // Without a note, just the head.
        var plain = new StatusDetail(new StatusHead.Saved());
        Assert.Empty(StatusLine.Warnings(plain));
        Assert.Equal("Saved", StatusLine.Shown("Saved Scan 2026-10-20 1.pdf (412 KB)", plain, null, reviewShown: false, savedShown: true));
        // Too many to fit with the head: the warnings win, as on any other line.
        var all = SettingsAdapter.Adapt(
            new ScanSettings { Source = ScanSource.Flatbed, Duplex = DuplexMode.Both, PaperSize = PaperSize.Legal, Resolution = 600 },
            new ScannerCapabilities { Sources = [ScanSource.DocumentFeeder], FeederSizeInches = new(8.5, 11), SupportedResolutions = [300] }).Notes;
        string many = $"Saved Scan 2026-10-20 1.pdf (412 KB) {string.Join(" ", all.Select(n => n.Message))}";
        var manyDetail = new StatusDetail(new StatusHead.Saved(), all.Select(n => n.Warning).ToList());
        string shown = StatusLine.Shown(many, manyDetail, null, reviewShown: false, savedShown: true);
        Assert.Equal(StatusLine.Short(many, manyDetail), shown);
        Assert.InRange(StatusLine.Words(shown), 1, StatusLine.MaxWords);
    }

    [Fact]
    public void Shown_IsEmptyUnderAReview_AndSavedWhileTheSavedFilesShow()
    {
        var found = new StatusDetail(new StatusHead.Found(3, FileKind.Photo));
        Assert.Equal("", StatusLine.Shown("Found 3 photos.", found, "Demo Scanner", reviewShown: true, savedShown: false));
        Assert.Equal("", StatusLine.Shown("Back scanned. Check the sides, then save.", new(), "Demo Scanner", reviewShown: true, savedShown: false));
        Assert.Equal("Saved", StatusLine.Shown("Saved 3-page PDF: Scan 2026-10-20 1.pdf (497.7 KB)", new(new StatusHead.Saved()), null,
                                               reviewShown: false, savedShown: true));
        Assert.Equal("Saved", StatusLine.Shown("Saved 3 photos to C:\\x\\files", new(new StatusHead.SavedFiles(3, FileKind.Photo)), null,
                                               reviewShown: false, savedShown: true));
        // Not about a save: the short line, whatever the bar.
        Assert.Equal("Page 3 added", StatusLine.Shown("Added 1 page — 3 in queue. Scan more or Save PDF.", Added(1, 3), null,
                                                      reviewShown: false, savedShown: true));
        Assert.Equal("Ready — Demo Scanner", StatusLine.Shown("Ready for “Photos”.", new(new StatusHead.ReadyForTask()), "Demo Scanner",
                                                              reviewShown: false, savedShown: false));
    }
}
