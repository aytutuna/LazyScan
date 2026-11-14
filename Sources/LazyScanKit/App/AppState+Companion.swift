import Foundation

// The phone's side of C1 (I20): pairing with a desktop from its code, checking the link, sending the
// queue as a `.lsdoc` and taking what the desktop holds for the phone. The desktop is the server
// (windows/LazyScan.Core/Companion); this is the client, through `CompanionClient`. When the
// desktop cannot be reached, documents go through the cloud sync folder instead (C2, `SyncPackage`).

/// The companion's texts on the phone.
public enum CompanionText {
    public static var localNetworkOffReason: String { L10n.t("Local Network access is off for Lazy Scan. Turn it on in Settings.") }
    public static var refusedReason: String {
        L10n.t("The computer is on this network but refused the connection. Check its firewall, or run the phone troubleshooter on the computer.")
    }
    public static var refusedSyncFolderReason: String {
        L10n.t("The computer is on this network but refused the connection. Documents go to the cloud folder instead.")
    }
    public static var notPairedMessage: String {
        L10n.t("Pair this device with a computer first: choose Pair a phone in Lazy Scan on the computer and scan its code.")
    }
    public static var outboxFullMessage: String {
        L10n.plural(PhoneOutbox.maxItems, one: "{0} document is waiting to be sent already. Send it, or remove it first.",
                    other: "{0} documents are waiting to be sent already. Send them, or remove some first.")
    }
    public static var unreachableMessage: String { L10n.t("The computer cannot be reached.") }
    public static var wrongCertificateMessage: String {
        L10n.t("The computer that answered is not the one this device was paired with. If pairing was reset there, pair again.")
    }
    public static var badResponseMessage: String { L10n.t("The computer's answer could not be read.") }
    public static var notSavedMessage: String { L10n.t("The pairing could not be saved on this device. Try again.") }
    public static var syncFolderHint: String {
        L10n.t("Set a cloud folder in My computer to send when the computer cannot be reached.")
    }
    public static var syncFolderUnavailableMessage: String {
        L10n.t("The cloud folder could not be opened. Choose it again in My computer.")
    }
    public static var syncFolderLine: String {
        L10n.t("A folder in iCloud Drive or OneDrive that your computer also syncs. Documents go here, encrypted, when the computer cannot be reached.")
    }

    /// "Office PC was not found. Lazy Scan may not be open on it, or it is on another network."
    public static func notOnNetworkReason(_ desktopName: String) -> String {
        L10n.t("{0} was not found. Lazy Scan may not be open on it, or it is on another network.", desktopName)
    }

    /// "Office PC cannot be reached on this network."
    public static func cannotReachMessage(_ desktopName: String) -> String {
        L10n.t("{0} cannot be reached on this network.", desktopName)
    }

    /// "Sending to Office PC..."
    public static func sendingMessage(_ desktopName: String) -> String {
        L10n.t("Sending to {0}...", desktopName)
    }

    public static var cancelledNothingSentMessage: String { L10n.t("Cancelled. Nothing was sent.") }
    public static var cancelledWaitingMessage: String { L10n.t("Cancelled. The document is waiting in My computer.") }

    /// "Paired with Office PC."
    public static func pairedMessage(_ desktopName: String) -> String {
        L10n.t("Paired with {0}.", desktopName)
    }

    /// "This device is no longer paired with Office PC."
    public static func unpairedMessage(_ desktopName: String) -> String {
        L10n.t("This device is no longer paired with {0}.", desktopName)
    }

    /// "3 pages sent to Office PC."
    public static func sentMessage(_ pageCount: Int, desktopName: String) -> String {
        L10n.plural(pageCount, one: "{0} page sent to {1}.", other: "{0} pages sent to {1}.", desktopName)
    }

    /// "Scan 12.lsdoc was not sent: This document is too large to send in one piece."
    public static func notSentMessage(_ fileName: String, reason: String) -> String {
        L10n.t("{0} was not sent: {1}", fileName, reason)
    }

    /// "Put Scan 12 in the cloud folder for Office PC."
    public static func putInSyncFolderMessage(_ documentName: String, desktopName: String) -> String {
        L10n.t("Put {0} in the cloud folder for {1}.", documentName, desktopName)
    }

    /// "Put 3 documents in the cloud folder for Office PC."
    public static func putInSyncFolderMessage(count: Int, desktopName: String) -> String {
        L10n.plural(count, one: "Put {0} document in the cloud folder for {1}.", other: "Put {0} documents in the cloud folder for {1}.",
                    desktopName)
    }

    /// "Received Invoice.pdf from Office PC."
    public static func receivedMessage(_ fileName: String, desktopName: String) -> String {
        L10n.t("Received {0} from {1}.", fileName, desktopName)
    }

