using LazyScan.Core;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Automation.Peers;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace LazyScan.App;

public partial class MainWindow
{
    private const double MinZoom = 0.1;
    private const double MaxZoom = 8;
    private const double MaxZoomedPixels = 16384;
    private const double ScrollStep = 48;

    /// <summary>Screen pixels per image pixel while zoomed; null while the page is fitted to the window.</summary>
    private double? _zoom;
    private RgbaImage? _stageImage;
    private Guid? _stagePageId;
    private Point? _panStart;
    private double _panX, _panY;

    /// <summary>
    /// Brings the page view in line with what the stage shows: a different page or scan starts
    /// fitted, the pill is there while there is an image, and a zoomed page is sized again.
    /// </summary>
    private void SyncZoom()
    {
        if (!ReferenceEquals(_stageImage, ViewModel.CanvasImage) || _stagePageId != ViewModel.ViewedPageId)
        {
            _stageImage = ViewModel.CanvasImage;
            _stagePageId = ViewModel.ViewedPageId;
            _zoom = null;
        }
        bool hasImage = CanvasImage.Source is BitmapSource && ViewModel.ViewedPageProblem is null;
        ZoomPill.Visibility = hasImage ? Visibility.Visible : Visibility.Collapsed;
        if (!hasImage) _zoom = null;
        if (_zoom is not null) DragChip.Visibility = Visibility.Collapsed;
        ApplyZoom();
    }

    private void ApplyZoom()
    {
        if (_zoom is { } zoom && CanvasImage.Source is BitmapSource source)
        {
            double dip = zoom / VisualTreeHelper.GetDpi(CanvasImage).DpiScaleX;
            CanvasImage.Width = source.PixelWidth * dip;
            CanvasImage.Height = source.PixelHeight * dip;
            CanvasImage.Effect = null;
            CanvasScroll.HorizontalScrollBarVisibility = ScrollBarVisibility.Auto;
            CanvasScroll.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
            CanvasScroll.PanningMode = PanningMode.Both;
            CanvasHost.Cursor = _panStart is null ? Cursors.Hand : Cursors.SizeAll;
        }
        else
        {
            CanvasImage.ClearValue(WidthProperty);
            CanvasImage.ClearValue(HeightProperty);
            CanvasImage.SetResourceReference(EffectProperty, "PageShadow");
            CanvasScroll.HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled;
            CanvasScroll.VerticalScrollBarVisibility = ScrollBarVisibility.Disabled;
            CanvasScroll.PanningMode = PanningMode.None;
            CanvasHost.ClearValue(CursorProperty);
        }
        SyncZoomButtons();
        UpdateMarquee();
    }

    private void SyncZoomButtons()
    {
        ZoomReadout.Text = Loc.T("{0}%", (int)Math.Round((_zoom ?? FitZoom()) * 100));
        ZoomFitButton.FontWeight = _zoom is null ? FontWeights.SemiBold : FontWeights.Normal;
        bool full = _zoom is { } zoom && Math.Abs(zoom - 1) < 0.005;
        ZoomFullButton.FontWeight = full ? FontWeights.SemiBold : FontWeights.Normal;
    }

    /// <summary>The scale the page has while it is fitted to the window, in screen pixels per image pixel.</summary>
    private double FitZoom()
    {
        if (CanvasImage.Source is not BitmapSource source) return 1;
        double margin = CanvasImage.Margin.Left;
        double cw = CanvasHost.ActualWidth - margin * 2;
        double ch = CanvasHost.ActualHeight - margin * 2;
        if (cw <= 0 || ch <= 0) return 1;
        double dip = Math.Min(cw / source.Width, ch / source.Height);
        return dip * source.Width * VisualTreeHelper.GetDpi(CanvasImage).DpiScaleX / source.PixelWidth;
    }

    private double ZoomLimit()
    {
        if (CanvasImage.Source is not BitmapSource source) return MaxZoom;
        return Math.Min(MaxZoom, MaxZoomedPixels / Math.Max(source.PixelWidth, source.PixelHeight));
    }

    /// <summary>
    /// Zooms to the scale, keeping the page point under <paramref name="anchor"/> (a point of the
    /// scroll area; its center by default) where it is.
    /// </summary>
    private void ZoomTo(double zoom, Point? anchor = null)
    {
        if (CanvasImage.Source is null) return;
        var at = anchor ?? new Point(CanvasScroll.ViewportWidth / 2, CanvasScroll.ViewportHeight / 2);
        double rx = PagePosition(at.X, CanvasScroll.HorizontalOffset, CanvasScroll.ViewportWidth, CanvasScroll.ExtentWidth);
        double ry = PagePosition(at.Y, CanvasScroll.VerticalOffset, CanvasScroll.ViewportHeight, CanvasScroll.ExtentHeight);
        _zoom = Math.Min(Math.Max(zoom, MinZoom), ZoomLimit());
        ApplyZoom();
        CanvasScroll.UpdateLayout();
        CanvasScroll.ScrollToHorizontalOffset(ScrollOffset(rx, at.X, CanvasScroll.ViewportWidth, CanvasScroll.ExtentWidth));
        CanvasScroll.ScrollToVerticalOffset(ScrollOffset(ry, at.Y, CanvasScroll.ViewportHeight, CanvasScroll.ExtentHeight));
    }

    // Where along the content (0 to 1) a point of the viewport is; content smaller than the
    // viewport sits in the middle of it.
    private static double PagePosition(double point, double offset, double viewport, double extent) =>
        (offset + point - Math.Max(0, (viewport - extent) / 2)) / Math.Max(extent, 1);

