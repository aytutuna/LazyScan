using LazyScan.Core;

namespace LazyScan.App;

/// <summary>
/// Import from folder: new images that appear in the chosen folder are imported as pages
/// (<see cref="ImportPhotos"/>) once nothing else is running. The folder and the switch are app
/// preferences, kept between runs; files that arrived while the app was closed are not imported.
/// </summary>
public sealed partial class AppViewModel
{
    private FolderImportWatcher? _folderWatcher;
    private int _folderImporting;

    public string? ImportFolder { get; private set; }

    public bool ImportFolderOn { get; private set; }

    /// <summary>Why the switch is off for the task in use (it saves its scans on its own); null when it can be used.</summary>
    public string? ImportFolderReason => PhotoImport.OwnSaveTaskReason(Settings);

    /// <summary>Whether the folder is the save folder, holds it or lies inside it: what is saved would be imported again.</summary>
    private bool ImportFolderOverlapsSaveFolder => ImportFolder is { } folder && FolderImportWatcher.Overlaps(folder, DestinationFolder);

    /// <summary>Why <paramref name="folder"/> cannot be the import folder now; null when it can.</summary>
    public string? ImportFolderRefusal(string folder) =>
        FolderImportWatcher.Overlaps(folder, DestinationFolder) ? OverlapMessage : null;

    private static string OverlapMessage =>
        Loc.T("Saved scans would be imported again, because this folder and the save folder are the same or hold each other. Pick another folder.");

    /// <summary>The line under the folder: what the watch is doing, or what is wrong with the folder. Null when nothing is watched.</summary>
    public string? ImportFolderStatus
    {
        get
        {
            if (!ImportFolderOn || ImportFolder is null || ImportFolderReason is not null) return null;
            if (ImportFolderOverlapsSaveFolder) return OverlapMessage;
            return _folderWatcher?.State switch
            {
                FolderImportState.Missing => Loc.T("The folder is not there. Pick it again or turn this off."),
                FolderImportState.Unreadable => Loc.T("This folder cannot be read. Pick another or turn this off."),
                _ when _folderImporting > 0 => Loc.Plural(_folderImporting, "Importing {0} new image…", "Importing {0} new images…"),
                _ => Loc.T("Watching. New images become pages."),
            };
        }
    }

    public bool ImportFolderHasProblem => ImportFolderStatus is not null
        && (ImportFolderOverlapsSaveFolder || _folderWatcher is { State: not FolderImportState.Watching });

    /// <summary>Reads the saved folder and starts watching it. Not called for a command-line scan, which shows no window.</summary>
    public void StartFolderImport()
    {
        var preferences = AppPreferencesStore.Load();
        ImportFolder = string.IsNullOrEmpty(preferences.ImportFolder) ? null : preferences.ImportFolder;
        ImportFolderOn = preferences.ImportFolderOn && ImportFolder is not null;
        NotifyAll();
    }

    public void SetImportFolder(string folder)
    {
        ImportFolder = folder;
        ImportFolderOn = true;
        SaveImportFolder();
        NotifyAll();
    }

    public void SetImportFolderOn(bool on)
    {
        ImportFolderOn = on && ImportFolder is not null;
        SaveImportFolder();
        NotifyAll();
    }

    private void SaveImportFolder()
    {
        string? folder = ImportFolder;
        bool on = ImportFolderOn;
        AppPreferencesStore.Update(preferences =>
        {
            preferences.ImportFolder = folder;
            preferences.ImportFolderOn = on;
        });
    }

    /// <summary>Watching follows the switch, the folder and the task: it stops for a task that saves on its own and starts again with the next one.</summary>
    private void SyncFolderWatch()
    {
        string? folder = ImportFolderOn && ImportFolderReason is null && !ImportFolderOverlapsSaveFolder ? ImportFolder : null;
        if (_folderWatcher is { } current && current.Folder == folder) return;
        _folderWatcher?.Dispose();
        _folderWatcher = null;
        if (folder is null) return;
        var watcher = new FolderImportWatcher(folder);
        watcher.Changed += (_, _) => _dispatcher.BeginInvoke(NotifyAll);
        watcher.Start();
        _folderWatcher = watcher;
    }

    /// <summary>Imports what the folder has collected, once the import can run; files that came meanwhile wait in the watcher.</summary>
    private void TakeFolderFiles()
    {
        if (_folderWatcher is not { Pending: > 0 } watcher || !CanImportPhotos) return;
        var files = watcher.TakeReady();
        if (files.Count > 0) _ = ImportFolderFiles(files);
    }

    private async Task ImportFolderFiles(IReadOnlyList<string> files)
    {
        _folderImporting = files.Count;
        try
        {
            await ImportPhotos(files);
        }
        finally
        {
            _folderImporting = 0;
            NotifyAll();
        }
    }
}