    /// "The computer refused the request (HTTP 501)."
    public static func refusedMessage(_ status: Int) -> String {
        L10n.t("The computer refused the request (HTTP {0}).", String(status))
    }
}

/// Where the link to the paired desktop stands.
public enum CompanionStatus: Equatable, Sendable {
    case notPaired
    /// A check or a pairing is under way, or the paired desktop has not been checked yet.
    case checking
    /// The desktop answered: its name and the pages in its queue.
    case reachable(desktopName: String, queuedPages: Int)
    /// The desktop did not answer, or refused: why, as a sentence.
    case unreachable(reason: String)
    /// The desktop named no longer knows this phone (it was removed there): pair again.
    case unpaired(byDesktop: String)
}

/// A companion status for a screen without a status line (`AppState.companionNotice`); each one is new, so the
/// same words twice still count.
public struct CompanionNotice: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let text: String
}

extension AppState {
    /// The desktop paired last; nil when there is none. The calls that take no desktop act on it.
    public var companionDesktop: PairedDesktop? {
        companionDesktops.first
    }

    /// Where the link stands overall: that of the desktop that answers, else one being checked, else one
    /// that does not answer, else one that no longer knows this phone; `.notPaired` without a desktop.
    public var companionStatus: CompanionStatus {
        let rank: (CompanionStatus) -> Int = { (status: CompanionStatus) -> Int in
            switch status {
            case .reachable: return 0
            case .checking: return 1
            case .unreachable: return 2
            case .unpaired: return 3
            case .notPaired: return 4
            }
        }
        let all: [CompanionStatus] = companionDesktops.compactMap { companionStatuses[$0.id] }
        return all.min { rank($0) < rank($1) } ?? .notPaired
    }

    /// Keeps the companion's files in `folder` (companion-desktop.json, the "Outbox" and "Inbox"
    /// folders; the iPhone's network folder, out of backups) and the device secret in `secrets` (the
    /// Keychain), and loads the paired desktops, `.checking` until `checkDesktop` runs; a package received
    /// before and not yet taken or dismissed is offered again. Set by the shell; without it the phone
    /// cannot pair.
    public func setUpCompanion(in folder: URL, secrets: any CompanionSecretStore) {
        stopPulling()
        let store = PairedDesktopStore(directory: folder, secrets: secrets)
        let outbox = PhoneOutbox(directory: folder.appendingPathComponent("Outbox", isDirectory: true))
        companionStore = store
        companionOutbox = outbox
        companionInbox = folder.appendingPathComponent("Inbox", isDirectory: true)
        companionClients = [:]
        companionDesktops = store.loadAll()
        companionStatuses = [:]
        for desktop in companionDesktops {
            companionStatuses[desktop.id] = store.secret(for: desktop) == nil ? .unpaired(byDesktop: desktop.name) : .checking
        }
        countOutbox()
        Task { [weak self] in
            await self?.offerReceivedPackage()
        }
    }