    private static double ScrollOffset(double position, double point, double viewport, double extent) =>
        position * extent + Math.Max(0, (viewport - extent) / 2) - point;

    private void ZoomBy(double factor, Point? anchor = null) => ZoomTo((_zoom ?? FitZoom()) * factor, anchor);

    private void ZoomFit()
    {
        _zoom = null;
        ApplyZoom();
    }

    private void AnnounceZoom()
    {
        var peer = UIElementAutomationPeer.FromElement(ZoomReadout) ?? UIElementAutomationPeer.CreatePeerForElement(ZoomReadout);
        peer?.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
    }

    private void ZoomOut_Click(object sender, RoutedEventArgs e)
    {
        ZoomBy(1 / 1.25);
        AnnounceZoom();
    }

    private void ZoomIn_Click(object sender, RoutedEventArgs e)
    {
        ZoomBy(1.25);
        AnnounceZoom();
    }

    private void ZoomFit_Click(object sender, RoutedEventArgs e)
    {
        ZoomFit();
        AnnounceZoom();
    }

    private void ZoomFull_Click(object sender, RoutedEventArgs e)
    {
        ZoomTo(1);
        AnnounceZoom();
    }

    private void CanvasScroll_PreviewMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (Keyboard.Modifiers == ModifierKeys.Control)
        {
            ZoomBy(Math.Pow(1.25, e.Delta / 120.0), e.GetPosition(CanvasScroll));
            e.Handled = true;
        }
        else if (Keyboard.Modifiers == ModifierKeys.Shift && _zoom is not null)
        {
            CanvasScroll.ScrollToHorizontalOffset(CanvasScroll.HorizontalOffset - e.Delta);
            e.Handled = true;
        }
    }

    private void CanvasHost_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (!CanvasHost.IsKeyboardFocusWithin || CanvasImage.Source is null) return;
        var modifiers = Keyboard.Modifiers;
        if (modifiers == ModifierKeys.Control)
        {
            e.Handled = true;
            switch (e.Key)
            {
                case Key.OemPlus or Key.Add: ZoomBy(1.25); break;
                case Key.OemMinus or Key.Subtract: ZoomBy(1 / 1.25); break;
                case Key.D0 or Key.NumPad0: ZoomFit(); break;
                case Key.D1 or Key.NumPad1: ZoomTo(1); break;
                default: e.Handled = false; break;
            }
            if (e.Handled) AnnounceZoom();
            return;
        }
        if (modifiers != ModifierKeys.None || !ReferenceEquals(Keyboard.FocusedElement, CanvasHost)) return;
        e.Handled = _zoom is null ? StepPageKey(e.Key) : ScrollKey(e.Key);
    }

    /// <summary>Fitted, the keys that would scroll move between the queued pages instead.</summary>
    private bool StepPageKey(Key key)
    {
        int count = ViewModel.ScannedPages.Count;
        int number = ViewModel.ViewedPageNumber;
        int target = key switch
        {
            Key.Left or Key.Up or Key.PageUp => number - 1,
            Key.Right or Key.Down or Key.PageDown => number + 1,
            Key.Home => 1,
            Key.End => count,
            _ => -1,
        };
        if (target < 0) return false;
        if (number > 0 && target >= 1 && target <= count && target != number)
        {
            ViewModel.ViewPage(ViewModel.ScannedPages[target - 1].Page.Id);
            RefreshFromViewModel();
            PageList.ScrollIntoView(ViewModel.ScannedPages[target - 1]);
        }
        return true;
    }

    private bool ScrollKey(Key key)
    {
        switch (key)
        {
            case Key.Left: CanvasScroll.ScrollToHorizontalOffset(CanvasScroll.HorizontalOffset - ScrollStep); break;
            case Key.Right: CanvasScroll.ScrollToHorizontalOffset(CanvasScroll.HorizontalOffset + ScrollStep); break;
            case Key.Up: CanvasScroll.ScrollToVerticalOffset(CanvasScroll.VerticalOffset - ScrollStep); break;
            case Key.Down: CanvasScroll.ScrollToVerticalOffset(CanvasScroll.VerticalOffset + ScrollStep); break;
            case Key.PageUp: CanvasScroll.ScrollToVerticalOffset(CanvasScroll.VerticalOffset - CanvasScroll.ViewportHeight); break;
            case Key.PageDown: CanvasScroll.ScrollToVerticalOffset(CanvasScroll.VerticalOffset + CanvasScroll.ViewportHeight); break;
            case Key.Home: CanvasScroll.ScrollToTop(); break;
            case Key.End: CanvasScroll.ScrollToBottom(); break;
            default: return false;
        }
        return true;
    }

    /// <summary>A zoomed page is dragged by hand; true when the press started a drag.</summary>
    private bool BeginPan(MouseButtonEventArgs e)
    {
        if (_zoom is null) return false;
        _panStart = e.GetPosition(CanvasHost);
        _panX = CanvasScroll.HorizontalOffset;
        _panY = CanvasScroll.VerticalOffset;
        CanvasHost.CaptureMouse();
        CanvasHost.Cursor = Cursors.SizeAll;
        return true;
    }

    private void Pan(MouseEventArgs e)
    {
        if (_panStart is not { } start) return;
        var p = e.GetPosition(CanvasHost);
        CanvasScroll.ScrollToHorizontalOffset(_panX - (p.X - start.X));
        CanvasScroll.ScrollToVerticalOffset(_panY - (p.Y - start.Y));
    }

    private void EndPan()
    {
        _panStart = null;
        if (_zoom is not null) CanvasHost.Cursor = Cursors.Hand;
    }
}
