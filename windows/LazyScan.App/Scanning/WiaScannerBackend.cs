using System.IO;
using System.Runtime.InteropServices;
using LazyScan.App.Scanning.Twain;
using LazyScan.App.Services;
using LazyScan.Core;

namespace LazyScan.App.Scanning;

/// <summary>
/// Real scanner hardware via WIA 2.0 (the WIA Automation layer, wiaaut.dll) — the Windows
/// counterpart of the macOS ICScannerBackend.
///
/// ⚠ EXPERIMENTAL, UNTESTED AGAINST HARDWARE: this was authored without a Windows machine
/// or scanner attached. The WIA property IDs and flow follow the documented WIA Automation
/// model (DeviceManager → DeviceInfos → Connect → Items → Transfer), but expect to iterate
/// against a real device. Known scaffold limitations:
///   - the scanner's own button is heard through WIA device events (see ListenForEvents);
///   - hot-plug is detected from WIA connect and disconnect events, with a poll (the watchdog below) as the fallback;
///   - Transfer() is synchronous with no progress callbacks — progress is coarse;
///   - CancelScan() cannot abort an in-flight WIA transfer: the pass ends, then the scan stops (a feeder after the current sheet).
/// </summary>
public sealed class WiaScannerBackend : IPolledScannerBackend, IScannerBackendDiagnostics, IBackendDiagnostics
{
    // A kill between the transfer and the delete leaves a full-resolution bitmap in %TEMP%.
    static WiaScannerBackend()
    {
        try
        {
            foreach (string file in Directory.EnumerateFiles(Path.GetTempPath(), "LazyScan-*.bmp"))
            {
                try { File.Delete(file); } catch { /* in use or gone: leave it */ }
            }
        }
        catch { /* best effort */ }
    }

    public event Action? DevicesChanged;
    public event Action? EnumerationFinished;

    /// <summary>
    /// Raised on the thread that started browsing for every WIA event the backend is registered for,
    /// with the event id and the device id. The connect and disconnect events also refresh the list;
    /// the button events are for the app (<see cref="IsButtonEvent"/>).
    /// </summary>
    internal event Action<string, string>? DeviceEvent;

    private readonly List<ScannerInfo> _devices = [];
    public IReadOnlyList<ScannerInfo> Devices => _devices;

    // WIA constants.
    private const int ScannerDeviceType = 1;
    internal const string FormatBmp = "{B96B3CAB-0728-11D3-9D7B-0000F81EF32E}";

    // Device-level property IDs (WIA_DPS_*).
    internal const string HorizontalBedSize = "3074";   // thousandths of an inch
    internal const string VerticalBedSize = "3075";
    internal const string HorizontalSheetFeedSize = "3076"; // thousandths of an inch
    internal const string VerticalSheetFeedSize = "3077";
    internal const string DocumentHandlingCapabilities = "3086"; // see WiaDocumentHandling (Core)
    internal const string DocumentHandlingSelect = "3088"; // see WiaDocumentHandling.SelectValues (Core)
    internal const string OpticalXResolution = "3090";
    internal const string TransparencySelect = "3102";  // 2 = LIGHT_SOURCE_POSITIVE: the transparency unit, raw film
    internal const string Pages = "3096";               // 0 = every sheet in the feeder
    internal const string PageSize = "3097";            // see WiaDocumentHandling.PageSize (Core)
    internal const string PageWidth = "3098";           // thousandths of an inch
    internal const string PageHeight = "3099";
    internal const int HandlingFeeder = 1;
    internal const int HandlingFlatbed = 2;

    // Item-level property IDs (WIA_IPS_* / WIA_IPA_*).
    internal const string ItemCategory = "4125";        // a GUID; the film item's is WiaDocumentHandling.FilmCategory
    internal const string FilmScanMode = "3104";        // 0 = color slide: raw film, the app inverts negatives
    internal const string CurrentIntent = "6146";       // 1 color, 2 gray, 4 text
    internal const string HorizontalResolution = "6147";
    internal const string VerticalResolution = "6148";
    internal const string XPos = "6149";
    internal const string YPos = "6150";
    internal const string XExtent = "6151";
    internal const string YExtent = "6152";

    /// <summary>First delay of the hot-plug watchdog; doubled after each fruitless poll.</summary>
    internal static readonly TimeSpan InitialRebrowseDelay = TimeSpan.FromSeconds(10);
    /// <summary>Upper bound of the watchdog backoff.</summary>
    internal static readonly TimeSpan MaxRebrowseDelay = TimeSpan.FromSeconds(60);

    internal const string DeviceManagerProgId = "WIA.DeviceManager";
    internal const string CommonDialogProgId = "WIA.CommonDialog";

    // WIA event ids (wiaEventDeviceConnected, wiaEventDeviceDisconnected) and the "every device" id.
    internal const string DeviceConnected = "{A28BBADE-64B6-11D2-A231-00C04FA31809}";
    internal const string DeviceDisconnected = "{143E4E83-6497-11D2-A231-00C04FA31809}";
    private const string AnyDevice = "*";
    // The events a press on the scanner's own button raises (wiaEventScanImage, ScanPrintImage, ScanFaxImage, ScanEmailImage, ScanImage2, ScanImage3, ScanImage4, ScanOCRImage, ScanFilmImage).
    private static readonly string[] ButtonEvents =
    [
        "{A6C5A715-8C6E-11D2-977A-0000F87A926F}",
        "{B441F425-8C6E-11D2-977A-0000F87A926F}",
        "{C00EB793-8C6E-11D2-977A-0000F87A926F}",
        "{C686DCEE-54F2-419E-9A27-2FC7F2E98F9E}",
        "{FC4767C1-C8B3-48A2-9CFA-2E90CB3D3590}",
        "{154E27BE-B617-4653-ACC5-0FD7BD4C42CE}",
        "{A65B704A-7F3C-4447-A75D-8A26DFCA1FDF}",
        "{9D095B89-37D6-4877-AFED-62A297DC6DBE}",
        "{9B2B662C-6185-438C-B68B-E39EE25E71CB}",
    ];
    // _IDeviceManagerEvents, whose OnEvent (dispatch id 1) reports the events registered with RegisterEvent.
    private static readonly Guid DeviceManagerEvents = new("2E9A5206-2360-49DF-9D9B-1762B4BEAE77");