    /// Pairs with the desktop whose code is `uri` (scanned, or its text pasted), as `phoneName`. The
    /// desktop asks its user first, so this can take two minutes. The certificate that answers must be
    /// the one the code names. On success the desktop, its secret and its sync key (from a desktop that
    /// has the sync folder) are kept as the current desktop, beside the others paired before; pairing
    /// the same desktop again keeps its sync folder. A refusal is said in `errorMessage` with the desktop's own message, and the
    /// pairing kept before stays. True when the refusal used the code up (declined, expired, used or not a
    /// code the desktop issued), so only a new one can work.
    @discardableResult
    public func pairDesktop(uri: String, phoneName: String) async -> Bool {
        guard let store = companionStore else { return false }
        let code: PairingUri
        do {
            code = try PairingUri.parse(uri)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        var phoneId = companionDesktop?.phoneId ?? ""
        if !CompanionProtocol.isValidId(phoneId) { phoneId = PairedDesktop.makePhoneId() }
        var desktop = PairedDesktop(id: code.desktopId, name: code.name, fingerprint: code.fingerprint,
                                    addresses: code.addresses, port: code.port, phoneId: phoneId)
        guard !desktop.addresses.isEmpty else {
            errorMessage = CompanionText.notOnNetworkReason(code.name)
            return false
        }
        #if os(iOS)
        let platform = "ios"
        #else
        let platform = "macos"
        #endif
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let client = CompanionClient(desktop: desktop, secret: nil, protocolClasses: companionProtocolClasses)
        do {
            let response = try await client.pair(token: code.token, phoneId: phoneId, phoneName: phoneName,
                                                 platform: platform, appVersion: version)
            guard let secret = CompanionProtocol.decodeBase64Url(response.deviceSecret) else {
                throw CompanionClientError.badResponse
            }
            desktop.id = response.desktopId
            if !response.desktopName.isEmpty { desktop.name = response.desktopName }
            desktop.pairedAt = Date()
            desktop.lastSeen = desktop.pairedAt
            if let before = store.loadAll().first(where: { $0.id == desktop.id }) {
                desktop.received = before.received
                desktop.syncFolderBookmark = before.syncFolderBookmark
            }
            let syncKey = CompanionProtocol.decodeBase64Url(response.syncKey)
            try store.save(desktop, secret: secret, syncKey: syncKey?.count == SyncPackage.keyByteCount ? syncKey : nil)
        } catch {
            if case .unreachable? = error as? CompanionClientError {
                errorMessage = companionUnreachableReason(desktop)
            } else {
                errorMessage = error.localizedDescription
            }
            return Self.usesUpCode(error)
        }
        stopPulling(of: desktop.id)
        companionDesktops = [desktop] + companionDesktops.filter { $0.id != desktop.id }
        countOutbox()
        companionClients[desktop.id] = client
        companionStatuses[desktop.id] = .reachable(desktopName: desktop.name, queuedPages: 0)
        statusMessage = CompanionText.pairedMessage(desktop.name)
        return false
    }

    /// The pairing text of the desktop at `addresses` and `port` for the short code it shows (the
    /// computers nearby list's way to a pairing code); throws the desktop's refusal or why it was not
    /// reached. Nothing is kept: `pairDesktop` takes it from here, as after a scan.
    public func fetchPairingText(code: String, addresses: [String], port: Int) async throws -> String {
        let desktop = PairedDesktop(id: "", name: "", fingerprint: "", addresses: addresses, port: port, phoneId: "")
        let client = CompanionClient(desktop: desktop, secret: nil, protocolClasses: companionProtocolClasses, pinned: false)
        return try await client.pairingText(code: code)
    }

    private static func usesUpCode(_ error: Error) -> Bool {
        guard case .refused(_, let refusal)? = error as? CompanionClientError else { return false }
        let spent = [CompanionErrorCode.declined, CompanionErrorCode.tokenExpired,
                     CompanionErrorCode.tokenUsed, CompanionErrorCode.tokenInvalid]
        return spent.contains(refusal.code)
    }

    /// Tells `desktop` (the one paired last when nil) to forget this phone (best effort: it may be off),
    /// then forgets it and its secret; the other desktops stay paired. Documents waiting to be sent stay,
    /// for that desktop only.
    public func unpairDesktop(_ desktop: PairedDesktop? = nil) async {
        guard let desktop = desktop ?? companionDesktop else { return }
        stopPulling(of: desktop.id)
        if let client = desktopClient(for: desktop) {
            try? await client.unpair()
        }
        companionStore?.remove(desktop)
        companionClients[desktop.id] = nil
        companionStatuses[desktop.id] = nil
        companionDesktops = companionDesktops.filter { $0.id != desktop.id }
        countOutbox()
        statusMessage = CompanionText.unpairedMessage(desktop.name)
    }

    /// Checks every paired desktop (`checkDesktop(_:)`) at once.
    public func checkDesktop() async {
        let desktops = companionDesktops
        await withTaskGroup(of: Void.self) { group in
            for desktop in desktops {
                group.addTask { @MainActor in await self.checkDesktop(desktop) }
            }
        }
    }

    /// Checks every paired desktop and gives those that answered, in the paired order.
    public func answeringDesktops() async -> [PairedDesktop] {
        await checkDesktop()
        return companionDesktops.filter {
            if case .reachable? = companionStatuses[$0.id] { return true }
            return false
        }
    }

    /// The paired desktops that did not answer the last check.
    public var unreachableDesktops: [PairedDesktop] {
        companionDesktops.filter {
            if case .unreachable? = companionStatuses[$0.id] { return true }
            return false
        }
    }

    /// The desktop a document goes to when none was picked and none answers: the one seen last, else the
    /// one paired last, among those that still have their secret.
    public var likelyDesktop: PairedDesktop? {
        companionDesktops.filter { companionStore?.secret(for: $0) != nil }
            .max { ($0.lastSeen ?? .distantPast) < ($1.lastSeen ?? .distantPast) }
    }

    /// Asks `desktop` how it is (`hello`) at its addresses: `.reachable` with its queue, keeping the
    /// name it gives now; a desktop that no longer knows this phone (401) loses its secret here and is
    /// `.unpaired`; one that does not answer is `.unreachable` with the reason
    /// (`companionUnreachableReason`), everything kept.
    public func checkDesktop(_ desktop: PairedDesktop) async {
        guard let client = desktopClient(for: desktop) else {
            companionStatuses[desktop.id] = .unpaired(byDesktop: desktop.name)
            return
        }
        let before = companionStatuses[desktop.id]
        companionStatuses[desktop.id] = .checking
        do {
            let hello = try await client.hello()
            // Unpaired or found at new addresses meanwhile: only what the answer says is kept.
            guard var current = pairedDesktop(desktop.id) else { return }
            if !hello.desktopName.isEmpty { current.name = hello.desktopName }
            current.lastSeen = Date()
            keep(current)
            companionStatuses[desktop.id] = .reachable(desktopName: current.name, queuedPages: hello.queuedPages)
        } catch is CancellationError {
            companionStatuses[desktop.id] = before
        } catch {
            companionFailed(error, desktop)
        }
    }

    /// Writes the queue as a `.lsdoc` (`exportPackage`) into the outbox for `desktop` (`likelyDesktop` when
    /// nil) and sends what waits there for it (`drainOutbox`); the queue is not touched. A document that
    /// cannot be sent now waits in the outbox for the next time. A cancelled send stops quietly. True when
    /// the document this send queued is still in the outbox.
    @discardableResult
    public func sendQueueToDesktop(target: CompanionTarget, to desktop: PairedDesktop? = nil) async -> Bool {
        guard let outbox = companionOutbox, let desktop = desktop ?? likelyDesktop,
              desktopClient(for: desktop) != nil else {
            errorMessage = CompanionText.notPairedMessage
            return false
        }
        guard outbox.count < PhoneOutbox.maxItems else {
            errorMessage = CompanionText.outboxFullMessage
            return false
        }
        let queued: PhoneOutboxItem
        do {
            try FileManager.default.createDirectoryCompleteUnlessOpen(at: outbox.directory)
            let url = try await exportPackage(to: outbox.directory)
            if Task.isCancelled {
                try? FileManager.default.removeItem(at: url)
                return false
            }
            queued = try outbox.enqueue(url, target: target, desktopId: desktop.id)
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        countOutbox()
        let noticeBefore = companionNotice
        await drainOutbox(for: desktop)
        if settings.output.protect, errorMessage == nil, !Task.isCancelled, companionNotice != noticeBefore {
            statusMessage += " " + Self.noPasswordNote
            companionNotice = CompanionNotice(text: statusMessage)
        }
        return outbox.items.contains { $0.id == queued.id }
    }

    /// Sends the documents waiting in the outbox for `target` (each paired desktop in turn when nil) one
    /// by one, oldest first (those queued for a desktop no longer paired wait for it), each removed once
    /// the desktop has it (a duplicate counts: it had it already). One the desktop refuses (too large, not readable) stays, said in
    /// `errorMessage` once and never tried again, and the next is sent; when the desktop is busy or no longer knows this phone, the
    /// rest wait. When it does not answer, the rest go through the sync folder if the desktop handed out
    /// a sync key and a folder is set (`sendThroughSyncFolder`), except those it refused as too large or
    /// not readable (another error status sends the next too, but keeps the folder open); with a key but no
    /// folder, the status says once this session where to set one. One that failed to go into the folder
    /// before tries the folder first. One in the folder leaves once its file has left it (the desktop took
    /// it), or once it is sent over the network, its file then taken out of the folder. "3 pages sent to
    /// Office PC."
    public func drainOutbox(for target: PairedDesktop? = nil) async {
        guard companionOutbox != nil else { return }
        defer { countOutbox() }
        for desktop in target.map({ [$0] }) ?? companionDesktops {
            if Task.isCancelled { return }
            guard companionDrainingIds.insert(desktop.id).inserted else { continue }
            defer { companionDrainingIds.remove(desktop.id) }
            await drain(desktop)
        }
    }

    private func drain(_ desktop: PairedDesktop) async {
        guard let outbox = companionOutbox, let client = desktopClient(for: desktop) else { return }
        var tried: Set<String> = []
        var pages = 0
        while let item = outbox.next(excluding: tried) {
            tried.insert(item.id)
            guard item.desktopId == desktop.id else { continue }
            if item.inSyncFolder, let folder = openSyncFolder(for: desktop), !syncFolder(folder, holds: item.id) {
                outbox.markSent(item.id)
                countOutbox()
                continue
            }
            if item.viaSyncFolder, sendThroughSyncFolder(itemId: item.id) { continue }
            let data: Data
            do {
                data = try Data(contentsOf: outbox.fileURL(of: item), options: .mappedIfSafe)
            } catch {
                if FileManager.default.fileExists(atPath: outbox.fileURL(of: item).path) {
                    outbox.markFailed(item.id, error: error.localizedDescription)
                } else {
                    outbox.remove(item.id)
                }
                continue
            }
            do {
                let response = try await client.send(packageId: item.id, data: data, target: item.target)
                if item.inSyncFolder, let folder = openSyncFolder(for: desktop) {
                    try? AppState.coordinateWriting(folder.appendingPathComponent(SyncPackage.fileName(item.id)),
                                                    options: .forDeleting) { try FileManager.default.removeItem(at: $0) }
                }
                outbox.markSent(item.id)
                pages += response.pageCount
                countOutbox()
            } catch is CancellationError {
                return
            } catch {
                outbox.markFailed(item.id, error: error.localizedDescription)
                switch error as? CompanionClientError {
                case .tooLarge?, .invalidPackage?:
                    outbox.markRefused(item.id)
                    errorMessage = CompanionText.notSentMessage(item.fileName, reason: error.localizedDescription)
                    continue
                case .refused?:
                    // Not about the document itself (a 500, say): it may still go through the folder.
                    errorMessage = CompanionText.notSentMessage(item.fileName, reason: error.localizedDescription)
                    continue
                case .unreachable?:
                    companionFailed(error, desktop)
                    statusMessage = CompanionText.cannotReachMessage(desktop.name)
                    putInSyncFolder(for: desktop)
                default:
                    companionFailed(error, desktop)
                    statusMessage = error.localizedDescription
                }
                return
            }
        }
        if pages > 0 {
            statusMessage = CompanionText.sentMessage(pages, desktopName: desktop.name)
            companionNotice = CompanionNotice(text: statusMessage)
            if !Task.isCancelled { await checkDesktop(desktop) }
        }
    }

    /// The desktop paired last handed out a sync key, so documents can go through a cloud sync folder.
    public var canUseSyncFolder: Bool {
        guard let desktop = companionDesktop else { return false }
        return canUseSyncFolder(for: desktop)
    }

    /// `desktop` handed out a sync key.
    public func canUseSyncFolder(for desktop: PairedDesktop) -> Bool {
        companionStore?.syncKey(for: desktop) != nil
    }

    /// The documents waiting in the outbox for a paired desktop that are in the sync folder, for the desktop
    /// to take from there.
    public var companionInSyncFolderCount: Int {
        companionOutbox?.items.filter { $0.inSyncFolder && isForPairedDesktop($0) }.count ?? 0
    }

    /// Keeps `bookmark` (made by the shell of the folder picked in My computer, in iCloud Drive or
    /// OneDrive) as the sync folder of `desktop` (the one paired last when nil); nil forgets it. The
    /// desktop watches the same folder. Documents put in the folder set before go again, into this one or
    /// over the network.
    public func setSyncFolder(bookmark: Data?, for desktop: PairedDesktop? = nil) {
        guard var desktop = (desktop ?? companionDesktop).flatMap({ pairedDesktop($0.id) }) else { return }
        if bookmark != desktop.syncFolderBookmark, let outbox = companionOutbox {
            for item in outbox.items where item.desktopId == desktop.id && item.inSyncFolder {
                outbox.markInSyncFolder(item.id, false)
            }
            countOutbox()
        }
        desktop.syncFolderBookmark = bookmark
        keep(desktop)
    }

    /// The sync folder of `desktop` (the one paired last when nil), opened through
    /// `resolveSyncFolderBookmark`, its bookmark brought up to date; nil without a folder or a resolver, or
    /// when it does not resolve now (the bookmark is kept).
    public func openSyncFolder(for desktop: PairedDesktop? = nil) -> URL? {
        guard var desktop = (desktop ?? companionDesktop).flatMap({ pairedDesktop($0.id) }),
              let bookmark = desktop.syncFolderBookmark,
              let resolve = resolveSyncFolderBookmark, let resolved = resolve(bookmark) else { return nil }
        if resolved.bookmark != bookmark {
            desktop.syncFolderBookmark = resolved.bookmark
            keep(desktop)
        }
        return resolved.folder
    }

    /// Seals the waiting document `itemId` with its desktop's sync key (`SyncPackage`) and puts it
    /// in the sync folder as "<id>.lssync", written whole in a coordinated write, so the provider (iCloud
    /// Drive, OneDrive) takes it as a new file and the desktop never takes half of it; it stays in the
    /// outbox, marked in the folder, until the desktop has it (`drainOutbox`). False when it is not for a
    /// paired desktop, the desktop refused it, it is in the folder already, or there is no key or folder;
    /// a folder that does not open or a write that fails is said in `errorMessage`, and the document waits,
    /// to try the folder first the next time (one too large to seal counts as refused). "Put Scan 12 in the
    /// cloud folder for Office PC."
    @discardableResult
    public func sendThroughSyncFolder(itemId: String) -> Bool {
        guard let outbox = companionOutbox, let item = outbox.items.first(where: { $0.id == itemId }),
              let desktop = pairedDesktop(item.desktopId), !item.refused, !item.inSyncFolder,
              let key = companionStore?.syncKey(for: desktop), desktop.syncFolderBookmark != nil else { return false }
        guard let folder = openSyncFolder(for: desktop) else {
            outbox.markViaSyncFolder(item.id)
            errorMessage = CompanionText.syncFolderUnavailableMessage
            return false
        }
        do {
            let data = try Data(contentsOf: outbox.fileURL(of: item), options: .mappedIfSafe)
            let sealed = try SyncPackage.seal(packageId: item.id, phoneId: desktop.phoneId, target: item.target,
                                              plaintext: data, key: key)
            try AppState.coordinateWriting(folder.appendingPathComponent(SyncPackage.fileName(item.id)),
                                           options: .forReplacing) { try sealed.write(to: $0, options: .atomic) }
        } catch {
            outbox.markFailed(item.id, error: error.localizedDescription)
            // The desktop refuses it over the network too: the same limit.
            if (error as? SyncPackageError) == .tooLarge {
                outbox.markRefused(item.id)
            } else {
                outbox.markViaSyncFolder(item.id)
            }
            errorMessage = CompanionText.notSentMessage(item.fileName, reason: error.localizedDescription)
            return false
        }
        outbox.markInSyncFolder(item.id)
        let name = URL(fileURLWithPath: item.fileName).deletingPathExtension().lastPathComponent
        statusMessage = CompanionText.putInSyncFolderMessage(name, desktopName: desktop.name)
        companionNotice = CompanionNotice(text: statusMessage)
        return true
    }

    /// Starts taking what each paired desktop holds for this phone: a long poll (`outbox(wait: 25)`) for
    /// each, for as long as it runs. A `.lsdoc` is downloaded into the inbox folder and offered on the banner as one opened
    /// by hand (`openPackage(at:)`) once nothing else is offered, its file kept until it is taken or
    /// dismissed (`offerReceivedPackage`); any other file goes to the save folder and is said. Each is
    /// acknowledged once written, so the desktop drops it, and its id kept (`PairedDesktop.received`):
    /// one listed again is acknowledged again, never saved twice. A desktop that no longer knows this
    /// phone stops it (`.unpaired`); other failures wait 5 s, then 30 s each, and try again. Nothing
    /// while it runs.
    public func pullFromDesktop() {
        guard companionInbox != nil else { return }
        for desktop in companionDesktops where companionPulls[desktop.id] == nil {
            companionPulls[desktop.id] = Task { [weak self] in
                await self?.pullLoop(desktop.id)
            }
        }
    }

    public func stopPulling() {
        for pull in companionPulls.values { pull.cancel() }
        companionPulls = [:]
    }

    func stopPulling(of desktopId: String) {
        companionPulls[desktopId]?.cancel()
        companionPulls[desktopId] = nil
    }

    /// Removes the documents waiting to be sent to the paired desktops (all of them while none is paired),
    /// unsent.
    public func clearOutbox() {
        guard let outbox = companionOutbox else { return }
        for item in outbox.items where isForPairedDesktop(item) {
            outbox.remove(item.id)
        }
        countOutbox()
    }

    /// Removes one waiting document, unsent.
    public func removeWaiting(id: String) {
        companionOutbox?.remove(id)
        countOutbox()
    }

    /// Removes the documents waiting for a desktop no longer paired while others are, unsent.
    public func clearOtherOutbox() {
        guard let outbox = companionOutbox else { return }
        for item in outbox.items where !isForPairedDesktop(item) {
            outbox.remove(item.id)
        }
        countOutbox()
    }

    /// The desktop with this id was found on the network (its DNS-SD service, TXT `id`) at `addresses`
    /// and `port`. When that is a paired desktop and they differ from the ones kept (a new DHCP
    /// lease), they replace them, IPv4 first, once the pinned certificate answers there, since anyone
    /// can advertise that id; the next request looks for its address anew. Returns whether they did.
    @discardableResult
    public func desktopFound(id: String, addresses: [String], port: Int) async -> Bool {
        guard let desktop = pairedDesktop(id), (1...65535).contains(port) else { return false }
        var ipv4: [String] = []
        var ipv6: [String] = []
        for address in addresses where PairingUri.isValidAddress(address) && !ipv4.contains(address)
            && !ipv6.contains(address) {
            if address.contains(":") {
                ipv6.append(address)
            } else {
                ipv4.append(address)
            }
        }
        let found = Array((ipv4 + ipv6).prefix(PairingUri.maxAddresses))
        guard !found.isEmpty, Set(found) != Set(desktop.addresses) || port != desktop.port else { return false }
        var moved = desktop
        moved.addresses = found
        moved.port = port
        let probe = CompanionClient(desktop: moved, secret: nil, protocolClasses: companionProtocolClasses)
        guard (try? await probe.health()) != nil, var current = pairedDesktop(id) else { return false }
        current.addresses = found
        current.port = port
        keep(current)
        companionClients[id] = nil
        return true
    }

    /// Offers the oldest package received from the desktop and still in the inbox folder on the banner,
    /// unless a package is offered already; one that cannot be read is said and removed.
    func offerReceivedPackage() async {
        guard pendingPackage == nil, let folder = companionInbox else { return }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)) ?? []
        var oldest: URL?
        var oldestDate = Date.distantFuture
        for file in files where file.pathExtension.lowercased() == CompanionPackage.fileExtension {
            let created = (try? file.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            if created < oldestDate {
                oldest = file
                oldestDate = created
            }
        }
        guard let url = oldest else { return }
        let opening = packageOpens + 1
        await openPackage(at: url)
        // Nothing offered and nothing else opened meanwhile: the read failed, and would again.
        if pendingPackage == nil, packageOpens == opening {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// The offered `package` was taken or dismissed: one received from the desktop leaves the inbox
    /// folder, and the next one received is offered.
    func receivedPackageAnswered(_ package: PendingPackage) {
        guard let folder = companionInbox else { return }
        let from = package.url.deletingLastPathComponent().resolvingSymlinksInPath()
        if from.path == folder.resolvingSymlinksInPath().path {
            try? FileManager.default.removeItem(at: package.url)
        }
        Task { [weak self] in
            await self?.offerReceivedPackage()
        }
    }

    /// Why the paired desktop does not answer: Local Network access is off (`companionAccessDenied`); else
    /// the desktop is seen on the network (`companionDesktopSeenOnNetwork`) and refuses the connection,
    /// and then the cloud folder is used when one is set for a desktop that handed out a sync key; else
    /// it is not on this network.
    func companionUnreachableReason(_ desktop: PairedDesktop) -> String {
        if companionAccessDenied?() == true {
            return CompanionText.localNetworkOffReason
        }
        guard companionDesktopSeenOnNetwork?(desktop.id) == true else {
            return CompanionText.notOnNetworkReason(desktop.name)
        }
        if desktop.syncFolderBookmark != nil, companionStore?.syncKey(for: desktop) != nil {
            return CompanionText.refusedSyncFolderReason
        }
        return CompanionText.refusedReason
    }

    // MARK: - Private

    /// The desktop paired with that has this id, as kept now.
    private func pairedDesktop(_ id: String) -> PairedDesktop? {
        companionDesktops.first { $0.id == id }
    }

    /// Writes what changed about a paired desktop, and keeps it in the list in its place.
    private func keep(_ desktop: PairedDesktop) {
        companionStore?.update(desktop)
        guard let index = companionDesktops.firstIndex(where: { $0.id == desktop.id }) else { return }
        companionDesktops[index] = desktop
    }

    /// The client of `desktop`, made with its secret the first time; nil without one.
    private func desktopClient(for desktop: PairedDesktop) -> CompanionClient? {
        if let client = companionClients[desktop.id] { return client }
        guard let current = pairedDesktop(desktop.id), let secret = companionStore?.secret(for: current) else { return nil }
        let client = CompanionClient(desktop: current, secret: secret, protocolClasses: companionProtocolClasses)
        companionClients[desktop.id] = client
        return client
    }

    /// Whether `item` waits for a paired desktop; while none is paired, every one does.
    private func isForPairedDesktop(_ item: PhoneOutboxItem) -> Bool {
        companionDesktops.isEmpty || companionDesktops.contains { $0.id == item.desktopId }
    }

    /// Counts what waits in the outbox for the paired desktops, and apart what waits for another.
    private func countOutbox() {
        let items = companionOutbox?.items ?? []
        let waiting = items.filter { isForPairedDesktop($0) }
        companionWaiting = waiting
        companionOutboxCount = waiting.count
        companionOtherOutboxCount = items.count - waiting.count
    }

    /// `desktop` did not answer: what waits for it goes through the sync folder when it handed out a sync
    /// key and a folder is set; with a key but no folder, the status says where to set one, once.
    private func putInSyncFolder(for desktop: PairedDesktop) {
        guard let outbox = companionOutbox, companionStore?.syncKey(for: desktop) != nil else { return }
        guard pairedDesktop(desktop.id)?.syncFolderBookmark != nil else {
            if !companionSyncFolderHinted {
                companionSyncFolderHinted = true
                statusMessage = CompanionText.cannotReachMessage(desktop.name) + " " + CompanionText.syncFolderHint
            }
            return
        }
        var put = 0
        for item in outbox.items where item.desktopId == desktop.id && !item.inSyncFolder && !item.refused {
            if sendThroughSyncFolder(itemId: item.id) {
                put += 1
            } else if openSyncFolder(for: desktop) == nil {
                break
            }
        }
        if put > 1 {
            statusMessage = CompanionText.putInSyncFolderMessage(count: put, desktopName: desktop.name)
            companionNotice = CompanionNotice(text: statusMessage)
        }
    }

    /// Whether `id`'s file is still in the sync folder `folder` (an iCloud file moved off the phone shows
    /// as ".<name>.icloud"); a folder that cannot be listed holds it.
    private func syncFolder(_ folder: URL, holds id: String) -> Bool {
        let name = SyncPackage.fileName(id)
        var holds = true
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: folder, options: .immediatelyAvailableMetadataOnly,
                                                         error: &coordinationError) { listed in
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: listed.path) else { return }
            holds = names.contains(name) || names.contains("." + name + ".icloud")
        }
        return holds
    }

    /// Runs `body` on `url` in a coordinated write, so the provider of a folder picked in Files learns of
    /// the change (an uncoordinated one may never be uploaded).
    nonisolated static func coordinateWriting(_ url: URL, options: NSFileCoordinator.WritingOptions,
                                              _ body: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var failure: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: options,
                                                         error: &coordinationError) { file in
            do {
                try body(file)
            } catch {
                failure = error
            }
        }
        if let failure = failure { throw failure }
        if let coordinationError = coordinationError { throw coordinationError }
    }

