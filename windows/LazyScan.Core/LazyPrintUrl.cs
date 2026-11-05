namespace LazyScan.Core;

// Twin of Sources/LazyScanKit/Core/LazyPrintUrl.swift: the address that opens Lazy Print with files.

/// <summary>
/// <c>lazyprint:open?file=C%3A%5CScans%5Cscan.pdf</c>: the <c>file</c> parameter repeated for each
/// file, each path percent-encoded whole.
/// </summary>
public static class LazyPrintUrl
{
    public const string Scheme = "lazyprint";

    public static string Build(IEnumerable<string> paths) =>
        Scheme + ":open?" + string.Join("&", paths.Select(path => "file=" + Uri.EscapeDataString(path)));
}
