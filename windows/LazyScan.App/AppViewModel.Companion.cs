using System.Collections.ObjectModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Threading;
using LazyScan.App.Services;
using LazyScan.App.Services.Companion;
using LazyScan.Core;

namespace LazyScan.App;

/// <summary>
/// The phone link (<see cref="CompanionService"/>): started when a phone is paired (or the Phone
/// window opens), receiving only on trusted networks, and documents from paired phones added to the
/// queue on their own, with a notification. Documents phones put in the cloud sync folder (C2) come
/// the same way: the service watches the folder while it runs and receives them into the inbox.
/// </summary>
public sealed partial class AppViewModel
{
    /// <summary>One instance per user session receives from phones; others say so.</summary>
    private const string CompanionMutexName = @"Local\LazyScan.PhoneLink";

    private CompanionService? _companion;
    private Mutex? _companionMutex;
    private WindowsNetworkSource? _companionNetworks;
    /// <summary>Documents from phones waiting to be added to the queue, oldest first, with the phone's name.</summary>
    private readonly Queue<(ReceivedPackage Package, string PhoneName)> _phoneDocuments = new();
    /// <summary>Retries adding waiting documents while the app is busy or the queue does not collect pages.</summary>
    private DispatcherTimer? _phoneRetryTimer;
    /// <summary>Documents that were cancelled or could not be added, in the phone bar's waiting list; they stay in the inbox until added or discarded.</summary>
    public ObservableCollection<KeptPhoneDocument> KeptPhoneDocuments { get; } = [];
    /// <summary>The queue's page count, for phones asking from the server's threads.</summary>
    private volatile int _queuedPageCount;
    /// <summary>The paired phones when the link is not running (it has its own store once started).</summary>
    private PairedDeviceStore? _pairedPhones;
    /// <summary>Files put in phones' outboxes, the latest 20; each says which of its files the phone has yet to fetch.</summary>
    private readonly List<PhoneSend> _phoneSends = [];

    /// <summary>One Send to phone: the files copied into a phone's outbox and the outbox items still waiting.</summary>
    private sealed class PhoneSend(string phoneId, string phoneName, IReadOnlyList<string> paths)
    {
        public string PhoneId { get; } = phoneId;
        public string PhoneName { get; } = phoneName;
        public IReadOnlyList<string> Paths { get; } = paths;
        /// <summary>Outbox item id to the file it holds.</summary>
        public Dictionary<string, string> Waiting { get; } = [];
    }

    /// <summary>One row of the phone bar's waiting list.</summary>
    public sealed class KeptPhoneDocument(ReceivedPackage package, string phoneName)
    {
        public ReceivedPackage Package { get; } = package;
        public string PhoneName { get; } = phoneName;
        public string RowText => Loc.Plural(Package.PageCount, "{1} · {0} page", "{1} · {0} pages", PhoneName);
        public string AddLabel => Loc.Plural(Package.PageCount, "Add {0} page from {1} now", "Add {0} pages from {1} now", PhoneName);
        public string DiscardLabel => Loc.Plural(Package.PageCount, "Discard {0} page from {1}", "Discard {0} pages from {1}", PhoneName);
    }

    /// <summary>The phone link; null until it is started, and when another window of the app has it.</summary>
    public CompanionService? Companion => _companion;

    /// <summary>Another window of the app receives from phones (<see cref="CompanionListenState.Elsewhere"/>).</summary>
    public bool CompanionElsewhere { get; private set; }

    /// <summary>Why the link could not start; null when it started or was not tried.</summary>
    public string? CompanionError { get; private set; }

    /// <summary>The last file in the cloud folder that could not be read; null since the folder was chosen.</summary>
    public string? SyncFolderProblem { get; private set; }

    /// <summary>
    /// Asks the user whether a phone that presented the pairing code may pair (the Phone window shows
    /// it). Without anyone to ask, the pairing is allowed: the code was only on this screen.
    /// </summary>
    public Func<PairRequest, CancellationToken, Task<bool>>? ConfirmPhonePairing { get; set; }

