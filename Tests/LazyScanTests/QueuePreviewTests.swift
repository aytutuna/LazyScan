import CoreGraphics
import Foundation
import XCTest
@testable import LazyScanKit

// What a spooled page keeps in the queue (a thumbnail on the iPhone) and the preview read from its file for
// the screen that shows it large (QueuePreview.swift).
final class QueuePreviewTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("queue-preview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func page(width: Int, height: Int) -> ScannedPage {
        let space: CGColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ScannedPage(image: context.makeImage()!, dpi: 100, colorMode: .color)
    }

    func test_aSpooledPage_keepsAThumbnail_andRemembersItsFullSize() {
        let spooled = AppState.spoolPages([page(width: 2000, height: 3000)], to: folder,
                                          previewSide: QueuePreview.thumbnailSide)[0]
        XCTAssertEqual(Double(spooled.image.width), 266.7, accuracy: 1)
        XCTAssertEqual(spooled.image.height, QueuePreview.thumbnailSide)
        XCTAssertEqual(spooled.fullPixelSize, CGSize(width: 2000, height: 3000))
        XCTAssertNotNil(spooled.fileURL)
    }

    func test_withoutASide_aSpooledPageKeepsTheOldPreview() {
        let spooled = AppState.spoolPages([page(width: 2000, height: 3000)], to: folder)[0]
        XCTAssertEqual(spooled.image.height, QueuePreview.side)
    }

    func test_thePreview_isReadFromTheSpoolFile_andTurnedAsThePageIs() throws {
        var spooled = AppState.spoolPages([page(width: 2000, height: 3000)], to: folder,
                                          previewSide: QueuePreview.thumbnailSide)[0]
        let upright = try XCTUnwrap(QueuePreview.image(of: spooled))
        XCTAssertEqual(Double(upright.width), 1066.7, accuracy: 1)
        XCTAssertEqual(upright.height, QueuePreview.side)
        spooled.rotationQuarterTurns = 1
        let turned = try XCTUnwrap(QueuePreview.image(of: spooled))
        XCTAssertEqual(turned.width, QueuePreview.side)
        XCTAssertEqual(Double(turned.height), 1066.7, accuracy: 1)
    }

    func test_aPageWithoutAFile_isItsOwnPreview() throws {
        let held = page(width: 300, height: 400)
        let shown = try XCTUnwrap(QueuePreview.image(of: held))
        XCTAssertTrue(shown === held.image)
    }

    func test_aPageAsLargeAsAskedFor_isNotReadAgain() throws {
        let spooled = AppState.spoolPages([page(width: 2000, height: 3000)], to: folder)[0]
        let shown = try XCTUnwrap(QueuePreview.image(of: spooled))
        XCTAssertTrue(shown === spooled.image)
    }

    func test_aPageWhoseFileIsGone_hasNoPreview() {
        let spooled = AppState.spoolPages([page(width: 2000, height: 3000)], to: folder,
                                          previewSide: QueuePreview.thumbnailSide)[0]
        try? FileManager.default.removeItem(at: spooled.fileURL!)
        XCTAssertNil(QueuePreview.image(of: spooled))
    }

    @MainActor
    func test_theIPhoneQueuesThumbnails_theMacKeepsThePreview() {
        let state = AppState(backends: [], presetStore: PresetStore(directory: folder),
                             files: AppStateFiles.all(in: folder))
        XCTAssertEqual(state.queuePreviewSide, QueuePreview.side)
        state.platform = .ios
        XCTAssertEqual(state.queuePreviewSide, QueuePreview.thumbnailSide)
    }

    private func objects(of photo: ScannedPage, count: Int) -> [ScannedPage] {
        (0..<count).map { _ in
            ScannedPage(image: photo.image, dpi: 100, colorMode: .color)
                .withGeometry(photo.image, geometry: PageGeometry(cropped: true, angleDegrees: 0, basis: .perspective))
        }
    }

    func test_pagesCutFromOneShot_shareOneFileForTheOriginal() throws {
        let shot = objects(of: page(width: 400, height: 600), count: 3)
        let spooled = AppState.spoolPages(shot, to: folder)
        let others = Set(spooled.compactMap { $0.alternate?.fileURL })
        XCTAssertEqual(others.count, 1)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(names.filter { $0.hasSuffix("-other.tiff") }.count, 1)
        XCTAssertEqual(names.count, 4)
    }

    @MainActor
    func test_theSharedOriginal_goesWithTheLastPageThatUsesIt() throws {
        let state = AppState(backends: [], presetStore: PresetStore(directory: folder),
                             files: AppStateFiles.all(in: folder))
        let spooled = AppState.spoolPages(objects(of: page(width: 400, height: 600), count: 2), to: folder)
        let original = try XCTUnwrap(spooled[0].alternate?.fileURL)
        state.scannedPages = spooled
        state.deleteSpoolFiles(of: [spooled[0]])
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: spooled[0].fileURL!.path))
        state.scannedPages = [spooled[1]]
        state.deleteSpoolFiles(of: [spooled[1]])
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
    }

    @MainActor
    func test_aSwappedPage_keepsTheSharedFileForTheOthers() throws {
        let state = AppState(backends: [], presetStore: PresetStore(directory: folder),
                             files: AppStateFiles.all(in: folder))
        let spooled = AppState.spoolPages(objects(of: page(width: 400, height: 600), count: 2), to: folder)
        let original = try XCTUnwrap(spooled[0].alternate?.fileURL)
        let swapped = spooled[0].withVersionsSwapped(spooled[0].image)
        XCTAssertEqual(swapped.fileURL, original)
        state.scannedPages = [swapped, spooled[1]]
        state.deleteSpoolFiles(of: [spooled[1]])
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        state.scannedPages = [spooled[1]]
        state.deleteSpoolFiles(of: [swapped])
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        state.scannedPages = []
        state.deleteSpoolFiles(of: [spooled[1]])
        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
    }
}
