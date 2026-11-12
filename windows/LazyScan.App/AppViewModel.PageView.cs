using System.Collections.Specialized;
using System.ComponentModel;
using System.Windows.Media.Imaging;
using LazyScan.App.Services;
using LazyScan.Core;

namespace LazyScan.App;

public sealed partial class AppViewModel
{
    /// <summary>The queued page the canvas shows large; null while the canvas shows the preview or last scan.</summary>
    public Guid? ViewedPageId { get; private set; }
    public bool ViewsPage => ViewedPageId is not null;
    /// <summary>The viewed page as it will be saved; the previous page's picture stays until this one is read.</summary>
    public BitmapSource? ViewedPageBitmap { get; private set; }
    /// <summary>Why the viewed page's picture could not be read; its thumbnail is shown instead.</summary>
    public string? ViewedPageProblem { get; private set; }
    /// <summary>The viewed page's place in the queue (1 for the first), 0 while none is viewed.</summary>
    public int ViewedPageNumber => ViewedPageId is { } id ? ScannedPages.ToList().FindIndex(p => p.Page.Id == id) + 1 : 0;

    private Guid? _lastViewedPageId;
    private int _pageViewRevision;

    public void ViewPage(Guid id)
    {
        if (IsBusy || ViewedPageId == id || !ScannedPages.Any(p => p.Page.Id == id)) return;
        ViewedPageId = id;
        _lastViewedPageId = id;
        ViewedPageProblem = null;
        LoadViewedPage();
        RaisePageViewChanged();
    }

    /// <summary>Back to the preview or the last scan; the page last viewed stays the one Page returns to.</summary>
    public void ShowPreview()
    {
        if (!ViewsPage) return;
        _pageViewRevision++;
        ViewedPageId = null;
        ViewedPageBitmap = null;
        ViewedPageProblem = null;
        RaisePageViewChanged();
    }

    /// <summary>The page last viewed, else the first one.</summary>
    public void ShowPage()
    {
        if ((_lastViewedPageId ?? ScannedPages.FirstOrDefault()?.Page.Id) is { } id) ViewPage(id);
    }

    private void RaisePageViewChanged() => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(string.Empty));

    private async void LoadViewedPage()
    {
        if (ViewedPageId is not { } id) return;
        int revision = ++_pageViewRevision;
        int index = ScannedPages.ToList().FindIndex(p => p.Page.Id == id);
        if (index < 0) return;
        var item = ScannedPages[index];
        int number = index + 1;
        BitmapSource? bitmap = null;
        string? problem = null;
        try
        {
            bitmap = await Task.Run(() =>
            {
                if (revision != Volatile.Read(ref _pageViewRevision)) return null;
                return WpfImageCodec.ToBitmapSource(PdfBuilder.PreparePage(item.Page, SpoolImage(item.Page), number).Image);
            });
        }
        catch (Exception)
        {
            problem = $"{Loc.T("Page {0} can't be opened", number)}\n{Loc.T("Its saved scan is missing or unreadable. Scan the page again.")}";
        }
        if (revision != _pageViewRevision) return;
        ViewedPageBitmap = bitmap ?? item.Thumbnail;
        ViewedPageProblem = problem;
        RaisePageViewChanged();
    }

    /// <summary>
    /// New pages bring the canvas back to the preview; a viewed page that is gone does too, and one
    /// whose pixels were replaced (turned, other version) is read again.
    /// </summary>
    private void KeepViewedPage(NotifyCollectionChangedEventArgs e)
    {
        if (e.Action == NotifyCollectionChangedAction.Add)
        {
            ShowPreview();
            return;
        }
        if (_lastViewedPageId is { } last && !ScannedPages.Any(p => p.Page.Id == last)) _lastViewedPageId = null;
        if (ViewedPageId is not { } id) return;
        if (!ScannedPages.Any(p => p.Page.Id == id)) ShowPreview();
        else if (e.Action == NotifyCollectionChangedAction.Replace) LoadViewedPage();
    }
}