    /// <summary>Reads the WIA service (stisvc); any thread, never throws.</summary>
    private readonly Func<ServiceStatus> _serviceStatus;
    /// <summary>Whether WIA Automation (wiaaut.dll) is registered; any thread, never throws.</summary>
    private readonly Func<bool> _automationRegistered;
    private readonly Func<List<ScannerInfo>> _enumerateScanners;
    /// <summary>Starts WIA event delivery on the WIA thread and returns what stops it; null when there is no WIA to listen to. Null itself: no events (harnesses).</summary>
    private readonly Func<Action<string, string>, Action?>? _listen;
    private Task<Action?>? _listener;
    private SynchronizationContext? _context;
    private CancellationTokenSource? _watchdog;
    /// <summary>Bumped by every Start/StopBrowsing; enumeration results from an older generation are dropped.</summary>
    private int _browseGeneration;
    /// <summary>The number of the enumeration running now; 0 when none is.</summary>
    private long _running;
    /// <summary>A refresh was asked for while one ran: another starts when it ends.</summary>
    private bool _refreshAgain;
    private long _enumerationsStarted;
    private long _enumerationsFinished;
    /// <summary>Why the last enumeration could not ask WIA (see <see cref="WiaAvailability"/>); null when it could.</summary>
    private string? _unavailable;
    /// <summary>The WIA service as the last enumeration read it.</summary>
    private ServiceStatus _service;
    /// <summary>Why the last enumeration failed while WIA could be asked; null when it did not. The list stays as it was.</summary>
    private string? _failure;

    public long EnumerationsStarted => Interlocked.Read(ref _enumerationsStarted);
    public long EnumerationsFinished => Interlocked.Read(ref _enumerationsFinished);

    public WiaScannerBackend() : this(new WindowsSystemDiagnostics().WiaService, AutomationRegistered, null, ListenForEvents)
    {
    }

    /// <param name="serviceStatus">Reads the WIA service; asked on the WIA thread before each enumeration.</param>
    /// <param name="automationRegistered">Whether WIA Automation is registered; asked likewise.</param>
    /// <param name="enumerateScanners">Lists the scanners on the WIA thread; WIA itself when null.</param>
    /// <param name="listen">Registers for WIA events on the WIA thread, given the handler of an event (its id and device id); no events when null.</param>
    internal WiaScannerBackend(Func<ServiceStatus> serviceStatus, Func<bool> automationRegistered,
                               Func<List<ScannerInfo>>? enumerateScanners = null,
                               Func<Action<string, string>, Action?>? listen = null)
    {
        _listen = listen;
        _serviceStatus = serviceStatus;
        _automationRegistered = automationRegistered;
        _enumerateScanners = enumerateScanners ?? EnumerateScanners;
    }

    /// <summary>Why WIA is not asked for scanners now; null when it is (or before the first enumeration).</summary>
    public string? Unavailable => _unavailable;

    public string? DiagnosticsReport => WiaAvailability.Report(_watchdog is not null, _unavailable, _devices.Count, _failure);

    /// <summary>
    /// Enumerate once now, then keep re-enumerating so the list follows the hardware without
    /// a restart: a scanner plugged in later appears, and an unplugged one disappears (the
    /// macOS backend gets both from ICDeviceBrowser add/remove callbacks; here WIA's connect and
    /// disconnect events refresh the list, and a poll covers a missed event or WIA not running
    /// yet). While no scanner is listed the poll starts at
    /// 10 s and doubles up to 60 s; while one is listed it runs every 60 s. A session that
    /// finds its device gone also triggers an immediate re-enumeration. Enumeration runs on
    /// the WIA thread (<see cref="WiaApartment"/>), so the UI thread never blocks on WIA.
    /// </summary>
    public void StartBrowsing()
    {
        if (_watchdog is not null) return;
        _context = SynchronizationContext.Current;
        Interlocked.Increment(ref _browseGeneration);
        // An enumeration still queued from before a Stop is stale; don't let it block this one.
        _running = 0;
        _refreshAgain = false;
        _watchdog = new CancellationTokenSource();
        RefreshDevices();
        _ = RunWatchdog(_watchdog.Token);
    }

    public void StopBrowsing()
    {
        _watchdog?.Cancel();
        _watchdog?.Dispose();
        _watchdog = null;
        StopListening();
        Interlocked.Increment(ref _browseGeneration);
        _unavailable = null;
        _failure = null;
        if (_devices.Count == 0) return;
        _devices.Clear();
        DevicesChanged?.Invoke();
    }

    /// <summary>Whether a WIA event is a press on the scanner's own button.</summary>
    internal static bool IsButtonEvent(string eventId) => ButtonEvents.Contains(eventId, StringComparer.OrdinalIgnoreCase);

    /// <summary>The app's id for the WIA device id an event carries.</summary>
    internal static string ScannerIdOf(string deviceId) => $"wia:{deviceId}";

    /// <summary>Starts WIA event delivery unless it runs or WIA has nothing to listen to; a failed start is tried again.</summary>
    private void EnsureListening()
    {
        if (_listen is not { } listen || _listener is { IsFaulted: false }) return;
        _listener = WiaApartment.Run(() => listen(HandleEvent));
        _ = _listener.ContinueWith(t => System.Diagnostics.Trace.TraceWarning($"Could not listen for WIA events: {t.Exception?.GetBaseException().Message}"),
                                   CancellationToken.None, TaskContinuationOptions.OnlyOnFaulted, TaskScheduler.Default);
    }

    private void StopListening()
    {
        var listener = _listener;
        _listener = null;
        _ = listener?.ContinueWith(t =>
        {
            if (t.IsCompletedSuccessfully && t.Result is { } stop) _ = WiaApartment.Run(() => { stop(); return 0; });
        }, TaskScheduler.Default);
    }

    /// <summary>Called on the WIA thread for each event; the work goes to the thread that started browsing.</summary>
    private void HandleEvent(string eventId, string deviceId) => Post(() =>
    {
        if (_watchdog is null) return;
        DeviceEvent?.Invoke(eventId, deviceId);
        if (eventId.Equals(DeviceConnected, StringComparison.OrdinalIgnoreCase)
            || eventId.Equals(DeviceDisconnected, StringComparison.OrdinalIgnoreCase))
        {
            RefreshDevices();
        }
    });

