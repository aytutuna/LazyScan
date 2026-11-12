using System.IO;
using LazyScan.Core;

namespace LazyScan.App;

/// <summary>
/// Undo after a save. A save keeps the pages it wrote, with their spool files, until the next scan, import or
/// save, and <see cref="UndoSave"/> deletes the files written and puts the pages back in the queue (or puts the
/// PDF the pages were added to back as it was). It shares the Undo button and Ctrl+Z with the removed pages: the
/// two holds never exist together, since a save leaves an empty queue. Nothing is kept across a restart.
/// The Mac and the iPhone do the same (Sources/LazyScanKit/App/AppState+Undo.swift).
/// </summary>
public sealed partial class AppViewModel
{
    /// <summary>A PDF the save added pages to: the copy taken of it first, how it was after the pages went in, and the target the next save was set to.</summary>
    private sealed record AppendedPdf(string Path, string Backup, (long Length, DateTime Written)? Stamp, string? EarlierTarget);

    /// <summary>What a save leaves for <see cref="UndoSave"/>: the pages it saved, the files it wrote (with how each was then), the PDF it added to and the steps it reset.</summary>
    private sealed class SavedHold
    {
        public required List<PageItem> Items { get; init; }
        public required List<string> Files { get; set; }
        public required Dictionary<string, (long Length, DateTime Written)?> Stamps { get; init; }
        public AppendedPdf? Appended { get; set; }
        public TaskFlow? Flow { get; init; }
    }

    private SavedHold? _saved;

    /// <summary>The last save can be taken back.</summary>
    public bool CanUndoSave => _saved is not null;

    /// <summary>The held save added pages to a PDF, which Undo puts back as it was.</summary>
    public bool UndoSaveRestoresPdf => _saved?.Appended is not null;

    /// <summary>Whether the held save wrote one file, for the tooltip.</summary>
    public bool UndoSaveWroteOneFile => _saved?.Files.Count == 1;

    private static (long Length, DateTime Written)? StampIfThere(string path) => File.Exists(path) ? StampOf(path) : null;

    /// <summary>
    /// A save's end: the queue leaves the strip. Its pages are held with their spool files for
    /// <see cref="UndoSave"/>, with the <paramref name="files"/> the save wrote and, for pages added to a PDF, the
    /// copy of it from before. A save that has nothing to go back to (<paramref name="undoable"/> false: a
    /// password-protected PDF, or no copy of the PDF) lets the spool files go.
    /// </summary>
    private void DropSaved(List<ScannedPage> queued, IEnumerable<string> files, bool undoable = true, AppendedPdf? appended = null)
    {
        if (undoable)
        {
            var written = files.ToList();
            _saved = new SavedHold
            {
                Items = [.. ScannedPages],
                Files = written,
                Stamps = written.ToDictionary(path => path, StampIfThere),
                Appended = appended,
                Flow = Flow?.Copy(),
            };
        }
        else
        {
            DeleteSpoolFiles(queued);
        }
        ScannedPages.Clear();
        // The record is written at once, so a crash within its delay cannot bring the saved pages back.
        QueueRecord.Write([], _spool.Directory);
    }

    /// <summary>
    /// Takes the last save back: deletes every file it wrote (one already gone is no error), puts the PDF it added
    /// pages to back from the copy taken before, and puts the pages in the queue again in their order, with their
    /// spool files and edits, the task's steps and the PDF to add to. A file changed since the save (another size
    /// or date) is kept and the undo refused, as is one that cannot be deleted or put back: the reason is shown and
    /// the save stays held, as far as it still stands. Returns the first page back in the queue, null when none came.
    /// </summary>
    public async Task<Guid?> UndoSave()
    {
        if (IsBusy || _saved is not { } held) return null;
        Guid? first = null;
        await RunExclusive(async _ =>
        {
            StatusMessage = Loc.T("Undoing the save…");
            NotifyAll();
            await Task.Run(() => TakeBack(held));
            _saved = null;
            SavedBarPaths = null;
            foreach (var item in held.Items) ScannedPages.Add(item);
            _queueLength = ScannedPages.Count;
            LastSavedPaths = [];
            SavedRevision++;
            if (held.Appended is { } appended) AppendTarget = appended.EarlierTarget;
            if (held.Flow is { } before && Flow is { } flow && flow.Steps.SequenceEqual(before.Steps)) Flow = before;
            StatusMessage = held.Appended is { } added
                ? Loc.T("Save undone: {0} is as it was, and the pages are in the queue again.", Path.GetFileName(added.Path))
                : Loc.T("Save undone: the pages are in the queue again.");
            first = held.Items.FirstOrDefault()?.Page.Id;
        });
        return first;
    }

    /// <summary>Puts the PDF back and deletes the files; throws what is wrong and leaves the rest held.</summary>
    private static void TakeBack(SavedHold held)
    {
        if (held.Appended is { } appended)
        {
            string name = Path.GetFileName(appended.Path);
            if (appended.Stamp is { } stamp && StampIfThere(appended.Path) != stamp)
            {
                throw new IOException(Loc.T("{0} was changed after the pages were added, so Undo left it as it is.", name));
            }
            try
            {
                File.Copy(appended.Backup, appended.Path, overwrite: true);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                throw new IOException(Loc.T("{0} could not be put back as it was: {1}", name, e.Message), e);
            }
            try { File.Delete(appended.Backup); } catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        }
        foreach (string path in held.Files)
        {
            if (held.Stamps[path] is { } stamp && StampIfThere(path) is { } now && now != stamp)
            {
                throw new IOException(Loc.T("{0} was changed after it was saved, so Undo left it as it is.", Path.GetFileName(path)));
            }
        }
        var failed = new List<(string Path, string Reason)>();
        foreach (string path in held.Files)
        {
            try { File.Delete(path); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { failed.Add((path, e.Message)); }
        }
        if (failed.Count == 0) return;
        // The ones deleted are gone; what is left stays held, to try again.
        held.Files = [.. failed.Select(f => f.Path)];
        throw new IOException(Loc.T("{0} could not be deleted: {1}", Path.GetFileName(failed[0].Path), failed[0].Reason));
    }

    /// <summary>Lets the held save go: its pages' spool files, the copy of the PDF and the spreads only they used.</summary>
    private void DiscardSaved()
    {
        if (_saved is not { } held) return;
        _saved = null;
        DeleteSpoolFiles(held.Items.Select(item => item.Page));
        if (held.Appended is { } appended)
        {
            try { File.Delete(appended.Backup); } catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        }
        PruneSpreads();
    }
}
