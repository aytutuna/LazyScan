using System.Globalization;
using System.Windows;
using System.Windows.Markup;

namespace LazyScan.App;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        // Apply the saved appearance before the first window is created.
        ThemeService.Initialize();
        // Bindings format with en-US unless the language property says otherwise.
        FrameworkElement.LanguageProperty.OverrideMetadata(typeof(FrameworkElement),
            new FrameworkPropertyMetadata(XmlLanguage.GetLanguage(CultureInfo.CurrentCulture.IetfLanguageTag)));
        base.OnStartup(e);
    }
}
