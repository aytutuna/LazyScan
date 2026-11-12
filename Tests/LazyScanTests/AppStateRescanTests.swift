import CoreGraphics
import XCTest
@testable import LazyScanKit

// Scan Again (AppState+Rescan.swift): the next scan takes a marked page's place. Swift only, as the
// Mac's page strip is.

@MainActor
final class AppStateRescanTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppStateRescanTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try await Task.sleep(nanoseconds: 600_000_000)
        try? FileManager.default.removeItem(at: folder)
    }

    private func page() -> ScannedPage {
        let space: CGColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: 30, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ScannedPage(image: context.makeImage()!, dpi: 50, colorMode: .color)
    }

    private func makeState(pages count: Int) -> AppState {
        let state = AppState(presetStore: PresetStore(directory: folder), files: AppStateFiles.all(in: folder))
        state.scannedPages = (0..<count).map { _ in page() }
        return state
    }

    func test_withoutAMark_aScanGoesToTheEnd() {
        let state = makeState(pages: 3)
        let queued = state.scannedPages.map(\.id)
        let added = page()
        state.queueScanned([added], source: .scanner)
        XCTAssertEqual(state.scannedPages.map(\.id), queued + [added.id])
    }

    func test_aMarkedPage_isReplacedInPlace() {
        let state = makeState(pages: 4)
        let queued = state.scannedPages.map(\.id)
        state.armRescan(id: queued[1])
        XCTAssertEqual(state.rescanTarget, queued[1])
        let added = page()
        state.queueScanned([added], source: .scanner)
        XCTAssertEqual(state.scannedPages.map(\.id), [queued[0], added.id, queued[2], queued[3]])
        XCTAssertNil(state.rescanTarget)
        XCTAssertTrue(state.canUndoRemove)
    }

    func test_undoRemove_bringsTheReplacedPageBack() {
        let state = makeState(pages: 3)
        let queued = state.scannedPages.map(\.id)
        state.armRescan(id: queued[1])
        let added = page()
        state.queueScanned([added], source: .scanner)
        state.undoRemove()
        XCTAssertEqual(state.scannedPages.map(\.id), [queued[0], queued[1], added.id, queued[2]])
    }

    func test_theRestOfTheScan_followsTheFirstPage() {
        let state = makeState(pages: 3)
        let queued = state.scannedPages.map(\.id)
        state.armRescan(id: queued[0])
        let first = page(), second = page(), third = page()
        state.queueScanned([first], source: .scanner)
        state.queueScanned([second], source: .scanner)
        state.queueScanned([third], source: .scanner)
        XCTAssertEqual(state.scannedPages.map(\.id), [first.id, second.id, third.id, queued[1], queued[2]])
    }

    func test_aPageFromAPhone_goesToTheEndAndKeepsTheMark() {
        let state = makeState(pages: 2)
        let queued = state.scannedPages.map(\.id)
        state.armRescan(id: queued[0])
        let added = page()
        state.queueScanned([added], source: .phone)
        XCTAssertEqual(state.scannedPages.map(\.id), queued + [added.id])
        XCTAssertEqual(state.rescanTarget, queued[0])
    }

    func test_theMark_movesAndClears() {
        let state = makeState(pages: 3)
        let queued = state.scannedPages.map(\.id)
        state.armRescan(id: UUID())
        XCTAssertNil(state.rescanTarget)
        state.armRescan(id: queued[0])
        state.armRescan(id: queued[2])
        XCTAssertEqual(state.rescanTarget, queued[2])
        state.removePage(id: queued[2])
        XCTAssertNil(state.rescanTarget)
        state.armRescan(id: queued[0])
        state.cancelRescan()
        XCTAssertNil(state.rescanTarget)
    }

    func test_aScanThatIsNotQueued_cannotBeMarked() {
        let state = makeState(pages: 3)
        state.settings.documentMultiPage = false
        state.armRescan(id: state.scannedPages[1].id)
        XCTAssertNil(state.rescanTarget)
    }

    func test_aMark_isClearedWhenScansStopGoingToTheQueue() {
        let state = makeState(pages: 3)
        state.armRescan(id: state.scannedPages[1].id)
        state.settings.documentMultiPage = false
        XCTAssertNil(state.rescanTarget)
    }
}
