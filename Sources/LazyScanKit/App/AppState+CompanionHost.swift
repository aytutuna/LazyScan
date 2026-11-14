import Darwin
import Foundation

// Twin of windows/LazyScan.App/AppViewModel.Companion.cs: the desktop's side of C1 (I21), the
// Mac receiving from paired phones. The phone's side is AppState+Companion.swift; the two roles share
// the protocol and nothing else. The shell passes the platform's pieces (`setUpCompanionHost`); the
// Phone window answers `confirmPhonePairing`.

/// The desktop's companion texts.
public enum CompanionHostText {
    public static var elsewhereMessage: String {
        L10n.t("Another copy of Lazy Scan receives from phones. Pair and manage phones there.")
    }

    public static var phoneNotPairedMessage: String {
        L10n.t("This phone is no longer paired.")
    }

    public static var outboxNotSavedMessage: String {
        L10n.t("The file could not be put in the phone's outbox.")
    }

    /// "The phone link could not start: …"
    public static func notStartedMessage(_ reason: String) -> String {
        L10n.t("The phone link could not start: {0}", reason)
    }

    /// "Adding pages from Aytu's iPhone…"
    public static func addingMessage(_ phoneName: String) -> String {
        L10n.t("Adding pages from {0}…", phoneName)
    }

    /// "2 pages from Aytu's iPhone will be added to the queue when the current step is done.", "… when this
    /// two-sided stack is finished." while `stackUnderWay` (`AppState.isStackUnderWay`), or what to
    /// choose when the settings do not collect pages; `taskReason` (`PhotoImport.ownSaveTaskReason`) names
    /// the task to leave when one keeps them out.
    public static func waitingMessage(pageCount: Int, from: String, collectsPages: Bool, stackUnderWay: Bool = false,
                                      taskReason: String? = nil) -> String {
        if stackUnderWay {
            return L10n.plural(pageCount, one: "{0} page from {1} will be added to the queue when this two-sided stack is finished.",
                               other: "{0} pages from {1} will be added to the queue when this two-sided stack is finished.", from)
        }
        if collectsPages {
            return L10n.plural(pageCount, one: "{0} page from {1} will be added to the queue when the current step is done.",
                               other: "{0} pages from {1} will be added to the queue when the current step is done.", from)
        }
        if let taskReason {
            return L10n.plural(pageCount, one: "{0} page from {1} is waiting: {2}. Leave the task or pick Document to PDF to add it to the queue.",
                               other: "{0} pages from {1} are waiting: {2}. Leave the task or pick Document to PDF to add them to the queue.",
                               from, taskReason)
        }
        return L10n.plural(pageCount, one: "{0} page from {1} is waiting: choose Document mode, or a document task, with Collect pages before saving on, to add it to the queue.",
                           other: "{0} pages from {1} are waiting: choose Document mode, or a document task, with Collect pages before saving on, to add them to the queue.",
                           from)
    }

    /// "The document from Aytu's iPhone could not be added: one of its pictures could not be read."
    public static func unreadableMessage(_ phoneName: String) -> String {
        L10n.t("The document from {0} could not be added: one of its pictures could not be read.", phoneName)
    }

    /// The document could not be read or added now; it stays in the inbox and in the waiting list.
    public static func notAddedMessage(_ phoneName: String, reason: String) -> String {
        L10n.t("The document from {0} could not be added to the queue now ({1}). It is kept in the waiting list.",
               phoneName, reason)
    }

    /// "Aytu's iPhone · 3 pages": a row of the waiting list.
    public static func keptRowText(pageCount: Int, phoneName: String) -> String {
        L10n.plural(pageCount, one: "{1} · {0} page", other: "{1} · {0} pages", phoneName)
    }

    /// The waiting list's label for a screen reader: "Waiting, 2 documents".
    public static func keptListLabel(count: Int) -> String {
        L10n.plural(count, one: "Waiting, {0} document", other: "Waiting, {0} documents")
    }

    /// "Add 3 pages from Aytu's iPhone now"
    public static func keptAddLabel(pageCount: Int, phoneName: String) -> String {
        L10n.plural(pageCount, one: "Add {0} page from {1} now", other: "Add {0} pages from {1} now", phoneName)
    }

    /// "Discard 3 pages from Aytu's iPhone"
    public static func keptDiscardLabel(pageCount: Int, phoneName: String) -> String {
        L10n.plural(pageCount, one: "Discard {0} page from {1}", other: "Discard {0} pages from {1}", phoneName)
    }

