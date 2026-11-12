using System.Collections.Specialized;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Threading;
using LazyScan.App.Services;
using LazyScan.Core;

namespace LazyScan.App;

public sealed partial class AppViewModel
{
    /// <summary>How long after the queue last changed its record is written, so a batch of changes writes once.</summary>
    private static readonly TimeSpan QueueRecordDelay = TimeSpan.FromMilliseconds(500);

    private DispatcherTimer? _queueRecordTimer;

    /// <summary>Records the queue beside the spool whenever it changes, for pages to be found again after a crash.</summary>
    private void KeepQueueRecord()
    {
        var timer = new DispatcherTimer(DispatcherPriority.Background, _dispatcher) { Interval = QueueRecordDelay };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            QueueRecord.Write([.. ScannedPages.Select(item => item.Page)], _spool.Directory);
        };
        _queueRecordTimer = timer;
        ScannedPages.CollectionChanged += QueueChanged;
    }

    private void QueueChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        foreach (PageItem item in e.OldItems ?? Array.Empty<PageItem>()) item.PropertyChanged -= QueuedPageChanged;
        foreach (PageItem item in e.NewItems ?? Array.Empty<PageItem>())
        {
            item.PropertyChanged -= QueuedPageChanged;
            item.PropertyChanged += QueuedPageChanged;
        }
        ScheduleQueueRecord();
    }

    private void QueuedPageChanged(object? sender, PropertyChangedEventArgs e) => ScheduleQueueRecord();

    private void ScheduleQueueRecord()
    {
        _queueRecordTimer?.Stop();
        _queueRecordTimer?.Start();
    }

    /// <summary>The queues earlier sessions left in their spool folders, with the folder each one is in.</summary>
    private List<(string Folder, QueueRecord Record)> _leftBehind = [];

    /// <summary>
    /// How many pages earlier sessions that did not end cleanly left in the spool, to offer back at startup.
    /// A folder none of whose pages can be read is removed here.
    /// </summary>
    public int FindLeftBehind()
    {
        _leftBehind = [];
        if (TaskCatalog.FlowOf(Settings) != TaskFlowKind.DocumentQueue) return 0;
        foreach (string folder in _spool.LeftBehind)
        {
            var record = QueueRecord.Read(folder);
            if (record is null) DeleteFolder(folder);
            else _leftBehind.Add((folder, record));
        }
        return _leftBehind.Sum(found => found.Record.Pages.Count);
    }

    /// <summary>Deletes the pages <see cref="FindLeftBehind"/> found.</summary>
    public void DiscardLeftBehind()
    {
        foreach (var (folder, _) in _leftBehind) DeleteFolder(folder);
        _leftBehind = [];
    }

    /// <summary>
    /// Brings back the pages <see cref="FindLeftBehind"/> found, as an operation of its own: their files move
    /// into this session's spool, and a page whose file cannot be read is left out.
    /// </summary>
    public Task RestoreLeftBehind()
    {
        var found = _leftBehind;
        _leftBehind = [];
        int queued = found.Sum(f => f.Record.Queued ?? f.Record.Pages.Count);
        string spool = _spool.Directory;
        return RunExclusive(async token =>
        {
            StatusMessage = Loc.Plural(found.Sum(f => f.Record.Pages.Count),
                "Bringing back {0} page…", "Bringing back {0} pages…");
            NotifyAll();
            var items = await Task.Run(() => BringBack(found, spool));
            foreach (var item in items) ScannedPages.Add(item);
            StatusMessage = items.Count == 0 ? Loc.T("The pages kept from last time could not be read.")
                : items.Count < queued ? Loc.T("Pages back from last time: {0} of {1}.", items.Count, queued)
                : Loc.Plural(items.Count, "{0} page is back from last time.", "{0} pages are back from last time.");
        });
    }

    private static List<PageItem> BringBack(List<(string Folder, QueueRecord Record)> found, string spool)
    {
        var items = new List<PageItem>();
        foreach (var (folder, record) in found)
        {
            foreach (var recorded in record.Pages)
            {
                try
                {
                    string path = Path.Combine(spool, recorded.File);
                    File.Move(Path.Combine(folder, recorded.File), path);
                    if (recorded.AlternateFile is { } other)
                    {
                        try { File.Move(Path.Combine(folder, other), Path.Combine(spool, other)); }
                        catch (IOException) { recorded.AlternateFile = null; }
                    }
                    var preview = ScanHistory.MakePreview(WpfImageCodec.Load(path), SpoolPreviewMaxSide);
                    items.Add(new PageItem(recorded.ToPage(ImagePipeline.Rotate(preview, recorded.RotationQuarterTurns), spool)));
                }
                catch (Exception e) when (e is IOException or UnauthorizedAccessException or InvalidDataException or NotSupportedException
                                      or FileFormatException or COMException or ArgumentException
                                      or InvalidOperationException or OverflowException or OutOfMemoryException)
                {
                    System.Diagnostics.Trace.TraceWarning($"A page from the last session could not be brought back: {e.Message}");
                }
            }
            DeleteFolder(folder);
        }
        return items;
    }

    private static void DeleteFolder(string folder)
    {
        try { Directory.Delete(folder, recursive: true); } catch { /* best effort */ }
    }

    /// <summary>Stops recording: the spool folder goes with the queue on a normal exit.</summary>
    private void StopQueueRecord()
    {
        _queueRecordTimer?.Stop();
        _queueRecordTimer = null;
    }
}
