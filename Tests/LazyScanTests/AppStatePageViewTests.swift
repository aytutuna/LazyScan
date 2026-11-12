import CoreGraphics
import Foundation
import XCTest
@testable import LazyScanKit

// Which queued page the canvas shows large (AppState+PageView.swift).

final class AppStatePageViewTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppStatePageViewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try await Task.sleep(nanoseconds: 600_000_000)
        try? FileManager.default.removeItem(at: folder)
    }

    private func picture() -> CGImage {
        let context = CGContext(data: nil, width: 8, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    @MainActor
    private func makeState(pages count: Int) -> AppState {
        let state = AppState(presetStore: PresetStore(directory: folder), files: AppStateFiles.all(in: folder))
        state.scannedPages = (0..<count).map { _ in ScannedPage(image: picture(), dpi: 100, colorMode: .color) }
        return state
    }

    @MainActor
    func test_viewPage_showsThePage_andPreviewKeepsIt() {
        let state = makeState(pages: 3)
        let ids = state.scannedPages.map(\.id)
        XCTAssertFalse(state.viewsPage)
        XCTAssertNil(state.viewedPageID)

        state.viewPage(id: ids[1])
        XCTAssertTrue(state.viewsPage)
        XCTAssertEqual(state.viewedPage?.page.id, ids[1])
        XCTAssertEqual(state.viewedPage?.number, 2)

        state.showPreview()
        XCTAssertFalse(state.viewsPage)
        XCTAssertNil(state.viewedPage)
        XCTAssertEqual(state.viewedPageID, ids[1])

        state.showPage()
        XCTAssertTrue(state.viewsPage)
        XCTAssertEqual(state.viewedPageID, ids[1])
    }

    @MainActor
    func test_showPage_withNoPagePicked_opensTheFirst() {
        let state = makeState(pages: 2)
        state.showPage()
        XCTAssertEqual(state.viewedPageID, state.scannedPages[0].id)
        XCTAssertTrue(state.viewsPage)
    }

    @MainActor
    func test_viewPage_ignoresAPageNotInTheQueue() {
        let state = makeState(pages: 1)
        state.viewPage(id: UUID())
        XCTAssertNil(state.viewedPageID)
        XCTAssertFalse(state.viewsPage)
    }

    @MainActor
    func test_removingTheViewedPage_picksTheNext_elseThePrevious() {
        let state = makeState(pages: 3)
        let ids = state.scannedPages.map(\.id)

        state.viewPage(id: ids[1])
        state.scannedPages.removeAll { $0.id == ids[1] }
        XCTAssertEqual(state.viewedPageID, ids[2])
        XCTAssertTrue(state.viewsPage)

        state.scannedPages.removeAll { $0.id == ids[2] }
        XCTAssertEqual(state.viewedPageID, ids[0])
        XCTAssertTrue(state.viewsPage)
    }

    @MainActor
    func test_removingAnotherPage_keepsTheViewedPage() {
        let state = makeState(pages: 3)
        let ids = state.scannedPages.map(\.id)
        state.viewPage(id: ids[2])
        state.scannedPages.removeAll { $0.id == ids[0] }
        XCTAssertEqual(state.viewedPageID, ids[2])
        XCTAssertEqual(state.viewedPage?.number, 2)
    }

    @MainActor
    func test_movingTheViewedPage_keepsItViewed() {
        let state = makeState(pages: 3)
        let ids = state.scannedPages.map(\.id)
        state.viewPage(id: ids[0])
        state.movePage(id: ids[0], to: 2)
        XCTAssertEqual(state.viewedPageID, ids[0])
        XCTAssertEqual(state.viewedPage?.number, 3)
    }

    @MainActor
    func test_emptyingTheQueue_returnsToThePreview() {
        let state = makeState(pages: 1)
        state.viewPage(id: state.scannedPages[0].id)
        state.scannedPages = []
        XCTAssertNil(state.viewedPageID)
        XCTAssertFalse(state.viewsPage)
    }

    @MainActor
    func test_aNewPageLanding_doesNotChangeTheView() {
        let state = makeState(pages: 2)
        let ids = state.scannedPages.map(\.id)
        state.viewPage(id: ids[0])
        state.scannedPages.append(ScannedPage(image: picture(), dpi: 100, colorMode: .color))
        XCTAssertEqual(state.viewedPageID, ids[0])
        XCTAssertTrue(state.viewsPage)
    }

    @MainActor
    func test_stepViewedPage_movesByOne_andStopsAtTheEnds() {
        let state = makeState(pages: 3)
        let ids = state.scannedPages.map(\.id)

        state.stepViewedPage(by: 1)
        XCTAssertNil(state.viewedPageID)

        state.viewPage(id: ids[0])
        state.stepViewedPage(by: -1)
        XCTAssertEqual(state.viewedPageID, ids[0])
        state.stepViewedPage(by: 1)
        XCTAssertEqual(state.viewedPageID, ids[1])
        state.stepViewedPage(by: 1)
        state.stepViewedPage(by: 1)
        XCTAssertEqual(state.viewedPageID, ids[2])
        XCTAssertTrue(state.viewsPage)
    }
}
