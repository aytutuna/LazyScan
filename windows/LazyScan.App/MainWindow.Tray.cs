using System.ComponentModel;
using System.Globalization;
using System.IO;
using System.Windows;
using LazyScan.Core;

namespace LazyScan.App;

/// <summary>
/// "Keep receiving when the window is closed": while it is on, an icon in the notification area carries
/// Open Lazy Scan and Exit, and closing the window hides it instead of ending the process, so the phone
/// link and the cloud folder watcher keep running. The icon exists only while the option is on.
/// </summary>
public partial class MainWindow
{
    private System.Windows.Forms.NotifyIcon? _tray;
    private System.Windows.Forms.ToolStripMenuItem? _trayStatus;
    /// <summary>Exit was chosen on the icon's menu, so the next close quits.</summary>
    private bool _trayExit;

    /// <summary>Turns the option on or off; returns whether it is on (the icon could not be made when not).</summary>
    internal bool SetKeepReceiving(bool on)
    {
        if (on && _tray is null && !TryCreateTray()) on = false;
        if (!on) RemoveTray();
        AppPreferencesStore.Update(preferences => preferences.KeepReceiving = on);
        return on;
    }

    /// <summary>Makes the icon at start when the option was left on.</summary>
    private void SetUpTray()
    {
        if (AppPreferencesStore.Load().KeepReceiving && !TryCreateTray())
        {
            AppPreferencesStore.Update(preferences => preferences.KeepReceiving = false);
        }
    }

    private bool TryCreateTray()
    {
        try
        {
            using var stream = Application.GetResourceStream(new Uri("pack://application:,,,/app.ico")).Stream;
            var open = new System.Windows.Forms.ToolStripMenuItem(Loc.T("Open Lazy Scan"));
            open.Font = new System.Drawing.Font(open.Font, System.Drawing.FontStyle.Bold);
            open.Click += (_, _) => ShowFromTray();
            _trayStatus = new System.Windows.Forms.ToolStripMenuItem { Enabled = false };
            var exit = new System.Windows.Forms.ToolStripMenuItem(Loc.T("Exit"));
            exit.Click += (_, _) => ExitFromTray();
            var menu = new System.Windows.Forms.ContextMenuStrip();
            menu.Items.AddRange([open, new System.Windows.Forms.ToolStripSeparator(), _trayStatus,
                                 new System.Windows.Forms.ToolStripSeparator(), exit]);
            menu.Opening += (_, _) => UpdateTray();
            _tray = new System.Windows.Forms.NotifyIcon
            {
                Icon = new System.Drawing.Icon(stream, System.Windows.Forms.SystemInformation.SmallIconSize),
                ContextMenuStrip = menu,
            };
            _tray.MouseClick += (_, e) =>
            {
                if (e.Button == System.Windows.Forms.MouseButtons.Left) ShowFromTray();
            };
            _tray.DoubleClick += (_, _) => ShowFromTray();
            UpdateTray();
            _tray.Visible = true;
            ViewModel.CompanionChanged += UpdateTray;
            return true;
        }
        catch (Exception e) when (e is Win32Exception or InvalidOperationException or ArgumentException or IOException)
        {
            RemoveTray();
            return false;
        }
    }

    private void RemoveTray()
    {
        ViewModel.CompanionChanged -= UpdateTray;
        if (_tray is null) return;
        _tray.Visible = false;
        _tray.ContextMenuStrip?.Dispose();
        _tray.Icon?.Dispose();
        _tray.Dispose();
        _tray = null;
        _trayStatus = null;
    }

    private void UpdateTray()
    {
        if (_tray is null || _trayStatus is null) return;
        bool receiving = ViewModel.Companion?.Snapshot().Listen == CompanionListenState.Listening;
        // The network cards already have the lower-case "not receiving" (the catalog ignores case).
        string notReceiving = Loc.T("not receiving");
        _trayStatus.Text = receiving ? Loc.T("Receiving from phone") : char.ToUpper(notReceiving[0], CultureInfo.CurrentUICulture) + notReceiving[1..];
        _tray.Text = Loc.T(receiving ? "Lazy Scan: receiving from phone" : "Lazy Scan: not receiving");
    }

    private void ShowFromTray()
    {
        if (!IsVisible) Show();
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Activate();
    }

    /// <summary>Quits through the usual close, with its questions about running or unsaved work.</summary>
    private void ExitFromTray()
    {
        ShowFromTray();
        if (_inClosingPrompt || System.Windows.Interop.ComponentDispatcher.IsThreadModal) return;
        _trayExit = true;
        Close();
    }
}
