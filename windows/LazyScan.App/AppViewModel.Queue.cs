using System.Collections.Specialized;
using System.ComponentModel;
using System.Windows.Threading;
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

    /// <summary>Stops recording: the spool folder goes with the queue on a normal exit.</summary>
    private void StopQueueRecord()
    {
        _queueRecordTimer?.Stop();
        _queueRecordTimer = null;
    }
}
