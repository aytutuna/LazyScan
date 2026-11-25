import Foundation

/// Where the phone keeps the device secret each desktop gave it: the iPhone's Keychain, so a backup
/// or a copy of the app's files does not carry it. The desktop's sync key for the cloud sync folder
/// is kept there too, under "<desktopId>.sync". On the desktop the same store keeps each phone's sync
/// key under the phone's id (`PairedDeviceStore`).
public protocol CompanionSecretStore: Sendable {
    func save(_ secret: Data, for desktopId: String) throws
    /// nil when there is none.
    func load(for desktopId: String) throws -> Data?
    func delete(for desktopId: String) throws
}

/// Why a pairing could not be kept.
public enum PairedDesktopStoreError: Error, Equatable, LocalizedError, Sendable {
    /// The file could not be written (a phone must not believe it is paired when it is not).
    case notSaved

    public var errorDescription: String? { CompanionText.notSavedMessage }
}

/// The desktops this phone is paired with: companion-desktop.json in the folder the shell gives (the
/// iPhone's network folder, kept out of backups), following the settings-file rules, and each one's secret and
/// sync key in the `CompanionSecretStore`. The file holds an array,
/// the newest pairing first; a file from before, holding one desktop, still loads and is written as an
/// array with the next change. Safe to use from any thread.
public final class PairedDesktopStore: @unchecked Sendable {
    public static let fileName = "companion-desktop.json"

    private let url: URL
    private let secrets: any CompanionSecretStore
    private let lock = NSLock()

    public init(directory: URL, secrets: any CompanionSecretStore) {
        url = directory.appendingPathComponent(PairedDesktopStore.fileName)
        self.secrets = secrets
    }

    /// The desktop paired last; nil when there is none, or the file cannot be read or names no usable
    /// desktop.
    public func load() -> PairedDesktop? {
        loadAll().first
    }

    /// Every paired desktop, the newest pairing first; those that name no usable desktop are left out.
    public func loadAll() -> [PairedDesktop] {
        lock.lock()
        defer { lock.unlock() }
        return readAll()
    }

    /// Keeps `desktop`, its `secret` and its `syncKey` (nil: it gave none, and one kept before goes), as
    /// the newest pairing; a desktop with the same id is replaced, the others stay. Throws when the
    /// desktop or its secret cannot be kept; nothing of the new pairing stays then. A sync key that
    /// cannot be kept only leaves the phone without the sync folder.
    public func save(_ desktop: PairedDesktop, secret: Data, syncKey: Data? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        let kept = readAll()
        try secrets.save(secret, for: desktop.id)
        guard StoreFiles.write([desktop] + kept.filter { $0.id != desktop.id }, to: url) else {
            if !kept.contains(where: { $0.id == desktop.id }) { try? secrets.delete(for: desktop.id) }
            throw PairedDesktopStoreError.notSaved
        }
        if let syncKey {
            try? secrets.save(syncKey, for: PairedDesktopStore.syncAccount(desktop.id))
        } else {
            try? secrets.delete(for: PairedDesktopStore.syncAccount(desktop.id))
        }
    }

    /// Writes what changed about the desktop (its name, when it was last seen); best effort. A desktop
    /// that is no longer paired stays gone.
    public func update(_ desktop: PairedDesktop) {
        lock.lock()
        defer { lock.unlock() }
        var all = readAll()
        guard let index = all.firstIndex(where: { $0.id == desktop.id }) else { return }
        all[index] = desktop
        StoreFiles.write(all, to: url)
    }

    /// The secret of `desktop`; nil when there is none or it cannot be read.
    public func secret(for desktop: PairedDesktop) -> Data? {
        guard let secret = try? secrets.load(for: desktop.id), secret.count == PairedDeviceStore.secretByteCount else {
            return nil
        }
        return secret
    }

    /// The sync key `desktop` gave for the cloud sync folder; nil when it gave none or it cannot be read.
    public func syncKey(for desktop: PairedDesktop) -> Data? {
        guard let key = try? secrets.load(for: PairedDesktopStore.syncAccount(desktop.id)),
              key.count == SyncPackage.keyByteCount else { return nil }
        return key
    }

    /// Drops the secret and sync key of `desktop` (the desktop no longer knows this phone); the desktop
    /// stays, so the app can say which one to pair with again.
    public func forgetSecret(of desktop: PairedDesktop) {
        try? secrets.delete(for: desktop.id)
        try? secrets.delete(for: PairedDesktopStore.syncAccount(desktop.id))
    }

    /// Forgets `desktop`, its secret and its sync key; the other desktops stay.
    public func remove(_ desktop: PairedDesktop) {
        lock.lock()
        defer { lock.unlock() }
        try? secrets.delete(for: desktop.id)
        try? secrets.delete(for: PairedDesktopStore.syncAccount(desktop.id))
        let all = readAll()
        let rest = all.filter { $0.id != desktop.id }
        guard rest.count < all.count else { return }
        if rest.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else {
            StoreFiles.write(rest, to: url)
        }
    }

    /// Forgets every paired desktop, with their secrets and sync keys.
    public func remove() {
        lock.lock()
        defer { lock.unlock() }
        for desktop in readAll() {
            try? secrets.delete(for: desktop.id)
            try? secrets.delete(for: PairedDesktopStore.syncAccount(desktop.id))
        }
        try? FileManager.default.removeItem(at: url)
    }

    /// The file's usable desktops. The caller holds the lock. A file written before holds one desktop
    /// as an object; reading it as an array fails without side effects, so it is tried first.
    private func readAll() -> [PairedDesktop] {
        let found: [PairedDesktop]
        if case .loaded(let single) = StoreFiles.read(PairedDesktop.self, from: url) {
            found = [single]
        } else {
            found = StoreFiles.load([PairedDesktop].self, from: url) ?? []
        }
        return found.filter {
            CompanionProtocol.isValidId($0.id) && CompanionProtocol.isValidId($0.phoneId)
                && $0.fingerprintBytes != nil && !$0.addresses.isEmpty
        }
    }

    /// The `CompanionSecretStore` account the sync key of the desktop `id` is kept under.
    static func syncAccount(_ id: String) -> String {
        id + ".sync"
    }
}
