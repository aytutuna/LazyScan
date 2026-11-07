#if os(macOS)
import XCTest
@testable import LazyScanKit
@testable import LazyScanMac

// The bookmark of a folder the user picked: made of a folder, it opens the same folder again, and the save folder
// kept on the settings is the one the bookmark stands for.

@MainActor
final class MacBookmarkedFolderTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("bookmarked-" + UUID().uuidString,
                                                                              isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    func test_bookmark_opensTheSameFolder() throws {
        let kept = MacBookmarkedFolder()
        defer { kept.close() }
        let bookmark = try MacBookmarkedFolder.bookmark(of: folder)

        let opened = try XCTUnwrap(kept.resolve(bookmark))

        XCTAssertEqual(opened.folder.resolvingSymlinksInPath().path, folder.resolvingSymlinksInPath().path)
    }

    func test_resolve_nilForDataThatIsNotABookmark() {
        XCTAssertNil(MacBookmarkedFolder().resolve(Data([1, 2, 3])))
    }

    func test_chooseSaveFolder_keepsABookmarkAndThePath() throws {
        let state = AppState(backends: [], presetStore: PresetStore(directory: folder), files: AppStateFiles.all(in: folder))
        let kept = MacBookmarkedFolder()
        defer { kept.close() }
        state.resolveDestinationBookmark = { kept.resolve($0) }

        state.chooseSaveFolder(folder)

        XCTAssertNotNil(state.settings.destinationBookmark)
        XCTAssertEqual(URL(fileURLWithPath: state.settings.destinationPath).resolvingSymlinksInPath().path,
                       folder.resolvingSymlinksInPath().path)
        XCTAssertEqual(try state.destinationDirectory().resolvingSymlinksInPath().path, folder.resolvingSymlinksInPath().path)
    }

    func test_defaultSaveFolder_isLazyScanInDownloads() {
        XCTAssertTrue(ScanSettings.defaultDestinationPath.hasSuffix("/Downloads/Lazy Scan"))
    }
}
#endif