    /// <summary>Raised on the UI thread with the message after a phone's pages were added, or are waiting.</summary>
    public event Action<string>? PhoneDocumentArrived;

    /// <summary>Raised on the UI thread when the link's status, phones or networks changed.</summary>
    public event Action? CompanionChanged;

    /// <summary>
    /// Raised on the UI thread when files were put in a phone's outbox, or the phone has fetched them: the bar's lead
    /// ("Waiting for Aytu's iPhone to fetch it", "Sent to Aytu's iPhone") and the files.
    /// </summary>
    public event Action<string, IReadOnlyList<string>>? PhoneSendChanged;

    /// <summary>Raised on the UI thread when the phone that files were waiting for was removed.</summary>
    public event Action? PhoneSendCleared;

    /// <summary>"3 pages from Aytu's iPhone are waiting: …"; null when nothing waits.</summary>
    public string? PhoneDocumentsWaitingMessage { get; private set; }

    /// <summary>The queue can take a phone's pages now: nothing else is going on, whatever the task.</summary>
    public bool CanAddPhoneDocuments =>
        !IsBusy && !IsStackUnderWay && !ShowPhotoReview && !ShowIdCardReview;

    /// <summary>A package opened by hand can be added now: <see cref="CanAddPhoneDocuments"/> and the queue collects pages.</summary>
    public bool CanTakePhonePages => CanAddPhoneDocuments && CollectsPackages;

    /// <summary>
    /// Starts the phone link at launch when a phone is paired (nothing listens otherwise, and no
    /// certificate is made). <paramref name="options"/> replaces the platform's pieces (harnesses).
    /// </summary>
    public void StartCompanionIfPaired(CompanionServiceOptions? options = null)
    {
        string settings = options?.SettingsDirectory ?? CompanionSettingsDirectory;
        if (new PairedDeviceStore(settings).Count > 0) EnsureCompanion(options);
    }

    /// <summary>The phone link, started now if it was not (the Phone window opens); null when another window has it.</summary>
    public CompanionService? EnsureCompanion(CompanionServiceOptions? options = null)
    {
        if (_companion is not null) return _companion;
        _companionMutex ??= new Mutex(false, CompanionMutexName, out _);
        bool owned;
        try
        {
            owned = _companionMutex.WaitOne(0);
        }
        catch (AbandonedMutexException)
        {
            owned = true;
        }
        if (!owned)
        {
            CompanionElsewhere = true;
            _companionMutex.Dispose();
            _companionMutex = null;
            return null;
        }
        CompanionElsewhere = false;
        CompanionError = null;
        try
        {
            if (options is null)
            {
                var certificates = new CompanionCertificateStore();
                _companionNetworks = new WindowsNetworkSource();
                options = new CompanionServiceOptions
                {
                    SettingsDirectory = CompanionSettingsDirectory,
                    DataDirectory = CompanionDataDirectory,
                    Certificate = certificates.Current,
                    RenewCertificate = certificates.Renew,
                    Networks = _companionNetworks,
                    Advertiser = new WindowsDnsSdAdvertiser(),
                    DesktopName = Environment.MachineName,
                    AnyPortFallback = !Packaging.IsPackaged,
                };
            }
            var companion = new CompanionService(options);
            companion.Router.ApprovePairing = ApprovePhonePairingAsync;
            companion.Router.QueuedPages = () => _queuedPageCount;
            companion.PackageReceived += (_, e) =>
                _dispatcher.BeginInvoke(() => QueuePhoneDocument(e.Package, e.Device.Name));
            companion.Changed += (_, _) => _dispatcher.BeginInvoke(() =>
            {
                DropSendsToRemovedPhones();
                NotifyAll();
                CompanionChanged?.Invoke();
            });
            companion.SentFetched += (_, e) => _dispatcher.BeginInvoke(() => PhoneFetched(e.Id));
            companion.SyncFolderProblem += (_, message) => _dispatcher.BeginInvoke(() =>
            {
                SyncFolderProblem = message;
                StatusMessage = message;
                NotifyAll();
                CompanionChanged?.Invoke();
            });
            _companion = companion;
            _queuedPageCount = ScannedPages.Count;
            ScannedPages.CollectionChanged += (_, _) => _queuedPageCount = ScannedPages.Count;
            _ = StartCompanionAsync(companion);
            QueuePendingPhoneDocuments(companion);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or InvalidOperationException
                                      or System.Runtime.InteropServices.COMException)
        {
            CompanionError = e.Message;
            System.Diagnostics.Trace.TraceError($"The phone link did not start: {e}");
        }
        return _companion;
    }

