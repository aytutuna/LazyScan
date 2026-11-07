using System.IO;
using System.Runtime.InteropServices;
using System.Security;
using LazyScan.Core;
using Microsoft.Win32;

namespace LazyScan.App.Services;

/// <summary>
/// Opens <c>.lsdoc</c> files and <c>lazyscan:</c> addresses with this app: the extension, its program id
/// and the scheme are written for the current user only (HKCU\Software\Classes, never HKLM), each start,
/// pointing at the exe that runs. The app has no installer, so nothing removes them; a value already
/// right is not written again. A bare <c>lazyscan:</c> only opens the app (Lazy Print does that); a pairing
/// code (<c>lazyscan://pair</c>) is pasted or scanned and is not read from the command line.
/// The Store package declares the extension and the scheme in its manifest and writes nothing.
/// </summary>
public static class FileAssociation
{
    public const string ProgId = "LazyScan.Package";
    public const string Scheme = "lazyscan";
    public static string FriendlyName => Loc.T("Lazy Scan document");

    /// <summary>The keys under Software\Classes and the value each gets (name "" is the default value), for the app at <paramref name="exePath"/>.</summary>
    public static IReadOnlyList<(string Key, string Name, string Value)> Entries(string exePath) =>
    [
        ("." + CompanionPackage.FileExtension, "", ProgId),
        (ProgId, "", FriendlyName),
        (ProgId + @"\DefaultIcon", "", $"\"{exePath}\",0"),
        (ProgId + @"\shell\open\command", "", $"\"{exePath}\" \"%1\""),
        (Scheme, "", "URL:Lazy Scan"),
        (Scheme, "URL Protocol", ""),
        (Scheme + @"\DefaultIcon", "", $"\"{exePath}\",0"),
        (Scheme + @"\shell\open\command", "", $"\"{exePath}\" \"%1\""),
    ];

    /// <summary><paramref name="arg"/> is a <c>lazyscan:</c> address.</summary>
    public static bool IsAddress(string arg) => arg.TrimStart().StartsWith(Scheme + ":", StringComparison.OrdinalIgnoreCase);

    /// <summary>Writes <see cref="Entries"/> under <paramref name="classes"/>; true when anything changed.</summary>
    public static bool Register(RegistryKey classes, string exePath)
    {
        bool changed = false;
        foreach (var (name, valueName, value) in Entries(exePath))
        {
            using var key = classes.CreateSubKey(name);
            if (key.GetValue(valueName) as string == value) continue;
            key.SetValue(valueName, value);
            changed = true;
        }
        return changed;
    }

    /// <summary>
    /// Registers the running exe for the current user and, when that changed anything, tells File
    /// Explorer so its icons follow. A policy that keeps the user's classes read-only leaves it as it was.
    /// </summary>
    public static void RegisterForCurrentUser()
    {
        if (Environment.ProcessPath is not { } exe) return;
        try
        {
            using var classes = Registry.CurrentUser.CreateSubKey(@"Software\Classes");
            RegisterForCurrentUser(classes, exe);
        }
        catch (Exception e) when (e is UnauthorizedAccessException or SecurityException or IOException)
        {
        }
    }

    /// <summary>The write of <see cref="RegisterForCurrentUser()"/> under <paramref name="classes"/>; nothing when packaged.</summary>
    public static void RegisterForCurrentUser(RegistryKey classes, string exePath)
    {
        if (Packaging.IsPackaged) return;
        if (Register(classes, exePath)) SHChangeNotify(ShcneAssocChanged, ShcnfIdList, IntPtr.Zero, IntPtr.Zero);
    }

    private const int ShcneAssocChanged = 0x08000000;
    private const uint ShcnfIdList = 0x0000;

    [DllImport("shell32.dll", ExactSpelling = true)]
    private static extern void SHChangeNotify(int eventId, uint flags, IntPtr item1, IntPtr item2);
}
