using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Interop;
using LazyScan.Core;

namespace LazyScan.App;

/// <summary>
/// The phone link in the main window: the Phone button opens <see cref="PhoneWindow"/>, and when a
/// paired phone's document is added to the queue (or waits for it) a bar says so and the taskbar
/// button flashes if the window is in the background.
/// </summary>
public partial class MainWindow
{
    private void SetUpPhone()
    {
        ViewModel.PhoneDocumentArrived += ShowPhoneBar;
        ViewModel.PhoneSendChanged += ShowPhoneSend;
        ViewModel.PhoneSendCleared += () =>
        {
            if (_phoneBarShowsSend) PhoneBar.Visibility = Visibility.Collapsed;
        };
    }

    private void PhoneButton_Click(object sender, RoutedEventArgs e)
    {
        new PhoneWindow(ViewModel) { Owner = this }.ShowDialog();
    }

    /// <summary>Shows <paramref name="message"/> in the bar above the window content and announces it.</summary>
    private void ShowPhoneBar(string message) => ShowPhoneBar(Loc.T("From your phone"), message, send: false);

    private void ShowPhoneBar(string lead, string message, bool send)
    {
        _phoneBarShowsSend = send;
        PhoneBarLead.Text = lead;
        PhoneBarMessage.Text = message;
        PhoneBar.Visibility = Visibility.Visible;
        var peer = UIElementAutomationPeer.FromElement(PhoneBarText) ?? UIElementAutomationPeer.CreatePeerForElement(PhoneBarText);
        peer?.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
        if (!IsActive && IsVisible) FlashTaskbarButton();
    }

    /// <summary>Whether the bar says where a file sent to a phone is, not what a phone sent.</summary>
    private bool _phoneBarShowsSend;

    /// <summary>Shows the state of files sent to a phone in the same bar: <paramref name="lead"/>, then the files.</summary>
    private void ShowPhoneSend(string lead, IReadOnlyList<string> paths)
    {
        ShowPhoneBar(lead, "· " + SavedBarLine(paths), send: true);
    }

    private void PhoneBarClose_Click(object sender, RoutedEventArgs e) => PhoneBar.Visibility = Visibility.Collapsed;

    /// <summary>Flashes the taskbar button until the window comes to the front (FlashWindowEx).</summary>
    private void FlashTaskbarButton()
    {
        var handle = new WindowInteropHelper(this).Handle;
        if (handle == IntPtr.Zero) return;
        var info = new FlashInfo
        {
            Size = (uint)Marshal.SizeOf<FlashInfo>(),
            Window = handle,
            Flags = FlashTray | FlashTimerNoForeground,
            Count = 3,
            Timeout = 0,
        };
        FlashWindowEx(ref info);
    }

    private const uint FlashTray = 0x00000002;
    private const uint FlashTimerNoForeground = 0x0000000C;

    [StructLayout(LayoutKind.Sequential)]
    private struct FlashInfo
    {
        public uint Size;
        public IntPtr Window;
        public uint Flags;
        public uint Count;
        public uint Timeout;
    }

    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool FlashWindowEx(ref FlashInfo info);
}
