using System.Windows;
using System.Windows.Media;
using Windows.UI.ViewManagement;

namespace LazyScan.App;

/// <summary>
/// Follows Settings > Accessibility > Text size by scaling the content of every window. WPF does not
/// read that setting itself.
/// </summary>
public static class TextScale
{
    private static UISettings? _settings;

    public static void Initialize()
    {
        if (_settings is not null) return;
        _settings = new UISettings();
        // Raised on a thread-pool thread.
        _settings.TextScaleFactorChanged += (_, _) =>
            Application.Current?.Dispatcher.BeginInvoke(() =>
            {
                foreach (Window window in Application.Current.Windows) Apply(window);
            });
        EventManager.RegisterClassHandler(typeof(Window), FrameworkElement.LoadedEvent,
            new RoutedEventHandler((sender, e) =>
            {
                if (ReferenceEquals(sender, e.OriginalSource)) Apply((Window)sender);
            }));
    }

    public static double Factor => _settings is { TextScaleFactor: > 1 and var f } ? f : 1;

    private static void Apply(Window window)
    {
        if (window.Content is not FrameworkElement content) return;
        double factor = Factor;
        content.LayoutTransform = factor > 1 ? new ScaleTransform(factor, factor) : Transform.Identity;
    }
}
