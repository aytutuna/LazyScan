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
        // A second copy hands its arguments to the first and ends; a command-line scan runs without a window.
        // Clearing StartupUri is what keeps either from building a MainWindow. When the first does not answer
        // this one starts as usual. A command-line scan is its own process: it neither hands over nor takes the name.
        bool scan = ScanCommand.IsScan(e.Args);
        _instance = scan ? null : SingleInstance.TryOwn(SingleInstance.DefaultName);
        if (!scan && _instance is null && SingleInstance.Send(SingleInstance.DefaultName, e.Args))
        {
            StartupUri = null;
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
        if (scan)
        {
            StartupUri = null;
            RunScanCommand(e.Args);
            return;
        }
        base.OnStartup(e);
    }

    private async void RunScanCommand(string[] args)
    {
        int code = ScanCommand.BadArguments;
        if (ScanCommand.Parse(args) is { } command)
        {
            ShutdownMode = ShutdownMode.OnExplicitShutdown;
            code = await command.RunAsync(new AppViewModel(), Console.Error);
        }
        else
        {
            Console.Error.WriteLine(ScanCommand.Usage);
        }
        Shutdown(code);
    }
}