    /// "Discarded the document from Aytu's iPhone."
    public static func discardedMessage(_ phoneName: String) -> String {
        L10n.t("Discarded the document from {0}.", phoneName)
    }

    /// "Waiting for Aytu's iPhone to fetch it": a file is in the phone's outbox.
    public static func waitingToFetchMessage(_ phoneName: String) -> String {
        L10n.t("Waiting for {0} to fetch it", phoneName)
    }

    /// "Sent to Aytu's iPhone": the phone has the file.
    public static func sentToPhoneMessage(_ phoneName: String) -> String {
        L10n.t("Sent to {0}", phoneName)
    }
}

/// A phone's document that was cancelled or could not be added; its package is still in the inbox.
public struct KeptPhoneDocument: Identifiable {
    public var package: ReceivedPackage
    public var phoneName: String

    public var id: URL { package.url }
}

/// A file put in a paired phone's outbox (`AppState.sendToPhone`) and whether the phone has fetched it.
public struct PhoneSend: Identifiable, Equatable, Sendable {
    /// The outbox item's id.
    public var id: String
    public var fileName: String
    public var phoneName: String
    public var fetched = false

    public var message: String {
        fetched ? CompanionHostText.sentToPhoneMessage(phoneName) : CompanionHostText.waitingToFetchMessage(phoneName)
    }
}

extension AppState {
    /// Keeps the platform's pieces of the phone link (the Mac's keychain identity, interfaces, DNS-SD and
    /// the phones' sync keys) and starts it when a phone is paired; nothing listens otherwise, and no
    /// certificate is made. The cloud folder is watched while it runs.
    public func setUpCompanionHost(_ options: CompanionServiceOptions) {
        companionHostOptions = options
        if PairedDeviceStore(directory: options.settingsDirectory).count > 0 {
            ensureCompanionHost()
        }
    }

    /// The phone link, started now if it was not (the Phone window opens); nil when another copy of
    /// the app has it (`companionHostStatus.state == .elsewhere`) or it could not start
    /// (`companionHostError`).
    @discardableResult
    public func ensureCompanionHost() -> CompanionService? {
        if let companionService { return companionService }
        guard let options = companionHostOptions, companionHostStatus.state != .elsewhere else { return nil }
        // One copy of the app receives: the one holding the lock (released by the system when it quits).
        let folder = options.dataDirectory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let descriptor: Int32 = Darwin.open(folder.appendingPathComponent("companion.lock").path, O_RDWR | O_CREAT, 0o644)
        guard descriptor >= 0 else {
            companionHostError = String(cString: strerror(errno))
            return nil
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(descriptor)
            companionHostStatus = CompanionHostStatus(state: .elsewhere, networks: [], endpoints: [])
            return nil
        }
        companionHostLock = descriptor
        let service = CompanionService(options)
        service.router.approvePairing = { [weak self] request in
            await self?.askToPair(request) ?? false
        }
        service.onPackageReceived = { [weak self] package, device in
            Task { @MainActor in self?.queuePhoneDocument(package, phoneName: device.name) }
        }
        service.onSentFetched = { [weak self] _, itemId in
            Task { @MainActor in self?.phoneFetched(itemId) }
        }
        service.onSyncFolderProblem = { [weak self] message in
            Task { @MainActor in
                self?.syncFolderProblem = message
                if let message { self?.statusMessage = message }
            }
        }
        service.onChange = { [weak self] in
            Task { @MainActor in self?.companionHostChanged() }
        }
        service.queuedPages = scannedPages.count
        companionService = service
        companionHostError = nil
        Task { await service.start() }
        var names: [String: String] = [:]
        for device in service.devices.devices {
            names[device.id] = device.name
        }
        // Documents received before the app last closed and not yet in the queue.
        for package in service.inbox.pending() {
            queuePhoneDocument(package, phoneName: names[package.deviceId] ?? "")
        }
        return service
    }