    /// <summary>
    /// Registers a WIA device manager for the connect, disconnect and scanner button events of every device and
    /// passes each event to <paramref name="onEvent"/> (event id, device id), on the WIA thread, so
    /// it must be quick. The manager stays alive until the returned action runs, on the WIA thread;
    /// null when WIA Automation cannot create one.
    /// </summary>
    internal static Action? ListenForEvents(Action<string, string> onEvent)
    {
        object? manager;
        using (WiaApartment.Use())
        {
            manager = Type.GetTypeFromProgID(DeviceManagerProgId) is { } type ? Activator.CreateInstance(type) : null;
        }
        if (manager is null) return null;
        Action<string, string, string> sink = (eventId, deviceId, _) => onEvent(eventId, deviceId);
        try
        {
            ComEventsHelper.Combine(manager, DeviceManagerEvents, 1, sink);
            dynamic wia = manager;
            wia.RegisterEvent(DeviceConnected, AnyDevice);
            wia.RegisterEvent(DeviceDisconnected, AnyDevice);
            foreach (string buttonEvent in ButtonEvents)
            {
                // A driver may refuse some of them; connect and disconnect stay registered.
                try { wia.RegisterEvent(buttonEvent, AnyDevice); }
                catch { }
            }
        }
        catch
        {
            Release(manager, sink);
            throw;
        }
        return () => Release(manager, sink);
    }

    private static void Release(object manager, Action<string, string, string> sink)
    {
        try
        {
            ComEventsHelper.Remove(manager, DeviceManagerEvents, 1, sink);
        }
        catch
        {
            // best effort
        }
        try
        {
            if (Marshal.IsComObject(manager)) Marshal.FinalReleaseComObject(manager);
        }
        catch
        {
            // best effort
        }
    }

