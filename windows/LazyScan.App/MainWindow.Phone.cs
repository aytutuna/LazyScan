using System.Collections.Specialized;
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
            if (!_phoneBarShowsSend) return;
            _phoneBarHasMessage = false;
            UpdatePhoneBar();
        };
        PhoneWaitingItems.ItemsSource = ViewModel.KeptPhoneDocuments;
        ViewModel.KeptPhoneDocuments.CollectionChanged += (_, e) =>
        {
            if (e.Action == NotifyCollectionChangedAction.Add && !_phoneWaitingOpened)
            {
                _phoneWaitingOpened = true;
                PhoneWaiting.IsExpanded = true;
            }
            UpdatePhoneBar();
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
        _phoneBarHasMessage = true;
        UpdatePhoneBar();
        var peer = UIElementAutomationPeer.FromElement(PhoneBarText) ?? UIElementAutomationPeer.CreatePeerForElement(PhoneBarText);
        peer?.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
        if (!IsActive && IsVisible) FlashTaskbarButton();
    }

    private bool _phoneBarHasMessage;

    /// <summary>The waiting list opens by itself the first time a document is kept in a run, then stays as the user left it.</summary>
    private bool _phoneWaitingOpened;

    /// <summary>The bar shows while it has a message or documents are waiting; Dismiss clears the message only.</summary>
    private void UpdatePhoneBar()
    {
        int kept = ViewModel.KeptPhoneDocuments.Count;
        var message = _phoneBarHasMessage ? Visibility.Visible : Visibility.Collapsed;
        PhoneBarText.Visibility = message;
        PhoneBarClose.Visibility = message;
        PhoneWaiting.Visibility = kept > 0 ? Visibility.Visible : Visibility.Collapsed;
        PhoneWaitingHeader.Text = Loc.T("Waiting ({0})", kept);
        AutomationProperties.SetName(PhoneWaitingHeader, Loc.Plural(kept, "Waiting, {0} document", "Waiting, {0} documents"));
        PhoneBar.Visibility = _phoneBarHasMessage || kept > 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    /// <summary>Whether the bar says where a file sent to a phone is, not what a phone sent.</summary>
    private bool _phoneBarShowsSend;

    /// <summary>Shows the state of files sent to a phone in the same bar: <paramref name="lead"/>, then the files.</summary>
    private void ShowPhoneSend(string lead, IReadOnlyList<string> paths)
    {
        ShowPhoneBar(lead, "· " + SavedBarLine(paths), send: true);
    }

    private void PhoneBarClose_Click(object sender, RoutedEventArgs e)
    {
        _phoneBarHasMessage = false;
        UpdatePhoneBar();
    }

    private void PhoneWaitingAdd_Click(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is AppViewModel.KeptPhoneDocument kept) ViewModel.AddKeptPhoneDocument(kept);
    }

    private void PhoneWaitingDiscard_Click(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is AppViewModel.KeptPhoneDocument kept) ViewModel.DiscardKeptPhoneDocument(kept);
    }

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