    /// Puts a copy of the saved file `url` in the paired phone's outbox; the phone's next poll takes it, and
    /// `phoneSends` says when it has. False when the phone link is not running or the file could not be
    /// copied (`statusMessage` says why).
    @discardableResult
    public func sendToPhone(_ url: URL, to device: PairedDevice) -> Bool {
        guard let service = companionService else { return false }
        do {
            let item = try service.sendToPhone(url, deviceId: device.id)
            let send = PhoneSend(id: item.id, fileName: item.name, phoneName: device.name)
            phoneSends = Array((phoneSends + [send]).suffix(20))
            statusMessage = send.message
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    private func phoneFetched(_ itemId: String) {
        guard let index = phoneSends.firstIndex(where: { $0.id == itemId }) else { return }
        phoneSends[index].fetched = true
        statusMessage = phoneSends[index].message
    }

    /// Chooses the cloud folder phones put documents in (nil: none); false when that could not be saved.
    /// Twin of C# `SetPhoneSyncFolder`.
    @discardableResult
    public func setPhoneSyncFolder(_ folder: URL?, bookmark: Data? = nil) -> Bool {
        guard let service = companionService, service.setSyncFolder(folder, bookmark: bookmark) else { return false }
        syncFolderProblem = nil
        return true
    }

    /// Closes the bar above the window.
    public func dismissPhoneBar() {
        phoneBarMessage = nil
    }

    /// The queue can take the pages of a `.lsdoc` opened by hand now: it collects pages
    /// (`PhotoImport.isOffered` with Collect pages before saving on) and nothing else is going on
    /// (`canIngest`). A phone's documents do not need the first part (`addWaitingPhoneDocuments`).
    /// Twin of C# `CanTakePhonePages`.
    public var canTakePhonePages: Bool {
        PhotoImport.isOffered(settings) && settings.documentMultiPage && canIngest
    }

    /// The pages of a phone's document as the queue takes them: a document sent as new starts a
    /// document of its own (a split before its first page, when pages are queued already) and carries
    /// its name. Twin of the end of C# `CompanionPages.ToScannedPages`.
    nonisolated static func phonePages(_ package: PendingPackage, target: CompanionTarget, queueHasPages: Bool) -> [ScannedPage] {
        var pages = package.pages
        guard target == .new, var first = pages.first else { return pages }
        if queueHasPages { first = first.withDocumentBreak(.split) }
        if !package.documentName.isEmpty { first = first.withDocumentLabel(package.documentName) }
        pages[0] = first
        return pages
    }

    /// A document a phone sent, or put in the cloud folder (C2): added to the queue now, or as soon as the
    /// queue can take it.
    func queuePhoneDocument(_ package: ReceivedPackage, phoneName: String) {
        phoneDocuments.append((package, phoneName.isEmpty ? L10n.t("a phone") : phoneName))
        addWaitingPhoneDocuments()
    }

    /// Adds the oldest waiting document when pages can be brought in (`canIngest`), whatever the task or
    /// Collect pages setting; otherwise says what waits and tries again shortly (and when the work
    /// running now ends, `endOfWork`).
    func addWaitingPhoneDocuments() {
        guard !phoneDocuments.isEmpty else {
            phoneRetry?.cancel()
            phoneRetry = nil
            if phoneDocumentsWaitingMessage != nil { phoneDocumentsWaitingMessage = nil }
            return
        }
        guard canIngest else {
            var pages = 0
            var names: [String] = []
            for document in phoneDocuments {
                pages += document.package.pageCount
                if !names.contains(document.phoneName) { names.append(document.phoneName) }
            }
            let waiting = CompanionHostText.waitingMessage(pageCount: pages, from: names.count == 1 ? names[0] : L10n.t("your phones"),
                                                           collectsPages: true, stackUnderWay: isStackUnderWay)
            if waiting != phoneDocumentsWaitingMessage {
                phoneDocumentsWaitingMessage = waiting
                // Only the reason the user can act on is shown on the bar; being busy passes on its own.
                if !isBusy { phoneBarMessage = waiting }
            }
            if phoneRetry == nil {
                phoneRetry = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard let self, !Task.isCancelled else { return }
                    self.phoneRetry = nil
                    self.addWaitingPhoneDocuments()
                }
            }
            return
        }
        phoneRetry?.cancel()
        phoneRetry = nil
        let next = phoneDocuments.removeFirst()
        phoneDocumentsWaitingMessage = nil
        addPhoneDocument(next.package, phoneName: next.phoneName)
    }

    /// Decodes the document's pictures and queues its pages (`ingestPages`, as a phone's pages); the
    /// package is then released from the inbox and the bar says what arrived. A document with a picture
    /// that cannot be read is released too (it never will be); one that could not be read now, or
    /// whose adding was cancelled or failed, stays in the inbox and joins `keptPhoneDocuments`; it is added
    /// again at the next start unless it is discarded.
    private func addPhoneDocument(_ package: ReceivedPackage, phoneName: String) {
        // The pages go to the page list whatever the task: the task and Collect pages stay as they are.
        let s: ScanSettings = {
            var queued = settings
            if !(PhotoImport.isOffered(queued) && queued.documentMultiPage) {
                queued.intent = .document
                queued.taskId = nil
                queued.documentMultiPage = true
            }
            return queued
        }()
        let queueHasPages = !scannedPages.isEmpty
        runExclusive(stopsInBackground: false) { flag in
            self.statusMessage = CompanionHostText.addingMessage(phoneName)
            let url = package.url
            let read: Result<PendingPackage, Error> = await Task.detached(priority: .userInitiated) {
                Result { try PendingPackage.read(url) }
            }.value
            let decoded: PendingPackage
            switch read {
            case .success(let pending):
                decoded = pending
            case .failure(let error as CompanionPackageError):
                self.companionService?.inbox.release(package)
                self.errorMessage = error.kind == .unsupportedImage
                    ? CompanionHostText.unreadableMessage(phoneName) : error.localizedDescription
                self.statusMessage = L10n.t("Ready.")
                return
            case .failure(let error):
                self.keepPhoneDocument(package, phoneName: phoneName,
                                       message: CompanionHostText.notAddedMessage(phoneName, reason: error.localizedDescription))
                self.statusMessage = L10n.t("Ready.")
                return
            }
            let pages = AppState.phonePages(decoded, target: package.target, queueHasPages: queueHasPages)
            let intake = PageIntake(settings: s, source: .phone, generation: nil)
            do {
                guard try await self.ingestPages(pages, intake: intake, flag: flag) != nil else { return }
            } catch ScanError.cancelled, is CancellationError {
                let kept = CompanionProtocol.keptMessage(pages.count, phoneName: phoneName, onMac: true)
                self.statusMessage = kept
                self.keepPhoneDocument(package, phoneName: phoneName, message: kept)
                return
            } catch {
                self.keepPhoneDocument(package, phoneName: phoneName,
                                       message: CompanionHostText.notAddedMessage(phoneName, reason: error.localizedDescription))
                self.statusMessage = L10n.t("Ready.")
                return
            }
            let count = pages.count
            self.setStatus(L10n.plural(count, one: "Added {0} page from {1} — {2} in queue.", other: "Added {0} pages from {1} — {2} in queue.",
                                       phoneName, self.scannedPages.count),
                           StatusDetail(head: .pagesAdded(count, queue: self.scannedPages.count, blank: 0, split: 0)))
            self.companionService?.inbox.release(package)
            self.phoneBarMessage = CompanionProtocol.addedMessage(count, phoneName: phoneName)
        }
    }

    /// Lists a document that was cancelled or could not be added, and says so on the bar.
    func keepPhoneDocument(_ package: ReceivedPackage, phoneName: String, message: String) {
        if !keptPhoneDocuments.contains(where: { $0.id == package.url }) {
            keptPhoneDocuments.append(KeptPhoneDocument(package: package, phoneName: phoneName))
        }
        if !keptPhoneListShown {
            keptPhoneListShown = true
            keptPhoneDocumentsOpen = true
        }
        phoneBarMessage = message
    }

    /// Adds a kept document as a new one arriving; when the app is busy it joins the waiting documents.
    public func addKeptPhoneDocument(_ kept: KeptPhoneDocument) {
        guard let index = keptPhoneDocuments.firstIndex(where: { $0.id == kept.id }) else { return }
        keptPhoneDocuments.remove(at: index)
        queuePhoneDocument(kept.package, phoneName: kept.phoneName)
    }

    /// Deletes a kept document from the inbox, so it is not added at the next start.
    public func discardKeptPhoneDocument(_ kept: KeptPhoneDocument) {
        guard let index = keptPhoneDocuments.firstIndex(where: { $0.id == kept.id }) else { return }
        keptPhoneDocuments.remove(at: index)
        companionService?.inbox.release(kept.package)
        phoneBarMessage = CompanionHostText.discardedMessage(kept.phoneName)
    }

    /// Asks `confirmPhonePairing`; allows the pairing when nobody is there to ask.
    private func askToPair(_ request: PairRequest) async -> Bool {
        guard let ask = confirmPhonePairing else { return true }
        return await ask(request)
    }

    private func companionHostChanged() {
        guard let service = companionService else { return }
        // Set every time, so a view showing the phones or the pairing follows too.
        companionHostStatus = service.status
    }
}