    /// <summary>
    /// The phone Send to phone goes to: the one seen last of the paired phones; null when none is paired.
    /// </summary>
    public PairedDevice? SendPhone
    {
        get
        {
            var devices = (_companion?.Devices ?? (_pairedPhones ??= new PairedDeviceStore(CompanionSettingsDirectory))).Devices;
            return devices.OrderByDescending(d => d.LastSeen ?? d.Paired).FirstOrDefault();
        }
    }

    /// <summary>The name Send to phone shows for <paramref name="phone"/>.</summary>
    public static string PhoneNameOf(PairedDevice phone) => phone.Name.Length > 0 ? phone.Name : Loc.T("Phone");

    /// <summary>Every one of these files was sent to a phone and the phone has not fetched it yet.</summary>
    public bool IsWaitingForPhone(IReadOnlyList<string> paths)
    {
        DropFetchedFiles();
        return paths.Count > 0 && paths.All(p => _phoneSends.Any(s => s.Waiting.ContainsValue(p)));
    }

    /// <summary>
    /// Forgets the files the outbox no longer lists: the fetch was seen by another window of the app, or the outbox
    /// dropped the file after <see cref="CompanionOutbox.KeepFor"/>.
    /// </summary>
    private void DropFetchedFiles()
    {
        if (_phoneSends.Count == 0) return;
        var outbox = _companion?.Outbox ?? new CompanionOutbox(Path.Combine(CompanionDataDirectory, "Outbox"));
        foreach (var send in _phoneSends.Where(s => s.Waiting.Count > 0))
        {
            var listed = outbox.List(send.PhoneId, DateTimeOffset.Now).Select(i => i.Id).ToHashSet();
            foreach (var id in send.Waiting.Keys.Where(id => !listed.Contains(id)).ToList()) send.Waiting.Remove(id);
        }
    }

    /// <summary>
    /// Copies the files into the phone's outbox, where its next poll takes them, and says so in the phone bar. The link is
    /// started if it was not; when another window of the app has it, or it cannot start, the files wait all the same. A file
    /// that cannot be copied is reported in the InfoBar. Returns whether every file was put there.
    /// </summary>
    private bool SendToPhone(IReadOnlyList<string> paths)
    {
        if (SendPhone is not { } phone) return false;
        var outbox = EnsureCompanion()?.Outbox ?? new CompanionOutbox(Path.Combine(CompanionDataDirectory, "Outbox"));
        string phoneName = PhoneNameOf(phone);
        var send = new PhoneSend(phone.Id, phoneName, [.. paths.Where(p => !IsWaitingForPhone([p]))]);
        bool failed = false;
        foreach (var path in send.Paths)
        {
            try
            {
                var item = outbox.Add(phone.Id, path, Path.GetFileName(path), CompanionOutbox.ContentTypeFor(path), DateTimeOffset.Now);
                send.Waiting[item.Id] = path;
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                ErrorTitle = Loc.T("Could not send");
                ErrorMessage = Loc.T("Could not send {0} to {1}: {2}", Path.GetFileName(path), phoneName, e.Message.TrimEnd('.'));
                failed = true;
                break;
            }
        }
        if (send.Waiting.Count > 0)
        {
            _phoneSends.Add(send);
            if (_phoneSends.Count > 20) _phoneSends.RemoveAt(0);
            PhoneSendChanged?.Invoke(CompanionProtocol.WaitingToFetchMessage(phoneName), [.. send.Waiting.Values]);
        }
        return !failed;
    }

