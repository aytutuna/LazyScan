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
        var ui = CultureInfo.GetCultureInfo(Loc.Resolve(CultureInfo.CurrentUICulture.Name, shipped));
        CultureInfo.DefaultThreadCurrentUICulture = ui;
        CultureInfo.CurrentUICulture = ui;
        // Bindings format with en-US unless the language property says otherwise.
        FrameworkElement.LanguageProperty.OverrideMetadata(typeof(FrameworkElement),
            new FrameworkPropertyMetadata(XmlLanguage.GetLanguage(CultureInfo.CurrentCulture.IetfLanguageTag)));
        base.OnStartup(e);
    }
}
