using System.IO;
using LazyScan.Core;

namespace LazyScan.App;

/// <summary>
/// Lazy Print for what is not saved yet: the queue and the ID card review. The pages are
/// written as a PDF in a folder of the temp directory and that file is opened in Lazy Print, which keeps
/// the path and reads the file again when it prints, so it stays after the app ends; a day later the next
/// hand-off deletes it. Twin of the Mac's AppState+LazyPrint.swift.
/// </summary>
public sealed partial class AppViewModel
{
    /// <summary>Lazy Print has registered its address for this user.</summary>
    public bool LazyPrintInstalled => _fileActions.LazyPrintInstalled();

    /// <summary>
    /// Opens the pages the queue would save (the ones left out stay out) as one PDF in Lazy Print.
    /// The queue is left as it is.
    /// </summary>
    public Task PrintQueueWithLazyPrint()
    {
        if (ScannedPages.Count == 0) return Task.CompletedTask;
        var s = PlainPdfSettings();
        return RunExclusive(async token =>
        {
            await Settled(_pageRotateChain);
            var queued = ScannedPages.Select(p => p.Page).ToList();
            if (queued.Count == 0) return;
            var plan = SavePlan.Make(queued, s.Document);
            if (plan.IsEmpty)
            {
                ErrorTitle = PageFilter.NothingSavedTitle;
                ErrorMessage = PageFilter.NothingToSaveMessage;
                StatusMessage = Loc.T("{0}.", DocumentSplitter.QueueSummary(queued, s.Document));
                return;
            }
            var pages = plan.Documents.SelectMany(d => d.Pages).ToList();
            OpenInLazyPrint(await WriteHandoff(pages, s, Loc.T("Scan|noun"), token));
        });
    }

    /// <summary>Opens the ID card's page, both sides at real size on the paper chosen, as a PDF in Lazy Print.</summary>
    public Task PrintIdCardWithLazyPrint()
    {
        if (IdCardFront is null) return Task.CompletedTask;
        var s = PlainPdfSettings();
        var paperInches = PaperSizes.Inches(IdCardPaperSize)!.Value;
        return RunExclusive(async token =>
        {
            await Settled(_recropChain);
            if (IdCardFront is not { } frontItem) return;
            var frontPhoto = frontItem.Photo;
            var backPhoto = IdCardBack?.Photo;
            int frontTurns = frontPhoto.RotationQuarterTurns, backTurns = backPhoto?.RotationQuarterTurns ?? 0;
            int dpi = IdCardComposer.PageDpi(frontPhoto.Dpi);
            var pageMode = IdCardComposer.PageColorMode(frontPhoto.ColorMode, backPhoto?.ColorMode);
            var page = await Task.Run(() =>
            {
                var f = IdCardSideOf(frontPhoto, frontTurns);
                var b = backPhoto is null ? null : IdCardSideOf(backPhoto, backTurns);
                return IdCardComposer.Compose(f, b, dpi, paperInches);
            }, token);
            OpenInLazyPrint(await WriteHandoff([new ScannedPage(page, dpi, pageMode)], s, Loc.T("ID card"), token));
        });
    }

    /// <summary>The settings with what the file does not need left off: Lazy Print reads it at once, so no text layer, password or PDF/A.</summary>
    private ScanSettings PlainPdfSettings()
    {
        var s = Settings.Clone();
        s.PdfSearchable = false;
        s.Output.Protect = false;
        s.Output.Archival = false;
        return s;
    }

    /// Writes the file for Lazy Print. Nothing was saved, so the status and the last PDF's size stay as they were.
    private async Task<string> WriteHandoff(List<ScannedPage> pages, ScanSettings s, string name, CancellationToken token)
    {
        var status = StatusMessage;
        var bytes = LastPdfBytes;
        var isProtected = LastPdfProtected;
        string path = await WritePdfAtomically(pages, s, HandoffPath(name), token);
        StatusMessage = status;
        LastPdfBytes = bytes;
        LastPdfProtected = isProtected;
        NotifyAll();
        return path;
    }

    private static string HandoffPath(string name)
    {
        string folder = HandoffFolder;
        Directory.CreateDirectory(folder);
        SweepHandoffs();
        return NamingTemplate.UniquePath(folder, name, "pdf");
    }

    private static string HandoffFolder => Path.Combine(Path.GetTempPath(), "LazyScan-print");

    /// <summary>Deletes the hand-off files that are a day old; run at launch and before each hand-off.</summary>
    private static void SweepHandoffs()
    {
        string folder = HandoffFolder;
        if (!Directory.Exists(folder)) return;
        var cutoff = DateTime.UtcNow - TimeSpan.FromDays(1);
        foreach (var file in new DirectoryInfo(folder).EnumerateFiles())
        {
            try { if (file.LastWriteTimeUtc < cutoff) file.Delete(); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        }
    }

    private void OpenInLazyPrint(string path)
    {
        if (!SaveActions.CanPrintWithLazyPrint([path]))
        {
            ErrorMessage = Loc.T("Lazy Print can't open this file.");
            return;
        }
        RunFileAction(FileAction.LazyPrint, [path]);
    }
}