    private async Task RunWatchdog(CancellationToken token)
    {
        var delay = InitialRebrowseDelay;
        while (!token.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(delay, token).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                return;
            }
            Post(() =>
            {
                if (token.IsCancellationRequested) return;
                RefreshDevices();
            });
            // Read the count without marshaling: a stale value only shifts the next delay.
            delay = NextRebrowseDelay(delay, devicesListed: _devices.Count > 0);
        }
    }

    /// <summary>
    /// The watchdog's next poll interval: backing off (doubling up to the ceiling) while no
    /// scanner is listed, and the ceiling while one is — slow enough to stay cheap, fast
    /// enough that an unplugged scanner leaves the list.
    /// </summary>
    internal static TimeSpan NextRebrowseDelay(TimeSpan current, bool devicesListed) =>
        devicesListed
            ? MaxRebrowseDelay
            : TimeSpan.FromTicks(Math.Min(current.Ticks * 2, MaxRebrowseDelay.Ticks));

    /// <summary>
    /// The WIA service's state as the last enumeration read it, for a snapshot where the app has
    /// not read it itself (it does, in Services/SystemDiagnostics.cs); WIA adds nothing else.
    /// </summary>
    public DiscoverySnapshot AddStatus(DiscoverySnapshot snapshot) =>
        snapshot.WiaService == ServiceStatus.Unknown && _service != ServiceStatus.Unknown
            ? snapshot with { WiaService = _service }
            : snapshot;

    /// <summary>The troubleshooter's Refresh: list the WIA scanners again now, while browsing.</summary>
    public void Rescan()
    {
        if (_watchdog is not null) RefreshDevices();
    }

    /// <summary>A session found its device missing: re-enumerate now (callable from any thread).</summary>
    internal void DeviceLost() => Post(() =>
    {
        if (_watchdog is not null) RefreshDevices();
    });

    /// <summary>
    /// Re-enumerate WIA scanners in the background (call again to pick up newly plugged
    /// devices). A call while one runs does not start a second at once: one more starts when the
    /// running one ends, so the result of an enumeration begun after the call always arrives
    /// (the app waits for that before it uses Windows Scan for a scanner WIA does not list yet).
    /// </summary>
    public void RefreshDevices()
    {
        // Without a context to post to, results are applied on a pool thread under this lock (see
        // Post); it is re-entered when a result starts the enumeration asked for meanwhile.
        lock (_devices) StartEnumeration();
    }

    private void StartEnumeration()
    {
        if (_running != 0)
        {
            _refreshAgain = true;
            return;
        }
        _refreshAgain = false;
        int generation = Volatile.Read(ref _browseGeneration);
        long number = Interlocked.Increment(ref _enumerationsStarted);
        _running = number;
        WiaApartment.Run(() => Enumerate(generation)).ContinueWith(task =>
        {
            var result = task.IsCompletedSuccessfully ? task.Result : null;
            string? failure = task.Exception?.GetBaseException().Message;
            Post(() =>
            {
                if (_running == number) _running = 0;
                // A Stop/Start since this enumeration began makes its result stale.
                if (generation != _browseGeneration) return;
                if (number > Interlocked.Read(ref _enumerationsFinished)) Interlocked.Exchange(ref _enumerationsFinished, number);
                // A failed enumeration says nothing about the scanners: the list stays as it was.
                if (result is null)
                {
                    // The listing only ran because WIA was available, so an earlier reason is stale.
                    bool failureChanged = failure != _failure || (failure is not null && _unavailable is not null);
                    if (failure is not null) _unavailable = null;
                    _failure = failure;
                    if (failureChanged) DevicesChanged?.Invoke();
                    EnumerationFinished?.Invoke();
                    if (_refreshAgain && _running == 0) RefreshDevices();
                    return;
                }
                _service = result.Service;
                if (result.Unavailable is null) EnsureListening();
                bool noteChanged = result.Unavailable != _unavailable || _failure is not null;
                _unavailable = result.Unavailable;
                _failure = null;
                // A new reason (or none) is a change too: devices.txt is written again with it.
                if (!ReplaceDevices(result.Found) && noteChanged) DevicesChanged?.Invoke();
                EnumerationFinished?.Invoke();
                if (_refreshAgain && _running == 0) RefreshDevices();
            });
        }, TaskScheduler.Default);
    }

    private sealed record EnumerationResult(List<ScannerInfo> Found, string? Unavailable, ServiceStatus Service);

    /// <summary>
    /// One enumeration, on the WIA thread: nothing when browsing stopped while it waited there, and
    /// no WIA object at all when the service cannot start or WIA Automation is missing
    /// (<see cref="WiaAvailability"/>). A stopped service is started by asking WIA, so it is read
    /// again afterwards: the troubleshooter gets the state the enumeration left it in.
    /// </summary>
    private EnumerationResult Enumerate(int generation)
    {
        if (generation != Volatile.Read(ref _browseGeneration)) return new([], null, ServiceStatus.Unknown);
        ServiceStatus service = _serviceStatus();
        string? unavailable = WiaAvailability.Unavailable(service, _automationRegistered());
        if (unavailable is not null) return new([], unavailable, service);
        var found = _enumerateScanners();
        if (service is ServiceStatus.Stopped or ServiceStatus.Stopping or ServiceStatus.Paused) service = _serviceStatus();
        return new(found, null, service);
    }

    /// <summary>Run on the thread that started browsing (the UI thread in the app); without one, under the lock.</summary>
    private void Post(Action action)
    {
        if (_context is { } context) context.Post(_ => action(), null);
        else lock (_devices) action();
    }

    /// <summary>
    /// WIA Automation's DeviceManager is registered and its DLL is on disk. Checked before the
    /// first WIA object is created, so a PC without WIA lists nothing instead of failing in COM.
    /// </summary>
    internal static bool AutomationRegistered()
    {
        try
        {
            if (Type.GetTypeFromProgID(DeviceManagerProgId, throwOnError: false) is not { } type) return false;
            using var server = Microsoft.Win32.Registry.ClassesRoot.OpenSubKey($@"CLSID\{{{type.GUID}}}\InprocServer32");
            if (server?.GetValue(null) is not string path || path.Trim('"').Length == 0) return false;
            path = Environment.ExpandEnvironmentVariables(path.Trim('"'));
            // A bare file name is looked up on the search path, as COM does.
            return !Path.IsPathRooted(path) || File.Exists(path);
        }
        catch (Exception e)
        {
            System.Diagnostics.Trace.TraceWarning($"Could not read the WIA Automation registration: {e.Message}");
            return false;
        }
    }

    /// <summary>The scanners WIA lists now; throws when WIA fails. WIA thread only.</summary>
    internal static List<ScannerInfo> EnumerateScanners() => EnumerateScanners(() =>
        Type.GetTypeFromProgID(DeviceManagerProgId) is { } type ? Activator.CreateInstance(type) : null);

    /// <summary>A scanner whose entry cannot be read is skipped; the others are still listed.</summary>
    internal static List<ScannerInfo> EnumerateScanners(Func<object?> createManager)
    {
        var found = new List<ScannerInfo>();
        // The watchdog may enumerate for hours: release every COM object deterministically
        // rather than leaving them to the finalizer of a thread that has already exited.
        var comObjects = new List<object>();
        using var use = WiaApartment.Use();
        try
        {
            if (createManager() is not { } created) return found;
            dynamic manager = created;
            comObjects.Add(created);
            dynamic infos = manager.DeviceInfos;
            comObjects.Add(infos);
            int count = infos.Count;
            for (int i = 1; i <= count; i++) // WIA collections are 1-based
            {
                try
                {
                    dynamic info = infos[i];
                    comObjects.Add(info);
                    if ((int)info.Type != ScannerDeviceType) continue;
                    string id = (string)info.DeviceID;
                    string name = TryGetProperty(info.Properties, "Name") as string ?? Loc.T("Scanner");
                    found.Add(new ScannerInfo($"wia:{id}", name, "WIA", Backend: "wia",
                                              Model: ModelOf(TryGetProperty(info.Properties, "Manufacturer") as string,
                                                             TryGetProperty(info.Properties, "Description") as string),
                                              HardwareId: DeviceMerge.PnpInstanceId(TryGetProperty(info.Properties, "PnP ID String") as string)));
                }
                catch (Exception e)
                {
                    System.Diagnostics.Trace.TraceWarning($"Skipped WIA device {i}: {e.Message}");
                }
            }
        }
        finally
        {
            for (int i = comObjects.Count - 1; i >= 0; i--)
            {
                try
                {
                    if (Marshal.IsComObject(comObjects[i])) Marshal.FinalReleaseComObject(comObjects[i]);
                }
                catch
                {
                    // best effort
                }
            }
        }
        return found;
    }

    /// <summary>
    /// "Manufacturer Description" from the device's WIA properties, for matching it with the
    /// same scanner on other connections (DeviceMerge drops a repeated manufacturer); null
    /// when the driver reports neither.
    /// </summary>
    internal static string? ModelOf(string? manufacturer, string? description)
    {
        string model = $"{manufacturer?.Trim()} {description?.Trim()}".Trim();
        return model.Length > 0 ? model : null;
    }

    /// <summary>Lists <paramref name="found"/>; true (and DevicesChanged raised) when the list changed.</summary>
    private bool ReplaceDevices(List<ScannerInfo> found)
    {
        if (_devices.SequenceEqual(found)) return false;
        _devices.Clear();
        _devices.AddRange(found);
        DevicesChanged?.Invoke();
        return true;
    }

    public Task<IScannerSession> OpenSessionAsync(string deviceId)
    {
        var info = _devices.FirstOrDefault(d => d.Id == deviceId)
            ?? throw ScanException.DeviceUnavailable(() => Loc.T("The selected scanner is not connected."));
        string wiaId = deviceId["wia:".Length..];
        return Task.FromResult<IScannerSession>(new WiaScannerSession(info, wiaId, DeviceLost));
    }

    internal static object? TryGetProperty(dynamic properties, string idOrName)
    {
        try
        {
            return properties[idOrName].Value;
        }
        catch
        {
            return null;
        }
    }

    internal static bool TrySetProperty(dynamic properties, string id, object value)
    {
        try
        {
            properties[id].Value = value;
            return true;
        }
        catch
        {
            return false;
        }
    }
}