    /// <summary>A phone acknowledged an outbox file: once it has all of a send's files, the phone bar says so.</summary>
    private void PhoneFetched(string itemId)
    {
        var send = _phoneSends.FirstOrDefault(s => s.Waiting.ContainsKey(itemId));
        if (send is null) return;
        send.Waiting.Remove(itemId);
        if (send.Waiting.Count == 0) PhoneSendChanged?.Invoke(CompanionProtocol.SentToPhoneMessage(send.PhoneName), send.Paths);
        NotifyAll();
    }

    /// <summary>A phone that was removed no longer fetches anything (its outbox is deleted): its sends go and the bar clears.</summary>
    private void DropSendsToRemovedPhones()
    {
        if (_companion is not { } companion || _phoneSends.Count == 0) return;
        var paired = companion.Devices.Devices.Select(d => d.Id).ToHashSet();
        var gone = _phoneSends.Where(s => !paired.Contains(s.PhoneId)).ToList();
        if (gone.Count == 0) return;
        _phoneSends.RemoveAll(gone.Contains);
        if (gone.Any(s => s.Waiting.Count > 0)) PhoneSendCleared?.Invoke();
    }

    /// <summary>Chooses the cloud folder phones put documents in (null: none); false when that could not be saved.</summary>
    public bool SetPhoneSyncFolder(string? path)
    {
        if (_companion is null || !_companion.SetSyncFolder(path)) return false;
        SyncFolderProblem = null;
        CompanionChanged?.Invoke();
        return true;
    }

    /// <summary>Documents received before the app last closed, not yet in the queue; an inbox that cannot be read is left for next time.</summary>
    private void QueuePendingPhoneDocuments(CompanionService companion)
    {
        IReadOnlyList<ReceivedPackage> pending;
        try
        {
            pending = companion.Inbox.Pending();
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            System.Diagnostics.Trace.TraceWarning($"Could not read the documents waiting from phones: {e.Message}");
            return;
        }
        var names = companion.Devices.Devices.ToDictionary(d => d.Id, d => d.Name);
        foreach (var package in pending)
        {
            QueuePhoneDocument(package, names.GetValueOrDefault(package.DeviceId, Loc.T("a phone")));
        }
    }

    /// <summary>Adds a kept document to the queue now, or as soon as the queue can take it.</summary>
    public void AddKeptPhoneDocument(KeptPhoneDocument kept)
    {
        if (!KeptPhoneDocuments.Remove(kept)) return;
        QueuePhoneDocument(kept.Package, kept.PhoneName);
    }

    /// <summary>Deletes a kept document from the inbox without adding it.</summary>
    public void DiscardKeptPhoneDocument(KeptPhoneDocument kept)
    {
        if (!KeptPhoneDocuments.Remove(kept)) return;
        _companion?.Inbox.Release(kept.Package);
        PhoneDocumentArrived?.Invoke(Loc.T("Discarded the document from {0}.", kept.PhoneName));
    }

    private static string CompanionSettingsDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Lazy Scan");

    private static string CompanionDataDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Lazy Scan", "Companion");

    private async Task StartCompanionAsync(CompanionService companion)
    {
        try
        {
            await companion.StartAsync();
        }
        catch (Exception e)
        {
            System.Diagnostics.Trace.TraceError($"The phone link did not start: {e}");
        }
    }

    /// <summary>Asks <see cref="ConfirmPhonePairing"/> on the UI thread; allows the pairing when nobody is there to ask.</summary>
    private async Task<bool> ApprovePhonePairingAsync(PairRequest request, CancellationToken cancellation)
    {
        var ask = await _dispatcher.InvokeAsync(() => ConfirmPhonePairing);
        if (ask is null) return true;
        return await await _dispatcher.InvokeAsync(() => ask(request, cancellation));
    }

