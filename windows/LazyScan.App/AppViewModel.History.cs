using System.IO;
using LazyScan.App.Services;
using LazyScan.Core;

namespace LazyScan.App;

/// <summary>
/// The Scans tab's Add to queue and Save: a history card's page, kept in a file for the session
/// (<see cref="ScanHistoryEntry.PageFile"/>), goes back to the end of the queue or is saved on its own
/// with the current save settings. The Mac does the same (Sources/LazyScanKit/App/AppState.swift,
/// AppState+HistorySave.swift).
/// </summary>
public sealed partial class AppViewModel
{
    /// <summary>The session's history pages; inside the spool folder, so it goes at quit and is swept after a crash.</summary>
    private string HistoryFolder => Path.Combine(_spool.Directory, "history");

    /// <summary>Actions asked for while an operation was running; each starts when the one before it ends.</summary>
    private readonly Queue<Func<Task>> _historyActions = new();

    /// <summary>
    /// One card per page, each page written to <paramref name="folder"/> as a PNG. The cards only display the
    /// bitmap, so the entries are metadata only and each preview's pixels are held once, not twice. A page
    /// that cannot be written gets an entry without a file.
    /// </summary>
    private static List<HistoryItem> MakeHistoryItems(IReadOnlyList<ScannedPage> pages, ScanIntent intent, string folder)
    {
        var entries = ScanHistory.MakeEntries(pages, intent, DateTime.Now);
        var items = new List<HistoryItem>();
        for (int i = 0; i < entries.Count; i++)
        {
            var e = entries[i];
            string? file = Path.Combine(folder, $"{e.Id}.png");
            try
            {
                Directory.CreateDirectory(folder);
                WpfImageCodec.Save(pages[i].Image, file, OutputFormat.Png, pages[i].Dpi, 1.0);
            }
            catch
            {
                file = null;
            }
            items.Add(new HistoryItem(
                new ScanHistoryEntry(e.Date, e.Intent, e.Dpi, HistoryItem.NoPixels, e.PixelSize, e.Id, e.ColorMode, file),
                WpfImageCodec.ToBitmapSource(e.Thumbnail)));
        }
        return items;
    }

    private static void DeleteHistoryFile(HistoryItem item)
    {
        if (item.Entry.PageFile is not { } file) return;
        try { File.Delete(file); } catch { /* best effort */ }
    }

    /// <summary>The page of a card as a spooled page of its own, or null when its file is gone or unreadable.</summary>
    private static ScannedPage? HistoryPage(ScanHistoryEntry entry, string spoolDirectory)
    {
        if (entry.PageFile is not { } file || !File.Exists(file)) return null;
        try
        {
            var page = new ScannedPage(WpfImageCodec.Load(file), entry.Dpi, entry.ColorMode);
            return SpoolPages([page], spoolDirectory)[0];
        }
        catch
        {
            return null;
        }
    }

    /// <summary>Runs <paramref name="action"/> now, or once the running operation has ended.</summary>
    private Task RunHistoryAction(Func<Task> action)
    {
        if (!IsBusy) return action();
        _historyActions.Enqueue(action);
        return Task.CompletedTask;
    }

    private void RunHistoryActionAfterWork()
    {
        if (IsBusy || !_historyActions.TryDequeue(out var action)) return;
        _ = action();
    }

    /// <summary>Stack turned over by hand, or a review open: the queue is left alone, as the imports leave it.</summary>
    private bool TurnedAwayFromQueue()
    {
        if (!IsStackUnderWay && !ShowPhotoReview && !ShowIdCardReview) return false;
        StatusMessage = DocumentSides.NotWhileTurningOverReason;
        return true;
    }

    /// <summary>Puts the page of <paramref name="item"/> at the end of the queue as a page of its own; the card stays.</summary>
    public Task AddToQueue(HistoryItem item) => RunHistoryAction(() => RunExclusive(async _ =>
    {
        if (TurnedAwayFromQueue()) return;
        string spoolDirectory = _spool.Directory;
        var page = await Task.Run(() => HistoryPage(item.Entry, spoolDirectory));
        if (page is null)
        {
            item.MarkPageGone();
            StatusMessage = Loc.T("Could not add the scan. Its full page is no longer available.");
            return;
        }
        SavedBarPaths = null;
        _heldCopy = null;
        ScannedPages.Add(new PageItem(page));
        StatusMessage = Loc.T("Added to the queue");
    }));

    /// <summary>
    /// Saves the page of <paramref name="item"/> on its own with the current save settings, as a scan saved at
    /// once is. A save that fails puts the page in the queue, as that one does.
    /// </summary>
    public Task SaveHistoryPage(HistoryItem item)
    {
        if (!item.CanSave) return Task.CompletedTask;
        item.SetSaving(true);
        return RunHistoryAction(() => RunExclusive(async token =>
        {
            try
            {
                string spoolDirectory = _spool.Directory;
                var page = await Task.Run(() => HistoryPage(item.Entry, spoolDirectory));
                if (page is null)
                {
                    item.MarkPageGone();
                    StatusMessage = Loc.T("Could not save the scan. Its full page is no longer available.");
                    return;
                }
                SavedBarPaths = null;
                _heldCopy = null;
                await SaveImmediately([page], Settings.Clone(), token);
            }
            finally
            {
                item.SetSaving(false);
            }
        }));
    }
}
