using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Markup;
using LazyScan.App.Services;
using LazyScan.Core;

namespace LazyScan.App;

public partial class App : Application
{
    /// <summary>Set on every window before it is shown, so the title bar mirrors with the content.</summary>
    public static FlowDirection Flow { get; private set; } = FlowDirection.LeftToRight;

    public static MessageBoxOptions BoxOptions { get; private set; } = MessageBoxOptions.None;

    private SingleInstance? _instance;

    protected override void OnStartup(StartupEventArgs e)
    {
        // A second copy hands its arguments to the first and ends; returning before base.OnStartup keeps
        // StartupUri from building a MainWindow. When the first does not answer this one starts as usual.
        _instance = SingleInstance.TryOwn(SingleInstance.DefaultName);
        if (_instance is null && SingleInstance.Send(SingleInstance.DefaultName, e.Args))
        {
            Shutdown();
            return;
        }
        _instance?.Listen(args => Dispatcher.BeginInvoke(() => (MainWindow as MainWindow)?.OpenFromOtherProcess(args)));
        // Apply the saved appearance before the first window is created.
        ThemeService.Initialize();
        TextScale.Initialize();
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
        // A metadata default on Window throws, and on FrameworkElement it would also flip images and print pages.
        if (ui.TextInfo.IsRightToLeft)
        {
            Flow = FlowDirection.RightToLeft;
            BoxOptions = MessageBoxOptions.RtlReading | MessageBoxOptions.RightAlign;
        }
        base.OnStartup(e);
    }
}