    /// <summary>A document a phone sent: added to the queue now, or as soon as the queue can take it.</summary>
    private void QueuePhoneDocument(ReceivedPackage package, string phoneName)
    {
        _phoneDocuments.Enqueue((package, phoneName.Length > 0 ? phoneName : Loc.T("a phone")));
        AddWaitingPhoneDocuments();
    }

    /// <summary>Adds the oldest waiting document when the queue can take it; otherwise says what waits and tries again shortly.</summary>
    private void AddWaitingPhoneDocuments()
    {
        if (_phoneDocuments.Count == 0)
        {
            _phoneRetryTimer?.Stop();
            if (PhoneDocumentsWaitingMessage is not null)
            {
                PhoneDocumentsWaitingMessage = null;
                NotifyAll();
            }
            return;
        }
        if (!CanAddPhoneDocuments)
        {
            string waiting = WaitingMessage();
            if (waiting != PhoneDocumentsWaitingMessage)
            {
                PhoneDocumentsWaitingMessage = waiting;
                if (!IsBusy) PhoneDocumentArrived?.Invoke(waiting);
                NotifyAll();
            }
            if (_phoneRetryTimer is null)
            {
                _phoneRetryTimer = new DispatcherTimer(DispatcherPriority.Background, _dispatcher) { Interval = TimeSpan.FromSeconds(1) };
                _phoneRetryTimer.Tick += (_, _) => AddWaitingPhoneDocuments();
            }
            _phoneRetryTimer.Start();
            return;
        }
        _phoneRetryTimer?.Stop();
        var (package, phoneName) = _phoneDocuments.Dequeue();
        PhoneDocumentsWaitingMessage = null;
        _ = AddPhoneDocumentAsync(package, phoneName);
    }

    private string WaitingMessage()
    {
        int pages = _phoneDocuments.Sum(d => d.Package.PageCount);
        string from = _phoneDocuments.Select(d => d.PhoneName).Distinct().Count() == 1 ? _phoneDocuments.Peek().PhoneName : Loc.T("your phones");
        if (IsStackUnderWay)
        {
            return Loc.Plural(pages, "{0} page from {1} will be added to the queue when this two-sided stack is finished.",
                "{0} pages from {1} will be added to the queue when this two-sided stack is finished.", from);
        }
        return Loc.Plural(pages, "{0} page from {1} will be added to the queue when the current step is done.",
            "{0} pages from {1} will be added to the queue when the current step is done.", from);
    }

