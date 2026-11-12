using System.Runtime.InteropServices;

namespace LazyScan.App.Scanning.Twain;

/// <summary>
/// Brings the windows a helper process shows (the driver's settings window) forward. The helper
/// owns them and shows them without an owner, so they can open behind the app.
/// </summary>
internal static class DriverWindows
{
    private const int RestoreCommand = 9;
    private const uint FlashAll = 3;
    private const uint FlashUntilForeground = 12;

    /// <summary>Raises the process's visible top-level windows, or flashes their taskbar buttons when Windows keeps them back. False when it has none.</summary>
    public static bool Raise(int processId)
    {
        var windows = new List<IntPtr>();
        EnumWindows((window, _) =>
        {
            GetWindowThreadProcessId(window, out uint owner);
            if (owner == (uint)processId && IsWindowVisible(window)) windows.Add(window);
            return true;
        }, IntPtr.Zero);
        if (windows.Count == 0) return false;

        AllowSetForegroundWindow(processId);
        foreach (var window in windows)
        {
            if (IsIconic(window)) ShowWindowAsync(window, RestoreCommand);
            SetForegroundWindow(window);
            if (GetForegroundWindow() == window) continue;
            var flash = new FlashInfo
            {
                Size = (uint)Marshal.SizeOf<FlashInfo>(),
                Window = window,
                Flags = FlashAll | FlashUntilForeground,
                Count = uint.MaxValue,
            };
            FlashWindowEx(ref flash);
        }
        return true;
    }

    private delegate bool EnumWindowsProc(IntPtr window, IntPtr parameter);

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
    private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);

    [DllImport("user32.dll", ExactSpelling = true)]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(IntPtr window);

    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsIconic(IntPtr window);

    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShowWindowAsync(IntPtr window, int command);

    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(IntPtr window);

    [DllImport("user32.dll", ExactSpelling = true)]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AllowSetForegroundWindow(int processId);

    [DllImport("user32.dll", ExactSpelling = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool FlashWindowEx(ref FlashInfo info);
}
