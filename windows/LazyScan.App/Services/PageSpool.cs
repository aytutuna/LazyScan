using System.IO;
using LazyScan.Core;

namespace LazyScan.App.Services;

/// <summary>
/// The folder this process spills queued document pages to, so a long high-dpi batch
/// doesn't hold gigabytes of pixels in memory.
///
/// Every running instance gets its own subfolder of
/// %LOCALAPPDATA%\Lazy Scan\pages and holds a ".lock" file in it open, unshared, for its whole
/// lifetime, and records its queue beside the pages (<see cref="QueueRecord"/>). A normal exit deletes the
/// folder. On startup the folders of instances that are gone (their lock is no longer
/// held, because the process exited or crashed) are deleted; the folder of an instance
/// that is still running can't be, because its lock file can't be deleted. A folder with a
/// queue record is left alone, as the pages in it are the user's.
/// </summary>
public sealed class PageSpool : IDisposable
{
    public static readonly string DefaultRoot = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Lazy Scan", "pages");

    private const string LockFileName = ".lock";
    /// <summary>A folder without a lock file may belong to an instance that is just starting up.</summary>
    private static readonly TimeSpan UnlockedGracePeriod = TimeSpan.FromMinutes(1);

    private FileStream? _lock;

    /// <summary>This process's spool folder.</summary>
    public string Directory { get; }

    public PageSpool(string? root = null)
    {
        if (root == null)
        {
            root = DefaultRoot;
            SweepAbandoned(Path.Combine(Path.GetTempPath(), "LazyScan-pages"));
        }
        SweepAbandoned(root);
        Directory = Path.Combine(root, Guid.NewGuid().ToString("N"));
        System.IO.Directory.CreateDirectory(Directory);
        try
        {
            _lock = new FileStream(Path.Combine(Directory, LockFileName), FileMode.CreateNew,
                                   FileAccess.ReadWrite, FileShare.None, 1, FileOptions.DeleteOnClose);
        }
        catch
        {
            // Without the lock another instance may sweep this folder; saving a spooled
            // page then fails. Not a reason to refuse to start.
        }
    }

    /// <summary>Delete what earlier (or crashed) instances left behind; never throws.</summary>
    internal static void SweepAbandoned(string root)
    {
        if (!System.IO.Directory.Exists(root)) return;
        try
        {
            // Loose files directly in the root come from builds that used one shared folder.
            foreach (string file in System.IO.Directory.EnumerateFiles(root))
            {
                try { File.Delete(file); } catch { /* best effort */ }
            }
            foreach (string folder in System.IO.Directory.EnumerateDirectories(root))
            {
                try
                {
                    if (File.Exists(Path.Combine(folder, QueueRecord.FileName))) continue;
                    string lockPath = Path.Combine(folder, LockFileName);
                    if (File.Exists(lockPath))
                    {
                        // Fails with a sharing violation while the owning process is alive.
                        File.Delete(lockPath);
                    }
                    else if (System.IO.Directory.GetCreationTimeUtc(folder) > DateTime.UtcNow - UnlockedGracePeriod)
                    {
                        continue;
                    }
                    System.IO.Directory.Delete(folder, recursive: true);
                }
                catch
                {
                    // In use by a running instance (or not deletable): leave it.
                }
            }
        }
        catch
        {
            // Unreadable root: nothing to sweep.
        }
    }

    /// <summary>Release the lock and delete this process's spool folder (on a normal exit).</summary>
    public void Dispose()
    {
        _lock?.Dispose();
        _lock = null;
        try { System.IO.Directory.Delete(Directory, recursive: true); } catch { /* best effort */ }
    }
}
