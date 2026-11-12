using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;

namespace LazyScan.App;

public partial class MainWindow
{
    // The format carries the page's id; the file drop and the scan area never see it.
    private const string PageDragFormat = "LazyScan.Page";

    private Guid? _dragPageId;
    private Point _dragStart;
    private PageDropMarker? _dropMarker;

    /// <summary>A press on a page (not on one of its buttons) may become a drag once the pointer moves.</summary>
    private void PageList_PreviewMouseDown(object sender, MouseButtonEventArgs e)
    {
        _dragPageId = null;
        if (ViewModel.IsBusy || e.OriginalSource is not DependencyObject source) return;
        for (DependencyObject? node = source; node is not null; node = node is Visual
            ? VisualTreeHelper.GetParent(node) : LogicalTreeHelper.GetParent(node))
        {
            if (node is ButtonBase or TextBoxBase) return;
            if (node is ListBoxItem { DataContext: PageItem item })
            {
                _dragPageId = item.Page.Id;
                _dragStart = e.GetPosition(PageList);
                return;
            }
        }
    }

    private void PageList_PreviewMouseUp(object sender, MouseButtonEventArgs e) => _dragPageId = null;

    private void PageList_PreviewMouseMove(object sender, MouseEventArgs e)
    {
        if (_dragPageId is not { } id) return;
        if (e.LeftButton != MouseButtonState.Pressed) { _dragPageId = null; return; }
        var offset = e.GetPosition(PageList) - _dragStart;
        if (Math.Abs(offset.X) < SystemParameters.MinimumHorizontalDragDistance
            && Math.Abs(offset.Y) < SystemParameters.MinimumVerticalDragDistance) return;
        _dragPageId = null;
        DragDrop.DoDragDrop(PageList, new DataObject(PageDragFormat, id.ToString()), DragDropEffects.Move);
        HideDropMarker();
    }

    private void PageList_DragOver(object sender, DragEventArgs e)
    {
        if (!e.Data.GetDataPresent(PageDragFormat)) return;
        e.Effects = ViewModel.IsBusy ? DragDropEffects.None : DragDropEffects.Move;
        e.Handled = true;
        if (ViewModel.IsBusy) return;
        var point = e.GetPosition(PageList);
        ScrollPagesNear(point.X);
        ShowDropMarker(InsertionIndex(point));
    }

    private void PageList_DragLeave(object sender, DragEventArgs e) => HideDropMarker();

    private void PageList_Drop(object sender, DragEventArgs e)
    {
        HideDropMarker();
        if (!e.Data.GetDataPresent(PageDragFormat)) return;
        e.Handled = true;
        if (e.Data.GetData(PageDragFormat) is not string text || !Guid.TryParse(text, out var id)) return;
        int from = ViewModel.ScannedPages.ToList().FindIndex(p => p.Page.Id == id);
        if (from < 0) return;
        int at = InsertionIndex(e.GetPosition(PageList));
        ViewModel.MovePageTo(id, at > from ? at - 1 : at);
        RefreshFromViewModel();
    }

    /// <summary>The place between pages (0 to the page count) that is nearest the pointer, in the strip's reading direction.</summary>
    private int InsertionIndex(Point point)
    {
        int? last = null;
        for (int i = 0; i < PageList.Items.Count; i++)
        {
            if (PageList.ItemContainerGenerator.ContainerFromIndex(i) is not ListBoxItem container) continue;
            if (ItemBounds(container).X + container.ActualWidth / 2 >= point.X) return i;
            last = i;
        }
        return last is { } l ? l + 1 : PageList.Items.Count;
    }

    private Rect ItemBounds(ListBoxItem container) =>
        container.TransformToAncestor(PageList).TransformBounds(new Rect(container.RenderSize));

    private void ShowDropMarker(int index)
    {
        int count = PageList.Items.Count;
        if (count == 0 || AdornerLayer.GetAdornerLayer(PageList) is not { } layer) return;
        bool last = index >= count;
        if (PageList.ItemContainerGenerator.ContainerFromIndex(last ? count - 1 : index) is not ListBoxItem container) return;
        var bounds = ItemBounds(container);
        // The leading edge of the page the drop goes before, or the trailing edge of the last page.
        if (_dropMarker is null)
        {
            _dropMarker = new PageDropMarker(PageList, (Brush)FindResource("AccentFillColorDefaultBrush"));
            layer.Add(_dropMarker);
        }
        _dropMarker.Set(last ? bounds.Right : bounds.Left, bounds.Top, bounds.Height);
    }

    private void HideDropMarker()
    {
        if (_dropMarker is null) return;
        AdornerLayer.GetAdornerLayer(PageList)?.Remove(_dropMarker);
        _dropMarker = null;
    }

    /// <summary>Scrolls a long strip while a page is held near either end.</summary>
    private void ScrollPagesNear(double x)
    {
        const double edge = 40;
        if (FindScrollViewer(PageList) is not { } scroll) return;
        if (x < edge) scroll.LineLeft();
        else if (x > PageList.ActualWidth - edge) scroll.LineRight();
    }

    private static ScrollViewer? FindScrollViewer(DependencyObject node)
    {
        for (int i = 0; i < VisualTreeHelper.GetChildrenCount(node); i++)
        {
            var child = VisualTreeHelper.GetChild(node, i);
            if (child is ScrollViewer scroll) return scroll;
            if (FindScrollViewer(child) is { } found) return found;
        }
        return null;
    }

    private sealed class PageDropMarker : Adorner
    {
        private readonly Brush _brush;
        private double _x, _top, _height;

        public PageDropMarker(UIElement target, Brush brush) : base(target)
        {
            _brush = brush;
            IsHitTestVisible = false;
        }

        public void Set(double x, double top, double height)
        {
            _x = x;
            _top = top;
            _height = height;
            InvalidateVisual();
        }

        protected override void OnRender(DrawingContext context) =>
            context.DrawRectangle(_brush, null, new Rect(_x - 1.5, _top, 3, _height));
    }
}
