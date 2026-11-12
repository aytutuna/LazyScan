using System.IO;
using LazyScan.App.Services;
using LazyScan.Core;

namespace LazyScan.App;

/// <summary>
/// Adding the queued pages to the end of an existing PDF the user picks (Add to existing PDF… under
/// the queue, or a PDF's menu in the Saved tab), as an incremental update (<see cref="PdfAppender"/>).
/// The Mac and the iPhone add pages the same way (Sources/LazyScanKit/App/AppState+Append.swift).
/// A PDF picked before scanning (<see cref="AppendTarget"/>) is checked when it is picked
/// (<see cref="CheckAppendTarget"/>) and takes the queue when it is saved, which reads it again.
/// </summary>
public sealed partial class AppViewModel
{
    /// <summary>
    /// Asks whether to add pages to a file despite what <see cref="PdfAppendTarget.Warnings"/> say (a
    /// signed file, a PDF/A level the pages may not keep): the window shows a Yes/No question; no
    /// answer, or nobody to ask, adds nothing.
    /// </summary>
    public Func<string, bool>? ConfirmAppend { get; set; }

    /// <summary>
    /// The PDF Save adds the queue to instead of writing a new file (the start screen's "Add pages to
    /// a PDF"); null otherwise. Kept for this session only.
    /// </summary>
    public string? AppendTarget { get; private set; }

    // The file CheckAppendTarget asked its question about, as it was then; Save does not ask again
    // while it is unchanged.
    private (string Path, long Length, DateTime Written)? _confirmedAppend;

    private static (long Length, DateTime Written) StampOf(string path)
    {
        var info = new FileInfo(path);
        return (info.Length, info.LastWriteTimeUtc);
    }

    /// <summary>
    /// Reads the PDF at <paramref name="path"/> before it becomes the append target, so a file that can
    /// never take the pages (password-protected, damaged, read-only, open in another app) is refused now
    /// with what to do, and the signed or PDF/A question is asked now. True when the file can take them
    /// (and the question, if any, got a yes): the caller then calls <see cref="SetAppendTarget"/>.
    /// </summary>
    public async Task<bool> CheckAppendTarget(string path)
    {
        try
        {
            var (target, stamp) = await Task.Run(() =>
            {
                var inspected = PdfAppender.Inspect(path);
                return (inspected, StampOf(path));
            });
            if (target.ConfirmMessage is { } question && ConfirmAppend?.Invoke(question) != true) return false;
            _confirmedAppend = (path, stamp.Length, stamp.Written);
            return true;
        }
        catch (Exception e)
        {
            ErrorMessage = e.Message;
            NotifyAll();
            return false;
        }
    }

    /// <summary>
    /// Makes Save add the queue to <paramref name="path"/> (read when the pages are added, not now)
    /// until the pages are in or <see cref="ClearAppendTarget"/> is called.
    /// </summary>
    public void SetAppendTarget(string path)
    {
        AppendTarget = path;
        NotifyAll();
    }

    /// <summary>Save writes a new file again.</summary>
    public void ClearAppendTarget()
    {
        AppendTarget = null;
        _confirmedAppend = null;
        NotifyAll();
    }

    /// <summary>There are pages to add (some are not left out) and nothing else is running.</summary>
    public bool CanAppendPages =>
        !IsBusy && !SidesNeedOrder && SavePlan.Make([.. ScannedPages.Select(p => p.Page)], Settings.Document).PageCount > 0;

    /// <summary>
    /// Adds the pages the queue would save (all its documents, in order; pages left out stay out) to
    /// the end of <paramref name="targetPath"/>, stored as the PDF size and the text layer settings
    /// say. The file is read first: a password-protected, damaged or unreadable file, or one that
    /// is read-only or open in another app, is refused with what to do, and the pages stay in the
    /// queue. The file decides the rest: no password is added (the password switch is for new
    /// files) and a PDF/A file stays one where it can (<see cref="PdfAppender.KeepsPdfA"/>), with a
    /// question first where it may not, or where it is signed. Once the pages are in, the queue is
    /// cleared and the file is offered like a saved one, with the after-save action, and the
    /// <see cref="AppendTarget"/> is cleared.
    /// </summary>
    public Task AppendToPdf(string targetPath)
    {
        if (ScannedPages.Count == 0 || !SettleSides()) return Task.CompletedTask;
        var s = Settings.Clone();
        return RunExclusive(async token =>
        {
            // Let page rotations that were clicked before land first.
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
            string name = Path.GetFileName(targetPath);
            StatusMessage = Loc.T("Reading {0}…", name);
            NotifyAll();
            var (target, stamp) = await Task.Run(() => (PdfAppender.Inspect(targetPath), StampOf(targetPath)), token);
            bool answered = targetPath == AppendTarget && _confirmedAppend is { } done
                            && done.Path == targetPath && done.Length == stamp.Length && done.Written == stamp.Written;
            if (!answered && target.ConfirmMessage is { } question && ConfirmAppend?.Invoke(question) != true)
            {
                StatusMessage = Loc.T("Nothing was added to {0}.", name);
                return;
            }
            var pages = plan.Documents.SelectMany(d => d.Pages).ToList();
            StatusMessage = s.PdfSearchable ? Loc.T("Running OCR and adding pages…") : Loc.T("Adding pages…");
            NotifyAll();
            var failures = new PdfTextFailures();
            var inputs = await PdfPageInputs(pages, s, token, failures: failures);
            SetStatus(Loc.Plural(pages.Count, "Adding {0} page to {1}…", "Adding {0} pages to {1}…", name), new(new StatusHead.AddingPages(pages.Count)));
            NotifyAll();
            var result = await Task.Run(() => PdfAppender.AppendToFile(targetPath, inputs, progress: null, token), token);
            LastPdfBytes = result.Bytes;
            LastPdfProtected = false;
            MarkSaved([result.Path]);
            AppendTarget = null;
            _confirmedAppend = null;
            DeleteSpoolFiles(queued);
            ScannedPages.Clear();
            ResetFlow();
            SaveName = "";
            if (failures.Note is { } layerNote) ErrorMessage = layerNote;
            var message = PdfAppender.AddedMessage(pages.Count, name, result.PageCount, SavedFiles.SizeText(result.Bytes))
                          + plan.LeftOutNote();
            SetStatus(s.Output.Protect ? Loc.T("{0}. {1}", message, PdfAppender.NoPasswordNote) : message,
                      new(new StatusHead.PagesAdded(pages.Count, null, 0, 0)));
            RunAfterSave(s.Output.AfterSave, [result.Path]);
        });
    }
}