    /// What a failed request means for the link.
    private func companionFailed(_ error: Error, _ desktop: PairedDesktop) {
        // Unpaired while the request ran.
        guard pairedDesktop(desktop.id) != nil else { return }
        switch error as? CompanionClientError {
        case .unauthorized?:
            stopPulling(of: desktop.id)
            companionStore?.forgetSecret(of: desktop)
            companionClients[desktop.id] = nil
            companionStatuses[desktop.id] = .unpaired(byDesktop: desktop.name)
        case .unreachable?:
            companionStatuses[desktop.id] = .unreachable(reason: companionUnreachableReason(desktop))
        default:
            companionStatuses[desktop.id] = .unreachable(reason: error.localizedDescription)
        }
    }

    private func pullLoop(_ desktopId: String) async {
        var failures = 0
        while !Task.isCancelled, let desktop = pairedDesktop(desktopId), let client = desktopClient(for: desktop) {
            var wait: TimeInterval = 0
            do {
                let list = try await client.outbox(wait: CompanionProtocol.maxOutboxWaitSeconds)
                for item in list.items {
                    try Task.checkCancellation()
                    try await receive(item, from: client, desktop: desktop)
                }
                let recovered = failures > 0
                failures = 0
                if recovered {
                    await checkDesktop(desktop)
                    await drainOutbox(for: desktop)
                }
            } catch is CancellationError {
                return
            } catch {
                switch error as? CompanionClientError {
                case .unauthorized?:
                    companionFailed(error, desktop)
                    return
                case .rateLimited(let seconds)?:
                    wait = TimeInterval(seconds)
                default:
                    wait = failures == 0 ? 5 : 30
                }
                failures += 1
            }
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
        if !Task.isCancelled { companionPulls[desktopId] = nil }
    }

    /// Downloads one document the desktop holds, keeps it (a package in the inbox folder until it is
    /// answered, any other file in the save folder), notes its id and acknowledges it, then offers or
    /// says it. One received before is only acknowledged again.
    private func receive(_ item: OutboxItem, from client: CompanionClient, desktop: PairedDesktop) async throws {
        if pairedDesktop(desktop.id)?.received.contains(item.id) == true {
            try await acknowledge(item.id, from: client)
            return
        }
        let data = try await client.outboxItem(id: item.id)
        guard let inbox = companionInbox else { return }
        let packageExtension = CompanionPackage.fileExtension
        let isPackage = item.contentType == CompanionProtocol.packageContentType
            || item.name.lowercased().hasSuffix("." + packageExtension)
        let folder = try isPackage ? inbox : destinationDirectory()
        var name = PairedDeviceStore.cleanName(item.name)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        if name.isEmpty || name.hasPrefix(".") { name = item.id + name }
        let named = URL(fileURLWithPath: name)
        var fileExtension = isPackage ? packageExtension : named.pathExtension
        if fileExtension.isEmpty { fileExtension = "bin" }
        let url = NamingTemplate.uniqueURL(in: folder, base: named.deletingPathExtension().lastPathComponent,
                                           fileExtension: fileExtension)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        if var current = pairedDesktop(desktop.id) {
            current.noteReceived(item.id)
            keep(current)
        }
        // Acknowledged before the offer, which decodes every picture: the file is kept already.
        var failure: Error?
        do {
            try await acknowledge(item.id, from: client)
        } catch {
            failure = error
        }
        if isPackage {
            await offerReceivedPackage()
        } else {
            statusMessage = CompanionText.receivedMessage(url.lastPathComponent, desktopName: desktop.name)
            companionNotice = CompanionNotice(text: statusMessage)
        }
        if let failure = failure { throw failure }
    }

    /// Tells the desktop the phone has the item.
    private func acknowledge(_ id: String, from client: CompanionClient) async throws {
        do {
            try await client.ack(id: id)
        } catch CompanionClientError.refused(let status, _) where status == 404 {
            // Gone already (acknowledged before, or expired on the desktop).
        }
    }
}
