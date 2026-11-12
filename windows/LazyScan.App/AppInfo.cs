using System.Reflection;
using System.Runtime.InteropServices;
using LazyScan.App.Services;
using Windows.ApplicationModel;

namespace LazyScan.App;

/// <summary>The app's version and whether it runs from the Microsoft Store package.</summary>
public static class AppInfo
{
    private static readonly Lazy<(bool Packaged, string Version)> Identity = new(ReadIdentity);

    public static bool IsPackaged => Identity.Value.Packaged;

    public static string Version => Identity.Value.Version;

    /// <summary>First line of the copied diagnostics. Stays English, like the rest of the report.</summary>
    public static string DiagnosticsLine =>
        $"Lazy Scan {Version} ({(IsPackaged ? "Microsoft Store" : "Not packaged")}), " +
        $"Windows {Environment.OSVersion.Version.ToString(3)}, {RuntimeInformation.ProcessArchitecture.ToString().ToLowerInvariant()}";

    private static (bool, string) ReadIdentity()
    {
        if (Packaging.IsPackaged)
        {
            var v = Package.Current.Id.Version;
            return (true, $"{v.Major}.{v.Minor}.{v.Build}");
        }
        var assembly = typeof(AppInfo).Assembly;
        string version = assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion
            ?? assembly.GetName().Version?.ToString(3) ?? "";
        int plus = version.IndexOf('+');
        return (false, plus < 0 ? version : version[..plus]);
    }
}