    /// <summary>
    /// Decodes, spools and queues the document's pages; the package is then released from the
    /// inbox. A document with a picture that cannot be read is released too (it never will be); one
    /// that was cancelled or could not be spooled (the disk is full, the folder cannot be made) stays
    /// in the inbox and goes to the waiting list, to be added now, discarded, or added at the next start.
    /// </summary>
    private async Task AddPhoneDocumentAsync(ReceivedPackage package, string phoneName)
    {
        int added = 0;
        string? problem = null;
        bool unreadable = false;
        bool cancelled = false;
        bool kept = false;
        await RunExclusive(async token =>
        {
            SavedBarPaths = null;
            _heldCopy = null;
            StatusMessage = Loc.T("Adding pages from {0}…", phoneName);
            NotifyAll();
            bool queueHasPages = ScannedPages.Count > 0;
            string spoolDirectory = _spool.Directory;
            try
            {
                Directory.CreateDirectory(spoolDirectory);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                kept = true;
                problem = Loc.T("The document from {0} could not be added to the queue now ({1}). It is kept in the waiting list.",
                    phoneName, e.Message.TrimEnd('.'));
                StatusMessage = Loc.T("Ready.");
                return;
            }
            CompanionDocument document;
            try
            {
                document = await Task.Run(() => CompanionPackage.ReadFile(package.Path));
            }
            catch (CompanionPackageException)
            {
                unreadable = true;
                problem = Loc.T("The document from {0} could not be added: one of its pictures could not be read.", phoneName);
                StatusMessage = Loc.T("Ready.");
                return;
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                kept = true;
                problem = Loc.T("The document from {0} could not be added to the queue now ({1}). It is kept in the waiting list.",
                    phoneName, e.Message.TrimEnd('.'));
                StatusMessage = Loc.T("Ready.");
                return;
            }
            List<ScannedPage> pages;
            var spooledSoFar = new List<ScannedPage>();
            try
            {
                // Each picture is decoded from the package's bytes, spooled and dropped before the next, so a long
                // document never holds all its pixels at once. A failure here is the picture's, or the memory's.
                pages = await Task.Run(() => CompanionPages.ToScannedPages(document, package.Target, queueHasPages,
                    PendingPackage.Decode, keep: page =>
                    {
                        token.ThrowIfCancellationRequested();
                        var spooledPage = SpoolPages([page], spoolDirectory)[0];
                        spooledSoFar.Add(spooledPage);
                        return spooledPage;
                    }), token);
            }
            catch (Exception e) when (e is OperationCanceledException or OutOfMemoryException or NotSupportedException
                                          or System.IO.FileFormatException or COMException or ArgumentException
                                          or InvalidOperationException or OverflowException or IOException)
            {
                DeleteSpoolFiles(spooledSoFar);
                if (e is OperationCanceledException)
                {
                    cancelled = true;
                    kept = true;
                    throw;
                }
                unreadable = true;
                problem = e is OutOfMemoryException
                    ? Loc.T("The document from {0} could not be added: there is not enough memory for its pictures.", phoneName)
                    : Loc.T("The document from {0} could not be added: one of its pictures could not be read.", phoneName);
                StatusMessage = Loc.T("Ready.");
                return;
            }
            var spooled = pages.Select(p => new PageItem(p)).ToList();
            foreach (var item in spooled) ScannedPages.Add(item);
            added = spooled.Count;
            if (spooled.Count > 0) SetLastScan(ScanHistory.MakePreview(spooled[^1].Page.Image, CanvasPreviewMaxSide));
            if (PageProcessor.ReadsBarcodes(Settings)) _readBarcodesAfterWork = true;
            SetStatus(Loc.Plural(added, "Added {0} page from {1} — {2} in queue.", "Added {0} pages from {1} — {2} in queue.",
                phoneName, ScannedPages.Count), new(new StatusHead.PagesAdded(added, ScannedPages.Count, 0, 0)));
        });
        if (kept) KeptPhoneDocuments.Add(new KeptPhoneDocument(package, phoneName));
        if (problem is not null && kept)
        {
            PhoneDocumentArrived?.Invoke(problem);
        }
        else if (problem is not null)
        {
            ErrorMessage = problem;
            NotifyAll();
        }
        if (added > 0 || unreadable) _companion?.Inbox.Release(package);
        if (added > 0) PhoneDocumentArrived?.Invoke(CompanionProtocol.AddedMessage(added, phoneName));
        if (cancelled)
        {
            string keptText = CompanionProtocol.KeptMessage(package.PageCount, phoneName, onMac: true);
            StatusMessage = keptText;
            NotifyAll();
            PhoneDocumentArrived?.Invoke(keptText);
        }
        AddWaitingPhoneDocuments();
    }

    /// <summary>On app exit: the phone link stops listening and withdraws its advertisement.</summary>
    private void ShutdownCompanion()
    {
        _phoneRetryTimer?.Stop();
        if (_companion is { } companion)
        {
            _companion = null;
            try
            {
                companion.DisposeAsync().AsTask().Wait(TimeSpan.FromSeconds(5));
            }
            catch (Exception e)
            {
                System.Diagnostics.Trace.TraceWarning($"The phone link did not stop cleanly: {e.Message}");
            }
        }
        _companionNetworks?.Dispose();
        _companionNetworks = null;
        if (_companionMutex is { } mutex)
        {
            _companionMutex = null;
            try
            {
                mutex.ReleaseMutex();
            }
            catch (ApplicationException)
            {
                // Not held by this thread: closing the handle releases it.
            }
            mutex.Dispose();
        }
    }
}
