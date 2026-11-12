using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Documents;
using System.Windows.Navigation;
using LazyScan.Core;

namespace LazyScan.App;

/// <summary>The app's version, support and website links, and the license and third-party notices files.</summary>
public partial class AboutWindow : Window
{
    public AboutWindow()
    {
        FlowDirection = App.Flow;
        InitializeComponent();
        VersionText.Text = Loc.T("Version {0}", AppInfo.Version);
        PackageText.Text = AppInfo.IsPackaged ? Loc.T("Microsoft Store") : Loc.T("Not packaged");
        AutomationProperties.SetName(VersionBlock, $"{Loc.T("Lazy Scan")}, {VersionText.Text}, {PackageText.Text}");
    }

    private void Link_RequestNavigate(object sender, RequestNavigateEventArgs e)
    {
        e.Handled = true;
        string name = sender is Hyperlink { Inlines.FirstInline: Run run } ? run.Text : e.Uri.AbsoluteUri;
        Open(e.Uri.AbsoluteUri, name);
    }

    private void License_Click(object sender, RoutedEventArgs e) =>
        Open(Path.Combine(AppContext.BaseDirectory, "LICENSE.txt"), Loc.T("License"));

    private void Notices_Click(object sender, RoutedEventArgs e) =>
        Open(Path.Combine(AppContext.BaseDirectory, "THIRD-PARTY-NOTICES.txt"), Loc.T("Third-party notices"));

    /// <summary>Opens a link or a file with the default app; a refusal is shown in the footer.</summary>
    private void Open(string target, string name)
    {
        FooterStatus.Text = "";
        try
        {
            if (Path.IsPathRooted(target) && !File.Exists(target)) throw new FileNotFoundException();
            Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
        }
        catch (Exception e) when (e is IOException or Win32Exception)
        {
            FooterStatus.Text = Loc.T("Could not open {0}.", name);
        }
    }
}
