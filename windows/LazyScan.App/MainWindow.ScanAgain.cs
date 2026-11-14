using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using LazyScan.Core;

namespace LazyScan.App;

/// <summary>
/// Scan again after: the choice in the Scanner section, and the countdown between passes, where the
/// Scan button becomes Stop. The loop itself is <see cref="AppViewModel.StopScanAgain"/>'s counterpart in the view model.
/// </summary>
public partial class MainWindow
{
    private static readonly int[] ScanAgainChoices = [0, 3, 5, 10];

    private bool _scanAgainAnnounced;

    private void FillScanAgainChoices()
    {
        foreach (int seconds in ScanAgainChoices)
        {
            var item = new ComboBoxItem
            {
                Content = seconds == 0 ? Loc.T("Off") : Loc.T("{0} s", seconds),
                Tag = seconds,
            };
            AutomationProperties.SetName(item, seconds == 0 ? Loc.T("Off") : Loc.T("{0} seconds", seconds));
            ScanAgainBox.Items.Add(item);
        }
    }

    private void SelectScanAgain(int seconds)
    {
        ScanAgainBox.SelectedItem = ScanAgainBox.Items.OfType<ComboBoxItem>().FirstOrDefault(i => (int)i.Tag == seconds)
            ?? ScanAgainBox.Items[0];
    }

    private void SyncScanAgain()
    {
        ScanAgainRow.Visibility = ViewModel.OffersScanAgain ? Visibility.Visible : Visibility.Collapsed;
        int? left = ViewModel.IsBusy ? null : ViewModel.ScanAgainRemaining;
        bool counting = left is not null;
        ScanAgainCountdown.Visibility = counting ? Visibility.Visible : Visibility.Collapsed;
        PreviewButton.IsEnabled &= !counting;
        if (!counting)
        {
            _scanAgainAnnounced = false;
            global::LazyScan.App.Icon.SetGlyph(ScanButton, "\uE8FE");
            AutomationProperties.SetAcceleratorKey(ScanButton, "Ctrl+Enter");
            ScanButton.ClearValue(AutomationProperties.NameProperty);
            return;
        }
        string text = Loc.T("Scanning again in {0} s", left!.Value);
        ScanAgainCountdown.Text = text;
        AutomationProperties.SetName(ScanAgainCountdown, text);
        ScanButton.IsEnabled = true;
        ScanButton.Content = Loc.T("Stop");
        ScanButton.ToolTip = Loc.T("Stop scanning again (Esc)");
        global::LazyScan.App.Icon.SetGlyph(ScanButton, "\uE71A");
        AutomationProperties.SetAcceleratorKey(ScanButton, "Esc");
        AutomationProperties.SetName(ScanButton, Loc.T("Stop scanning again"));
        // Read once when the countdown starts, not on every second.
        if (_scanAgainAnnounced) return;
        _scanAgainAnnounced = true;
        var peer = UIElementAutomationPeer.FromElement(ScanAgainCountdown) ?? UIElementAutomationPeer.CreatePeerForElement(ScanAgainCountdown);
        peer?.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
    }
}
