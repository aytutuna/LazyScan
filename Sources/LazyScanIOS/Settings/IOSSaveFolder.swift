#if os(iOS)
import LazyScanKit
import Foundation

/// Whether iCloud Drive can hold the scans right now (`IOSSaveFolder.iCloudState()`).
public enum ICloudState {
    /// The Documents folder of the app's container.
    case ready(URL)
    /// Signed out of iCloud or iCloud Drive is off.
    case off
    /// Signed in, but no container came back.
    case unavailable
}

/// A save folder outside the app (iCloud Drive, a USB drive) picked in Options. iOS lets the app back into
/// such a folder only through a bookmark (`ScanSettings.destinationBookmark`); its path is kept too, so what
/// reads `destinationPath` works on. The folder is opened once and kept open while the app runs, since it is
/// written to again and again (`AppState.resolveDestinationBookmark`, set by `makeForIOS`).
@MainActor
public enum IOSSaveFolder {
    private static let kept: IOSBookmarkedFolder = IOSBookmarkedFolder()
    private static let containerID: String = "iCloud.com.lazyscan.lazyscan"
    /// The folder name iOS gives the container under Mobile Documents.
    private static let containerFolder: String = "iCloud~com~lazyscan~lazyscan"

    /// The Documents folder of the app's iCloud container, which Files shows as iCloud Drive > Lazy Scan.
    /// `url(forUbiquityContainerIdentifier:)` can block, so it runs off the main actor.
    public static func iCloudState() async -> ICloudState {
        guard FileManager.default.ubiquityIdentityToken != nil else { return .off }
        let id: String = containerID
        let documents: URL? = await Task.detached { () -> URL? in
            guard let container = FileManager.default.url(forUbiquityContainerIdentifier: id) else { return nil }
            return container.appendingPathComponent("Documents", isDirectory: true)
        }.value
        guard let documents else { return .unavailable }
        return .ready(documents)
    }

    /// Whether `settings` save into the iCloud container: a bookmark to its Documents folder.
    public static func usesICloud(_ settings: ScanSettings) -> Bool {
        settings.destinationBookmark != nil && settings.destinationPath.hasSuffix("/" + containerFolder + "/Documents")
    }

    /// `settings` saving to `folder`, picked in Files; throws when no bookmark can be made of it. The folder
    /// is opened by `AppState.openBookmarkedFolder()`.
    public static func choosing(_ folder: URL, in settings: ScanSettings) throws -> ScanSettings {
        var changed: ScanSettings = settings
        changed.destinationBookmark = try IOSBookmarkedFolder.bookmark(of: folder)
        changed.destinationPath = folder.path
        return changed
    }

    /// `settings` saving to the app's own folder again; the folder picked before is closed.
    public static func appFolder(_ settings: ScanSettings) -> ScanSettings {
        kept.close()
        var changed: ScanSettings = settings
        changed.destinationBookmark = nil
        changed.destinationPath = ScanSettings.defaultDestinationPath
        return changed
    }

    /// The folder `bookmark` stands for, opened, and the bookmark to keep (made again when iOS says it is
    /// stale); nil when it does not resolve. The folder kept open is resolved again once it is out of reach.
    public static func resolve(_ bookmark: Data) -> (folder: URL, bookmark: Data)? {
        guard let resolved = kept.resolve(bookmark) else { return nil }
        // With iCloud off the container's path may still resolve, but a save there would only make a local folder.
        if FileManager.default.ubiquityIdentityToken == nil, resolved.folder.path.contains("/" + containerFolder + "/") {
            kept.close()
            return nil
        }
        return resolved
    }
}

/// A folder outside the app opened through its bookmark and kept open while the app runs: the save folder
/// (`IOSSaveFolder`) and the cloud folder of My computer (`IOSSyncFolder`) each have one.
@MainActor
final class IOSBookmarkedFolder {
    /// The folder open now and the bookmark it was opened with.
    private var opened: (folder: URL, bookmark: Data)?
    /// The folder whose security-scoped access was started, stopped when another is opened.
    private var accessed: URL?

    nonisolated init() {}

    /// The bookmark of `folder`, picked in Files; throws when none can be made of it.
    static func bookmark(of folder: URL) throws -> Data {
        let started: Bool = folder.startAccessingSecurityScopedResource()
        defer {
            if started { folder.stopAccessingSecurityScopedResource() }
        }
        return try folder.bookmarkData()
    }

    func resolve(_ bookmark: Data) -> (folder: URL, bookmark: Data)? {
        if let current = opened, current.bookmark == bookmark,
           (try? current.folder.checkResourceIsReachable()) == true {
            return current
        }
        var stale: Bool = false
        guard let folder = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil,
                                    bookmarkDataIsStale: &stale) else {
            close()
            return nil
        }
        // A folder deleted in Files may still resolve from the Trash of its drive; it is treated as out of reach and its
        // bookmark kept.
        if folder.pathComponents.contains(where: { $0 == ".Trash" || $0 == ".Trashes" }) {
            close()
            return nil
        }
        if opened?.folder != folder {
            close()
            if folder.startAccessingSecurityScopedResource() {
                accessed = folder
            }
        }
        var kept: Data = bookmark
        if stale, let fresh = try? folder.bookmarkData() {
            kept = fresh
        }
        opened = (folder: folder, bookmark: kept)
        return (folder: folder, bookmark: kept)
    }

    func close() {
        accessed?.stopAccessingSecurityScopedResource()
        accessed = nil
        opened = nil
    }
}
#endif
