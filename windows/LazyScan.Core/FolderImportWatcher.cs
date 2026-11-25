namespace LazyScan.Core;

public enum FolderImportState
{
    Watching,
    /// <summary>The folder is not there (deleted, a drive or share that is gone).</summary>
    Missing,
    /// <summary>The folder is there but cannot be listed.</summary>
    Unreadable,
}

/// <summary>
/// Watches a folder for images and PDFs that appear or change in it (a scanner's scan-to-folder, an SD
/// card copied over) and hands them out to be imported as pages. Files already there when watching
/// starts are left alone, and a file is offered once its size and date have been steady for
/// <see cref="SettleTime"/>, as the cloud folder watcher (<see cref="SyncFolderWatcher"/>) waits. A
/// file is handed out once per run for each size and date it has, oldest first; the folder is not
/// searched below its top level and its files are never touched. Only names are held, so files that
/// wait for the app to be free cost nothing.
/// </summary>
public sealed class FolderImportWatcher : IDisposable
{
    public static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(5);
    public static readonly TimeSpan SettleTime = TimeSpan.FromSeconds(2);

    private readonly Func<DateTimeOffset> _clock;
    private readonly object _gate = new();
    private readonly Dictionary<string, (long Size, DateTime Modified, DateTimeOffset Since)> _seen = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<(string Path, long Size, DateTime Modified)> _taken = [];
    private readonly HashSet<string> _skipped = new(StringComparer.OrdinalIgnoreCase);
    private List<string> _ready = [];
    private bool _baselined;
    private FileSystemWatcher? _watcher;
    private Timer? _timer;

    public FolderImportWatcher(string folder, Func<DateTimeOffset>? clock = null)
    {
        Folder = folder;
        _clock = clock ?? (() => DateTimeOffset.UtcNow);
    }

    public string Folder { get; }

    /// <summary>
    /// Whether two folders are the same or one holds the other. A scan saved into the watched folder, or into one
    /// inside it, would be imported again as a new page; so would one saved around it, whichever way the folders are
    /// written (case, trailing slash, "..").
    /// </summary>
    public static bool Overlaps(string folder, string other)
    {
        try
        {
            string a = Normalized(folder), b = Normalized(other);
            return a.StartsWith(b, StringComparison.OrdinalIgnoreCase) || b.StartsWith(a, StringComparison.OrdinalIgnoreCase);
        }
        catch (Exception e) when (e is ArgumentException or NotSupportedException or PathTooLongException)
        {
            return false; // not a path: the watcher reports it as missing
        }
    }

    private static string Normalized(string folder)
    {
        string full = Path.GetFullPath(folder);
        return Path.EndsInDirectorySeparator(full) ? full : full + Path.DirectorySeparatorChar;
    }

    public FolderImportState State { get; private set; } = FolderImportState.Watching;

    /// <summary>How many settled new files wait to be taken.</summary>
    public int Pending
    {
        get
        {
            lock (_gate) return _ready.Count;
        }
    }

    /// <summary>The state changed or new files are ready (on a pool thread).</summary>
    public event EventHandler? Changed;

    public void Start()
    {
        _timer = new Timer(_ => Poll(), null, TimeSpan.Zero, PollInterval);
        try
        {
            _watcher = new FileSystemWatcher(Folder)
            {
                NotifyFilter = NotifyFilters.FileName | NotifyFilters.Size | NotifyFilters.LastWrite,
            };
            _watcher.Created += (_, _) => Poll();
            _watcher.Changed += (_, _) => Poll();
            _watcher.Renamed += (_, _) => Poll();
            _watcher.EnableRaisingEvents = true;
        }
        catch (Exception e) when (e is ArgumentException or IOException or PlatformNotSupportedException)
        {
            // A folder that is not there now is found by the poll, which also notices when it comes back.
            _watcher?.Dispose();
            _watcher = null;
        }
    }

    /// <summary>The ready files, oldest first; each is handed out once for its size and date.</summary>
    public IReadOnlyList<string> TakeReady()
    {
        lock (_gate)
        {
            var files = new List<string>();
            foreach (string path in _ready)
            {
                if (!_seen.TryGetValue(path, out var seen)) continue;
                _taken.Add((path, seen.Size, seen.Modified));
                files.Add(path);
            }
            _ready = [];
            return files;
        }
    }

    /// <summary>Never offers these paths: files the app wrote itself, which must not come back in as pages.</summary>
    public void Skip(IEnumerable<string> paths)
    {
        lock (_gate)
        {
            foreach (string path in paths) _skipped.Add(path);
            _ready = _ready.Where(p => !_skipped.Contains(p)).ToList();
        }
    }

    /// <summary>Looks at the folder once.</summary>
    public void Poll()
    {
        bool changed;
        lock (_gate)
        {
            var before = (State, Ready: _ready.Count);
            Look();
            changed = before != (State, _ready.Count);
        }
        if (changed) Changed?.Invoke(this, EventArgs.Empty);
    }

    public void Dispose()
    {
        _watcher?.Dispose();
        _watcher = null;
        _timer?.Dispose();
        _timer = null;
    }

    private void Look()
    {
        string[] files;
        try
        {
            files = PhotoImport.PhotoFiles(Directory.GetFiles(Folder)).Where(f => !_skipped.Contains(f)).ToArray();
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            State = e is UnauthorizedAccessException ? FolderImportState.Unreadable : FolderImportState.Missing;
            _ready = [];
            return;
        }
        State = FolderImportState.Watching;
        var now = _clock();
        var names = files.ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (string gone in _seen.Keys.Where(n => !names.Contains(n)).ToList()) _seen.Remove(gone);
        bool settling = false;
        var ready = new List<(string Path, DateTime Modified)>();
        foreach (string path in files)
        {
            long size;
            DateTime modified;
            try
            {
                var info = new FileInfo(path);
                size = info.Length;
                modified = info.LastWriteTimeUtc;
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                continue;
            }
            if (!_baselined)
            {
                // What is in the folder when watching starts is not imported.
                _taken.Add((path, size, modified));
                continue;
            }
            if (!_seen.TryGetValue(path, out var seen) || seen.Size != size || seen.Modified != modified)
            {
                _seen[path] = (size, modified, now);
                seen = _seen[path];
            }
            if (_taken.Contains((path, size, modified))) continue;
            if (now - seen.Since < SettleTime) settling = true;
            else ready.Add((path, modified));
        }
        // The first look of a folder that could be read is the baseline.
        _baselined = true;
        _ready = ready.OrderBy(f => f.Modified).ThenBy(f => f.Path, StringComparer.OrdinalIgnoreCase).Select(f => f.Path).ToList();
        if (!settling) return;
        try
        {
            _timer?.Change(SettleTime, PollInterval);
        }
        catch (ObjectDisposedException)
        {
            // Stopped meanwhile.
        }
    }
}
