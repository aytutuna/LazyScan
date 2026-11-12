namespace LazyScan.Core;

// Twin of Sources/LazyScanKit/Output/SaveFailure.swift.

/// <summary>
/// Plain sentences for a file that could not be written: they name the folder it was going to,
/// never the hidden temp file, and say the pages are kept.
/// </summary>
public static class SaveErrors
{
    public static string PagesKept => Loc.T("The pages are still in the queue.");

    /// <summary>The sentence for a write that failed with <paramref name="e"/> in <paramref name="folder"/>.</summary>
    public static string Describe(Exception e, string folder) => $"{Reason(Cause(e, folder), folder)} {PagesKept}";

    private enum Reasons { DiskFull, NotAllowed, Missing }

    private static string Reason(Reasons? cause, string folder)
    {
        string name = Path.GetFileName(folder.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
        if (name.Length == 0) name = folder;
        return cause switch
        {
            Reasons.DiskFull => Loc.T("There is not enough space to save in “{0}”.", name),
            Reasons.NotAllowed => Loc.T("Files cannot be saved in “{0}”. It may be read-only. Choose another folder.", name),
            Reasons.Missing => Loc.T("The folder “{0}” was not found. Choose another folder.", name),
            _ => Loc.T("Could not save in “{0}”.", name),
        };
    }

    private static Reasons? Cause(Exception e, string folder)
    {
        // ERROR_HANDLE_DISK_FULL and ERROR_DISK_FULL.
        if (e is IOException { HResult: var hr } && ((hr & 0xFFFF) is 0x27 or 0x70)) return Reasons.DiskFull;
        // ERROR_WRITE_PROTECT: a locked SD card or USB stick.
        if (e is UnauthorizedAccessException || e is IOException { HResult: var wp } && (wp & 0xFFFF) == 0x13) return Reasons.NotAllowed;
        if (e is DirectoryNotFoundException || !Directory.Exists(folder)) return Reasons.Missing;
        return null;
    }
}
