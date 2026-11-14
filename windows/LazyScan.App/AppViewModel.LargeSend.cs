using System.IO;
using LazyScan.App.Services;
using LazyScan.Core;

namespace LazyScan.App;

/// <summary>What the user chose for files too big for most mail services.</summary>
public enum LargeSendChoice
{
    SaveSmaller,
    SendAnyway,
    Cancel,
}

/// <summary>
/// Share and email of files over <see cref="SaveActions.LargeAttachmentBytes"/> (RunFileAction): the user sees the size
/// first, and can save the held pages again at the Smallest PDF size. The Mac and the iPhone do the same
/// (Sources/LazyScanKit/App/AppState+LargeSend.swift).
/// </summary>
public sealed partial class AppViewModel
{
    private bool _savingSmaller;

    /// <summary>Whole megabytes, rounded up, from 10 MB up, else as <see cref="SavedFiles.SizeText"/> ("6.4 MB").</summary>
    internal static string AttachmentSizeText(long bytes) =>
        bytes >= 10_000_000 && bytes < 1_000_000_000 ? Loc.T("{0} MB", Math.Ceiling(bytes / 1_000_000.0)) : SavedFiles.SizeText(bytes);

    /// <summary>
    /// The pages of the save that wrote <paramref name="paths"/> are still held, and saving them again at the Smallest
    /// size changes something: a PDF not saved at that size already, and not added to another PDF.
    /// </summary>
    private bool CanSaveSmaller(IReadOnlyList<string> paths) =>
        _saved is { Smaller: false, Appended: null } held
        && held.Files.ToHashSet(StringComparer.OrdinalIgnoreCase).IsSupersetOf(paths)
        && OutputFormats.QueueFormat(Settings.Format) == OutputFormat.Pdf
        && Settings.Output.PdfSize != PdfSizePreset.Smallest;

    /// <summary>
    /// Takes the held save back, saves its pages again at the Smallest size, replacing the files, and runs
    /// <paramref name="action"/> on the new ones (asked about again if they are still too big). It waits for the save
    /// in progress when the question came from the end of one.
    /// </summary>
    private async Task SaveSmaller(FileAction action)
    {
        while (IsBusy) await Task.Delay(50);
        string? name = _saved is { Files: [var first, ..] } && Path.GetExtension(first).Equals(".pdf", StringComparison.OrdinalIgnoreCase)
            ? Path.GetFileNameWithoutExtension(first)
            : null;
        if (await UndoSave() is null) return;
        SaveName = name ?? "";
        _savingSmaller = true;
        try { await SavePdf(); }
        finally { _savingSmaller = false; }
        if (_saved is not { Smaller: true } || LastSavedPaths.Count == 0) return;
        var saved = LastSavedPaths;
        StatusMessage = Loc.T("Saved smaller: {0}.", AttachmentSizeText(saved.Sum(path => new FileInfo(path).Length)));
        NotifyAll();
        RunFileAction(action, saved);
    }
}
