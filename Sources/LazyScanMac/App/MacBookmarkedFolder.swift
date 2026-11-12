#if os(macOS)
import Foundation
import LazyScanKit

/// A folder the user picked, kept as a security-scoped bookmark: a sandboxed app can open a folder it was granted once, but
/// only through the bookmark of it, not its path. The folder is opened when the bookmark is resolved and stays open while the
/// app runs, or until another folder is opened. Modelled on the iPhone's `IOSBookmarkedFolder`. The save folder and the
/// cloud folder of the phone link each have one.
final class MacBookmarkedFolder: @unchecked Sendable {
    static let saveFolder = MacBookmarkedFolder()
    static let syncFolder = MacBookmarkedFolder()

    private let lock = NSLock()
    /// The folder whose security-scoped access was started.
    private var accessed: URL?

    /// Whether the app runs in the App Sandbox, where a folder without a bookmark is lost at the next launch.
    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    /// The bookmark of `folder`, picked in an open panel; throws when none can be made of it.
    static func bookmark(of folder: URL) throws -> Data {
        try folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// The folder `bookmark` stands for, opened, and the bookmark to keep (made again when it is stale); nil when it does not
    /// resolve. Nothing is asked of the user; with `mounting` false a share that is offline is not mounted either.
    func resolve(_ bookmark: Data, mounting: Bool = true) -> (folder: URL, bookmark: Data)? {
        var stale = false
        var options: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI]
        if !mounting { options.insert(.withoutMounting) }
        guard let folder = try? URL(resolvingBookmarkData: bookmark, options: options, relativeTo: nil,
                                    bookmarkDataIsStale: &stale) else {
            close()
            return nil
        }
        // Bookmarks follow a folder into the Trash; saving there would lose the scans when it is emptied. The bookmark is
        // kept, so Put Back brings the folder back.
        if folder.pathComponents.contains(where: { $0 == ".Trash" || $0 == ".Trashes" }) {
            close()
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        if accessed != folder {
            accessed?.stopAccessingSecurityScopedResource()
            accessed = folder.startAccessingSecurityScopedResource() ? folder : nil
        }
        if stale, let fresh = try? MacBookmarkedFolder.bookmark(of: folder) {
            return (folder: folder, bookmark: fresh)
        }
        return (folder: folder, bookmark: bookmark)
    }

    func close() {
        lock.lock()
        accessed?.stopAccessingSecurityScopedResource()
        accessed = nil
        lock.unlock()
    }
}

extension AppState {
    /// Saves to `folder`, picked in an open panel, from now on and after a relaunch. When no bookmark can be made the pick
    /// is refused in the sandbox, which could not open the folder again; elsewhere the path alone is kept.
    func chooseSaveFolder(_ folder: URL) {
        let bookmark = try? MacBookmarkedFolder.bookmark(of: folder)
        if bookmark == nil, MacBookmarkedFolder.isSandboxed {
            errorMessage = String(localized: "The setting could not be saved.")
            return
        }
        var chosen = settings
        chosen.destinationBookmark = bookmark
        chosen.destinationPath = folder.path
        settings = chosen
        openBookmarkedFolder()
    }
}
#endif
