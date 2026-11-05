using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Markup;
using LazyScan.Core;

namespace LazyScan.App;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        // Apply the saved appearance before the first window is created.
        ThemeService.Initialize();
        // Texts come from the satellite folder of the nearest shipped language; the format culture stays.
        var shipped = Directory.GetDirectories(AppContext.BaseDirectory)
            .Where(d => File.Exists(Path.Combine(d, "LazyScan.Core.resources.dll")))
            .Select(Path.GetFileName).OfType<string>().ToHashSet(StringComparer.OrdinalIgnoreCase);
        var tag = CultureInfo.CurrentUICulture.Name;
#if DEBUG
        tag = Environment.GetEnvironmentVariable("LAZYSCAN_UI_CULTURE") is { Length: > 0 } forced ? forced : tag;
#endif
        var ui = CultureInfo.GetCultureInfo(Loc.Resolve(tag, shipped));
        CultureInfo.DefaultThreadCurrentUICulture = ui;
        CultureInfo.CurrentUICulture = ui;
        // Bindings format with en-US unless the language property says otherwise.
        FrameworkElement.LanguageProperty.OverrideMetadata(typeof(FrameworkElement),
            new FrameworkPropertyMetadata(XmlLanguage.GetLanguage(CultureInfo.CurrentCulture.IetfLanguageTag)));
        // A metadata default would also flip images and off-screen print pages, so mirror the windows themselves.
        if (ui.TextInfo.IsRightToLeft)
            EventManager.RegisterClassHandler(typeof(Window), FrameworkElement.LoadedEvent,
                new RoutedEventHandler((s, _) => ((Window)s!).FlowDirection = FlowDirection.RightToLeft));
        base.OnStartup(e);
    }
}