/// <param name="deviceLost">Called (on the WIA thread) when the device is no longer connected.</param>
internal sealed class WiaScannerSession(ScannerInfo info, string wiaDeviceId, Action deviceLost)
    : IScannerSession, IDriverWindowOption, IDriverWindowControl
{
    public ScannerInfo Info { get; } = info;
    public Action<ScanProgress>? ProgressHandler { get; set; }

    /// <summary>Written on the WIA thread before the scan task completes, read after it.</summary>
    private volatile ScanStop? _lastScanStop;
    public ScanStop? LastScanStop => _lastScanStop;

    /// <summary>Written on the WIA thread before the scan task completes, read after it (null, false, true).</summary>
    private volatile int _lastScanDuplex = -1;
    public bool? LastScanDuplex => _lastScanDuplex < 0 ? null : _lastScanDuplex == 1;

    private volatile bool _cancelRequested;
    private volatile bool _waitingForDriverWindow;
    private volatile int _dialogThread;
    public bool WaitingForDriverWindow => _waitingForDriverWindow;
    public bool DriverWindowOptional => true;
    public bool UseDriverWindow { get; set; }

    public void ShowDriverWindow()
    {
        if (_waitingForDriverWindow) DriverWindows.RaiseThread(_dialogThread);
    }

    /// <summary>A scan was asked for and has not finished, from the call until the WIA thread is done with it.</summary>
    private volatile bool _scanning;
    private SizeD _bedInches = new(8.5, 11.7);
    /// <summary>The feeder's largest sheet, when the device reports it.</summary>
    private SizeD? _feederInches;
    /// <summary>The sources the device reported (null until the capabilities are read).</summary>
    private List<ScanSource>? _sources;
    /// <summary>The feeder scans both sides, as the device reported (null until the capabilities are read).</summary>
    private bool? _supportsDuplex;
    /// <summary>The source selected by the last <see cref="PrepareItemCore"/> scans both sides (WIA thread only).</summary>
    private bool _preparedTwoSided;
    private int _preparedDpi;

    public Task<ScannerCapabilities> GetCapabilitiesAsync() => WiaApartment.Run(() =>
    {
        var caps = new ScannerCapabilities();
        dynamic device = Connect();
        try
        {
            // The real sources: a feeder-only scanner has no flatbed (and so no overview),
            // whatever other properties its driver exposes.
            int? handling = ToInt(WiaScannerBackend.TryGetProperty(device.Properties,
                WiaScannerBackend.DocumentHandlingCapabilities));
            var sources = WiaDocumentHandling.Sources(handling);
            _sources = sources;
            caps.Sources = sources;
            caps.SupportsOverview = sources.Contains(ScanSource.Flatbed);
            caps.SupportsDuplex = WiaDocumentHandling.SupportsDuplex(handling);
            _supportsDuplex = caps.SupportsDuplex;

            // Physical bed and feeder sizes arrive in thousandths of an inch.
            object? bedWidth = WiaScannerBackend.TryGetProperty(device.Properties, WiaScannerBackend.HorizontalBedSize);
            object? bedHeight = WiaScannerBackend.TryGetProperty(device.Properties, WiaScannerBackend.VerticalBedSize);
            if (ToInt(bedWidth) is int bw && ToInt(bedHeight) is int bh && bw > 0 && bh > 0)
            {
                _bedInches = new SizeD(bw / 1000.0, bh / 1000.0);
                caps.FlatbedSizeInches = _bedInches;
            }
            if (sources.Contains(ScanSource.DocumentFeeder))
            {
                caps.FeederSizeInches = WiaDocumentHandling.FeederSizeInches(
                    ToInt(WiaScannerBackend.TryGetProperty(device.Properties, WiaScannerBackend.HorizontalSheetFeedSize)),
                    ToInt(WiaScannerBackend.TryGetProperty(device.Properties, WiaScannerBackend.VerticalSheetFeedSize)));
                _feederInches = caps.FeederSizeInches;
            }
            // The item's resolution property advertises its valid values as a list or a
            // range; when the driver reports neither, offer the common ladder (the session
            // snaps to whatever the driver accepts on scan).
            List<int>? resolutions = ReadResolutions(device, sources[0]);
            caps.SupportedResolutions = resolutions ?? [75, 150, 200, 300, 600, 1200];
            return caps;
        }
        finally
        {
            Release(device);
        }
    }, ReadTimeout, Info.Name);

    public Task<RgbaImage> PerformOverviewScanAsync(ScanSettings settings)
    {
        _cancelRequested = false;
        if (_sources is { } sources && !sources.Contains(ScanSource.Flatbed))
        {
            return Task.FromException<RgbaImage>(ScanException.Unsupported(() => Loc.T("This scanner has no flatbed to preview.")));
        }
        ProgressHandler?.Invoke(new ScanProgress(Loc.T("Scanning overview…")));
        return RunSta(() =>
        {
            dynamic device = Connect();
            try
            {
                object item = PrepareItem(device, 150, ScanSource.Flatbed, ColorMode.Color, null, false,
                                          PaperSize.Auto);
                try
                {
                    return Transfer(item);
                }
                finally
                {
                    Release(item);
                }
            }
            finally
            {
                Release(device);
            }
        });
    }

    public Task<IReadOnlyList<ScannedPage>> PerformScanAsync(ScanSettings settings, RectD? selection)
    {
        var pages = new List<ScannedPage>();
        // Reset here, not on the WIA thread: a Cancel pressed while that thread is still busy with
        // something else must survive until the scan starts.
        _cancelRequested = false;
        _scanning = true;
        return RunSta<IReadOnlyList<ScannedPage>>(() =>
        {
            try
            {
                Scan(settings, selection, pages.Add);
                return pages;
            }
            finally
            {
                _scanning = false;
            }
        });
    }

    public Task PerformScanAsync(ScanSettings settings, RectD? selection, Func<ScannedPage, Task> onPage)
    {
        _cancelRequested = false;
        _scanning = true;
        return PageHandover.Run(emit => RunSta(() =>
        {
            try
            {
                Scan(settings, selection, page => emit(page).GetAwaiter().GetResult());
                return true;
            }
            finally
            {
                _scanning = false;
            }
        }), onPage);
    }

    /// <summary>Scans on the WIA thread, passing each page to <paramref name="emit"/> as it transfers.</summary>
    private void Scan(ScanSettings settings, RectD? selection, Action<ScannedPage> emit)
    {
        _lastScanStop = null;
        _lastScanDuplex = -1;
        if (_cancelRequested) throw ScanException.Cancelled();
        if (UseDriverWindow)
        {
            ScanInDriverWindow(settings, emit);
            return;
        }
        ProgressHandler?.Invoke(new ScanProgress(Loc.T("Scanning…")));
        int count = 0;
        ScanSize.Check(ScanAreaInches(settings, selection), settings.Resolution);
        // One connection for the whole batch: every sheet of a feeder scan comes from the
        // same prepared item.
        dynamic device = Connect();
        try
        {
            bool feeder = settings.Source == ScanSource.DocumentFeeder;
            // Two-sided feeder scans deliver front, back, front, back… (FRONT_FIRST). A
            // feeder the device reported as one-sided is not asked.
            bool askedBoth = feeder && settings.Duplex == DuplexMode.Both;
            object item = PrepareItem(device, settings.Resolution, settings.Source, settings.ColorMode,
                                       feeder ? null : selection,
                                       askedBoth && _supportsDuplex != false,
                                       feeder ? settings.PaperSize : PaperSize.Auto, settings.CustomPaper);
            // Whether the driver took two-sided feeding, so the app knows what the pages are.
            if (askedBoth) _lastScanDuplex = _preparedTwoSided ? 1 : 0;
            try
            {
                if (feeder)
                {
                    count = ScanFeeder(item, settings, emit);
                }
                else
                {
                    RgbaImage image = Transfer(item);
                    if (_cancelRequested) throw ScanException.Cancelled();
                    emit(new ScannedPage(image, _preparedDpi, settings.ColorMode));
                    count = 1;
                }
            }
            finally
            {
                Release(item);
            }
        }
        finally
        {
            Release(device);
        }
        if (count == 0) throw ScanException.ScanFailed(() => Loc.T("The scanner did not return any image data."));
    }

    /// <summary>
    /// Keep pulling sheets until the feeder runs out, passing each to <paramref name="emit"/>, and
    /// return how many came. An empty feeder on the first sheet is the user's to fix ("Load paper in
    /// the feeder"); later it just ends the batch. Any other failure mid-batch keeps the sheets that
    /// already transferred (mirroring the macOS backend) and records why the scan stopped in
    /// <see cref="LastScanStop"/>.
    /// </summary>
    private int ScanFeeder(object item, ScanSettings settings, Action<ScannedPage> emit)
    {
        int count = 0;
        while (true)
        {
            RgbaImage image;
            try
            {
                image = Transfer(item);
            }
            catch (ScanException e) when (e.Problem == ScannerProblem.FeederEmpty && count > 0)
            {
                return count;
            }
            catch (ScanException e) when (count > 0 && e.Kind != ScanErrorKind.Cancelled)
            {
                _lastScanStop = ScanStop.From(e);
                return count;
            }
            if (_cancelRequested) throw ScanException.Cancelled();
            emit(new ScannedPage(image, _preparedDpi, settings.ColorMode));
            count++;
            ProgressHandler?.Invoke(new ScanProgress(Loc.T("Transferred sheet {0}…", count)));
        }
    }

    /// <summary>
    /// Shows the scanner's own WIA window for the connected device on the WIA thread and passes the pages it
    /// scans to <paramref name="emit"/>, a whole feeder batch when the window selected the feeder. The window
    /// chooses the settings, so the pages take the resolution and color the app asked for as their labels.
    /// </summary>
    private void ScanInDriverWindow(ScanSettings settings, Action<ScannedPage> emit)
    {
        ProgressHandler?.Invoke(new ScanProgress(Loc.T("Choose the settings in the scanner's window, then start the scan there…")));
        using var use = WiaApartment.Use();
        var dialogType = Type.GetTypeFromProgID(WiaScannerBackend.CommonDialogProgId)
            ?? throw ScanException.DeviceUnavailable(() => Loc.T("WIA is not available on this system."));
        dynamic dialog = Activator.CreateInstance(dialogType)!;
        dynamic device = Connect();
        object? items = null;
        object? item = null;
        try
        {
            _dialogThread = DriverWindows.CurrentThreadId;
            _waitingForDriverWindow = true;
            try
            {
                if (_cancelRequested) throw ScanException.Cancelled();
                // Intent and bias unspecified; a cancelled window returns nothing.
                items = dialog.ShowSelectItems(device, 0, 0, true, true, false);
            }
            catch (COMException e)
            {
                throw WiaErrors.ToScanException(e.HResult, e.Message);
            }
            finally
            {
                _waitingForDriverWindow = false;
            }
            if (items is null || _cancelRequested || ((dynamic)items).Count < 1) throw ScanException.Cancelled();
            item = (object)((dynamic)items!)[1];
            _preparedDpi = settings.Resolution;
            int? selected = ToInt(WiaScannerBackend.TryGetProperty(device.Properties, WiaScannerBackend.DocumentHandlingSelect));
            if (WiaDocumentHandling.FeederAlreadySelected(selected) is not null)
            {
                if (ScanFeeder(item, settings, emit) == 0)
                {
                    throw ScanException.ScanFailed(() => Loc.T("The scanner did not return any image data."));
                }
            }
            else
            {
                RgbaImage image = Transfer(item);
                if (_cancelRequested) throw ScanException.Cancelled();
                emit(new ScannedPage(image, settings.Resolution, settings.ColorMode));
            }
        }
        finally
        {
            if (item is not null) Release(item);
            if (items is not null) Release(items);
            Release(device);
            Release(dialog);
        }
    }

    public void CancelScan()
    {
        _cancelRequested = true;
        if (_waitingForDriverWindow)
        {
            // The window may not exist yet while the device connects, so ask again for a few seconds.
            Task.Run(async () =>
            {
                for (int i = 0; i < 20 && _waitingForDriverWindow; i++)
                {
                    DriverWindows.CloseThread(_dialogThread);
                    await Task.Delay(250);
                }
            });
            return;
        }
        // A transfer in flight cannot be aborted: the scanner ends this pass (a flatbed scan, or the
        // sheet in the feeder) and the scan stops after it.
        if (_scanning) ProgressHandler?.Invoke(new ScanProgress(Loc.T("Cancelling: the scanner is finishing this pass.")));
    }

    public Task CloseAsync() => Task.CompletedTask; // connections are per operation in WIA automation

    // MARK: - Transfers

    /// <summary>The area a scan covers, in inches; zero when the feeder's size is unknown.</summary>
    private SizeD ScanAreaInches(ScanSettings settings, RectD? selection)
    {
        if (settings.Source == ScanSource.DocumentFeeder)
        {
            if (_feederInches is not { } feederMax) return SizeD.Zero;
            var region = PaperSizes.FeederRegionInches(settings.PaperSize, settings.CustomPaper, feederMax);
            return new SizeD(region.Width, region.Height);
        }
        if (selection is { } sel)
        {
            var clamped = sel.Standardized.Intersection(new RectD(0, 0, 1, 1));
            if (clamped.Width > 0.001 && clamped.Height > 0.001)
            {
                return new SizeD(clamped.Width * _bedInches.Width, clamped.Height * _bedInches.Height);
            }
        }
        return _bedInches;
    }

    /// <summary>
    /// Select the source and set resolution, color and area on the item to scan. WIA errors
    /// (a busy or offline device, ...) become <see cref="ScanException"/>s via <see cref="WiaErrors"/>.
    /// </summary>
    private dynamic PrepareItem(dynamic device, int dpi, ScanSource source, ColorMode colorMode, RectD? selection,
                                bool duplex, PaperSize paperSize, SizeD customPaper = default)
    {
        try
        {
            return PrepareItemCore(device, dpi, source, colorMode, selection, duplex, paperSize, customPaper);
        }
        catch (COMException e)
        {
            throw WiaErrors.ToScanException(e.HResult, e.Message);
        }
    }

    /// <summary>
    /// The transparency unit's item for slides and negatives; null for the other sources and for
    /// devices that have no film item, which select the unit through WIA_DPS_TRANSPARENCY_SELECT instead.
    /// </summary>
    private static dynamic? FilmItem(dynamic device, ScanSource source)
    {
        if (!WiaDocumentHandling.IsFilm(source)) return null;
        int count = device.Items.Count;
        for (int i = 1; i <= count; i++)
        {
            dynamic candidate = device.Items[i];
            if (WiaDocumentHandling.IsFilmItem(WiaScannerBackend.TryGetProperty(candidate.Properties, WiaScannerBackend.ItemCategory)))
            {
                return candidate;
            }
        }
        if (!(bool)WiaScannerBackend.TrySetProperty(device.Properties, WiaScannerBackend.TransparencySelect, 2))
        {
            throw ScanException.ScanFailed(() => Loc.T("The scanner did not accept its film unit as the source."));
        }
        return null;
    }

    private dynamic PrepareItemCore(dynamic device, int dpi, ScanSource source, ColorMode colorMode, RectD? selection,
                                    bool duplex, PaperSize paperSize, SizeD customPaper)
    {
        // The first value the driver accepts: two-sided drivers that refuse FRONT_FIRST get
        // FEEDER | DUPLEX, and drivers that refuse two-sided feeding the feeder alone.
        dynamic properties = device.Properties;
        int? selected = WiaDocumentHandling.SelectSource(source, duplex, value =>
            (bool)WiaScannerBackend.TrySetProperty(properties, WiaScannerBackend.DocumentHandlingSelect, value));
        // A driver that took none of them may already have the feeder selected (single-source
        // drivers can make the property read-only): scan that, with its own sides. A feeder
        // that is not selected would scan whatever source is (the flatbed, over and over).
        // Drivers without the property keep their one source.
        if (selected is null && source == ScanSource.DocumentFeeder
            && (object?)WiaScannerBackend.TryGetProperty(properties, WiaScannerBackend.DocumentHandlingSelect) is { } current)
        {
            selected = WiaDocumentHandling.FeederAlreadySelected(ToInt(current))
                ?? throw ScanException.ScanFailed(() => Loc.T("The scanner did not accept its document feeder as the source."));
        }
        _preparedTwoSided = WiaDocumentHandling.ScansBothSides(selected);
        // Two-sided: every sheet in the feeder, both of its sides; one-sided feeding keeps the
        // driver's own page count, as before.
        if (_preparedTwoSided) WiaScannerBackend.TrySetProperty(device.Properties, WiaScannerBackend.Pages, WiaDocumentHandling.AllPages);
        var page = source == ScanSource.DocumentFeeder ? WiaDocumentHandling.PageSize(paperSize, paperSize == PaperSize.LongPaper ? _feederInches : customPaper) : null;
        if (page is not null)
        {
            WiaScannerBackend.TrySetProperty(device.Properties, WiaScannerBackend.PageSize, page.Value.PageSize);
            if (page.Value.PageSize == WiaDocumentHandling.PageCustom)
            {
                WiaScannerBackend.TrySetProperty(device.Properties, WiaScannerBackend.PageWidth, page.Value.WidthThousandths);
                WiaScannerBackend.TrySetProperty(device.Properties, WiaScannerBackend.PageHeight, page.Value.HeightThousandths);
            }
        }

        if (!WiaDocumentHandling.IsFilm(source)) WiaScannerBackend.TrySetProperty(device.Properties, WiaScannerBackend.TransparencySelect, 0);
        dynamic item = FilmItem(device, source) ?? device.Items[1];
        var props = item.Properties;
        if (WiaDocumentHandling.IsFilm(source)) WiaScannerBackend.TrySetProperty(props, WiaScannerBackend.FilmScanMode, 0);
        WiaScannerBackend.TrySetProperty(props, WiaScannerBackend.CurrentIntent, colorMode switch
        {
            ColorMode.Color => 1,
            _ => 2, // gray also for black & white: the app applies the threshold
        });
        // The nearest value the source accepts, then what the driver took: the extents and
        // the pages' resolution follow that, not the request.
        try
        {
            List<int>? valid = ValidResolutions(props[WiaScannerBackend.HorizontalResolution]);
            if (valid is { Count: > 0 }) dpi = valid.MinBy(v => Math.Abs(v - dpi));
        }
        catch
        {
            // no list: ask for the request as is
        }
        WiaScannerBackend.TrySetProperty(props, WiaScannerBackend.HorizontalResolution, dpi);
        WiaScannerBackend.TrySetProperty(props, WiaScannerBackend.VerticalResolution, dpi);
        if (ToInt(WiaScannerBackend.TryGetProperty(props, WiaScannerBackend.HorizontalResolution)) is > 0 and var taken) dpi = taken;
        _preparedDpi = dpi;

        // The paper's area on the feeder, in pixels at the chosen resolution, for drivers that
        // take the extents rather than the page size.
        if ((page is not null || (source == ScanSource.DocumentFeeder && paperSize == PaperSize.LongPaper))
            && _feederInches is { } feederMax)
        {
            var region = PaperSizes.FeederRegionInches(paperSize, customPaper, feederMax);
            WiaScannerBackend.TrySetProperty(props, WiaScannerBackend.XPos, 0);
            WiaScannerBackend.TrySetProperty(props, WiaScannerBackend.YPos, 0);
            WiaScannerBackend.TrySetProperty(props, WiaScannerBackend.XExtent, (int)Math.Round(region.Width * dpi));
            WiaScannerBackend.TrySetProperty(props, WiaScannerBackend.YExtent, (int)Math.Round(region.Height * dpi));
        }

        // Scan area in pixels at the chosen resolution; the selection is a normalized
        // top-left-origin rect of the bed.
        if (source == ScanSource.Flatbed && selection is { } sel)
        {
            var clamped = sel.Standardized.Intersection(new RectD(0, 0, 1, 1));
            if (clamped.Width > 0.001 && clamped.Height > 0.001)
            {
                WiaScannerBackend.TrySetProperty(props, WiaScannerBackend.XPos,
                    (int)Math.Round(clamped.MinX * _bedInches.Width * dpi));
                WiaScannerBackend.TrySetProperty(props, WiaScannerBackend.YPos,
                    (int)Math.Round(clamped.MinY * _bedInches.Height * dpi));
                WiaScannerBackend.TrySetProperty(props, WiaScannerBackend.XExtent,
                    (int)Math.Round(clamped.Width * _bedInches.Width * dpi));
                WiaScannerBackend.TrySetProperty(props, WiaScannerBackend.YExtent,
                    (int)Math.Round(clamped.Height * _bedInches.Height * dpi));
            }
        }
        return item;
    }

    /// <summary>One transfer (one sheet from the feeder). WIA errors become <see cref="ScanException"/>s via <see cref="WiaErrors"/>.</summary>
    private RgbaImage Transfer(object item)
    {
        ProgressHandler?.Invoke(new ScanProgress(Loc.T("Transferring…")));
        dynamic imageFile;
        try
        {
            imageFile = ((dynamic)item).Transfer(WiaScannerBackend.FormatBmp);
        }
        catch (COMException e)
        {
            throw WiaErrors.ToScanException(e.HResult, e.Message);
        }
        return LoadImageFile(imageFile);
    }

    /// <summary>Reads a WIA image file, then releases it.</summary>
    private static RgbaImage LoadImageFile(dynamic imageFile)
    {
        string tempPath = Path.Combine(Path.GetTempPath(), $"LazyScan-{Guid.NewGuid()}.{imageFile.FileExtension}");
        try
        {
            imageFile.SaveFile(tempPath);
            return WpfImageCodec.Load(tempPath);
        }
        catch (COMException e)
        {
            throw WiaErrors.ToScanException(e.HResult, e.Message);
        }
        finally
        {
            try { File.Delete(tempPath); } catch { /* best effort */ }
            Release(imageFile);
        }
    }

    private dynamic Connect()
    {
        using var use = WiaApartment.Use();
        var managerType = Type.GetTypeFromProgID(WiaScannerBackend.DeviceManagerProgId)
            ?? throw ScanException.DeviceUnavailable(() => Loc.T("WIA is not available on this system."));
        dynamic manager = Activator.CreateInstance(managerType)!;
        dynamic infos = manager.DeviceInfos;
        int count = infos.Count;
        for (int i = 1; i <= count; i++)
        {
            dynamic info = infos[i];
            if ((string)info.DeviceID == wiaDeviceId)
            {
                try
                {
                    return info.Connect();
                }
                catch (COMException e)
                {
                    throw WiaErrors.ToSessionException(e.HResult, e.Message);
                }
            }
        }
        // Unplugged: refresh the device list now rather than at the next poll, so the
        // sidebar drops it and the app can switch to another scanner.
        deviceLost();
        throw ScanException.DeviceUnavailable(() => Loc.T("{0} is no longer connected.", Info.Name));
    }

    /// <summary>
    /// The device's real resolution list via <see cref="ResolutionList.Build"/>: the valid
    /// values of the item's horizontal-resolution property (WiaSubType List = 2 or Range = 1),
    /// capped at the optical resolution. null when the driver does not expose them.
    /// </summary>
    private static List<int>? ReadResolutions(dynamic device, ScanSource unit)
    {
        try
        {
            // Resolutions are per functional unit: read the flatbed's (the feeder's on a
            // feeder-only scanner), like the macOS backend, rather than whatever unit the
            // driver last had selected.
            WiaScannerBackend.TrySetProperty(device.Properties, WiaScannerBackend.DocumentHandlingSelect,
                unit == ScanSource.DocumentFeeder ? WiaScannerBackend.HandlingFeeder : WiaScannerBackend.HandlingFlatbed);
            dynamic item = device.Items[1];
            List<int>? supported = ValidResolutions(item.Properties[WiaScannerBackend.HorizontalResolution]);
            if (supported is null) return null;
            object? optical = WiaScannerBackend.TryGetProperty(device.Properties, WiaScannerBackend.OpticalXResolution);
            int native = ToInt(optical) ?? 0;
            var list = ResolutionList.Build(preferred: null, supported, native);
            return list.Count > 0 ? list : null;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>The valid values of a resolution property (WiaSubType List = 2 or Range = 1); null for any other kind.</summary>
    private static List<int>? ValidResolutions(dynamic property)
    {
        int subType = Convert.ToInt32((object)property.SubType);
        var supported = new List<int>();
        if (subType == 2)
        {
            dynamic values = property.SubTypeValues;
            int count = values.Count;
            for (int i = 1; i <= count; i++) // WIA vectors are 1-based
            {
                object value = values[i];
                int dpi = Convert.ToInt32(value);
                if (dpi > 0) supported.Add(dpi);
            }
        }
        else if (subType == 1)
        {
            int min = Convert.ToInt32((object)property.SubTypeMin);
            int max = Convert.ToInt32((object)property.SubTypeMax);
            int step = Convert.ToInt32((object)property.SubTypeStep);
            supported.AddRange(ResolutionList.ExpandRange(min, max, step).Where(v => v > 0));
        }
        else
        {
            return null;
        }
        return supported;
    }

    /// <summary>A numeric property value; null when missing or not a number.</summary>
    private static int? ToInt(object? value)
    {
        if (value is null) return null;
        try
        {
            return Convert.ToInt32(value);
        }
        catch (Exception e) when (e is FormatException or InvalidCastException or OverflowException)
        {
            return null;
        }
    }

    private static void Release(object com)
    {
        try
        {
            if (OperatingSystem.IsWindows() && Marshal.IsComObject(com)) Marshal.ReleaseComObject(com);
        }
        catch
        {
            // best effort
        }
    }

    /// <summary>
    /// WIA Automation requires an STA apartment and must not be used from two threads at once;
    /// transfers also block. Each call runs on the WIA thread (<see cref="WiaApartment"/>), after
    /// the enumerations and session work queued before it, so the UI stays live.
    /// </summary>
    private Task<T> RunSta<T>(Func<T> work) => WiaApartment.Run(work, Timeout.InfiniteTimeSpan, Info.Name);

    /// <summary>For the calls that only read the device: a driver that never answers must not hold the scanner for good.</summary>
    internal static readonly TimeSpan ReadTimeout = TimeSpan.FromSeconds(30);
}
