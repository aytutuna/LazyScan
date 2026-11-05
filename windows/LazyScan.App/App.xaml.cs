using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
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

    protected override void OnStartup(StartupEventArgs e)
    {
        // A bare lazyscan: address carries nothing to open, so a window already open is brought forward instead of a
        // second copy. Returning before base.OnStartup keeps StartupUri from building a MainWindow.
        if (e.Args.Length > 0 && FileAssociation.IsAddress(e.Args[0]) && ShowRunningWindow())
        {
            Shutdown();
            return;
        }
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
        // A metadata default on Window throws, and on FrameworkElement it would also flip images and print pages.
        if (ui.TextInfo.IsRightToLeft)
        {
            Flow = FlowDirection.RightToLeft;
            BoxOptions = MessageBoxOptions.RtlReading | MessageBoxOptions.RightAlign;
        }
        base.OnStartup(e);
    }

    /// <summary>Brings the window of another Lazy Scan in this session forward; false when there is none.</summary>
    private static bool ShowRunningWindow()
    {
        using var self = Process.GetCurrentProcess();
        foreach (var other in Process.GetProcessesByName(self.ProcessName))
        {
            using (other)
            {
                if (other.Id == self.Id || other.SessionId != self.SessionId || other.MainWindowHandle == IntPtr.Zero) continue;
                if (IsIconic(other.MainWindowHandle)) ShowWindow(other.MainWindowHandle, SwRestore);
                SetForegroundWindow(other.MainWindowHandle);
                return true;
            }
        }
        return false;
    }

    private const int SwRestore = 9;

    [DllImport("user32.dll")]
    private static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int cmdShow);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);
}
