import CoreGraphics
import Foundation
import XCTest
@testable import LazyScanKit

// A PDF dropped on or picked in the Mac's import: its pages come into the queue one by one with no corner
// editor, and a protected or damaged PDF is reported by name. The renderer is a stand-in; the Mac's PDFKit
// one is tested in LazyScanMacTests. Every AppState keeps its settings, presets and spool in a folder of its own.

private struct ImportScorer: OrientationScorer {
    var isAvailable: Bool { false }

    func score(_ image: RgbaImage) throws -> OrientationScore {
        OrientationScore.none
    }
}

private struct ImportBarcodes: BarcodeReader {
    var isAvailable: Bool { false }

    func read(_ image: GrayImage) throws -> [BarcodeReading] {
        []
    }
}

/// Reads what a file says in its first bytes: "locked", "pages3" (a PDF of three pages) or anything else, which is no PDF.
private struct StandInPDFPages: PDFPageRenderer {
    func open(_ data: Data) -> PDFOpening {
        if data.starts(with: Data("locked".utf8)) { return .locked }
        if data.starts(with: Data("pages3".utf8)) { return .pages(3) }
        return .unreadable
    }

    func page(_ data: Data, at index: Int) -> ScannedPage? {
        let width = 400, height = 520
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.93, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1))
        context.fill(CGRect(x: width / 6, y: height / 2, width: width * 2 / 3, height: 20))
        var page = ScannedPage(image: context.makeImage()!, dpi: PhotoImport.pdfDPI, colorMode: .color)
        page.source = .photo
        return page
    }
}

final class AppStateImportPDFTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppStateImportPDFTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        // The settings are written 0.4 s after they change: let that write land before the folder goes.
        try await Task.sleep(nanoseconds: 600_000_000)
        try? FileManager.default.removeItem(at: folder)
    }

    @MainActor
    private func makeState(renderer: (any PDFPageRenderer)?) -> AppState {
        let state = AppState(presetStore: PresetStore(directory: folder), orientationScorer: ImportScorer(),
                             barcodeReader: ImportBarcodes(), files: AppStateFiles.all(in: folder))
        var settings = ScanSettings()
        settings.intent = .document
        settings.documentMultiPage = true
        settings.taskId = nil
        settings.format = .pdf
        settings.pdfSearchable = false
        settings.destinationPath = folder.path
        state.settings = settings
        state.pdfPages = renderer
        return state
    }

    private func file(_ name: String, _ start: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(start.utf8).write(to: url)
        return url
    }

    @MainActor
    private func importAndWait(_ state: AppState, _ urls: [URL]) async throws {
        state.importPhotos(urls)
        let deadline = Date().addingTimeInterval(60)
        while state.isBusy {
            XCTAssertLessThan(Date(), deadline, "Timed out")
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    @MainActor
    func test_aPDFBecomesQueuePagesAt300Dpi_withoutTheCornerEditor() async throws {
        let state = makeState(renderer: StandInPDFPages())
        try await importAndWait(state, [try file("scan.pdf", "pages3")])
        XCTAssertNil(state.errorMessage)
        XCTAssertNil(state.cornerReview)
        XCTAssertEqual(state.scannedPages.count, 3)
        XCTAssertEqual(state.scannedPages.map(\.dpi), [300, 300, 300])
    }

    @MainActor
    func test_aProtectedPDFIsRefusedByName_andOthersStillComeIn() async throws {
        let state = makeState(renderer: StandInPDFPages())
        try await importAndWait(state, [try file("secret.pdf", "locked"), try file("scan.pdf", "pages3")])
        XCTAssertEqual(state.scannedPages.count, 3)
        XCTAssertEqual(state.errorMessage, PhotoImport.unreadableMessage("secret.pdf", detail: PhotoImport.lockedDetail))
    }

    @MainActor
    func test_aDamagedPDFAndAMissingRendererAreReportedAsUnreadable() async throws {
        let damaged = makeState(renderer: StandInPDFPages())
        try await importAndWait(damaged, [try file("broken.pdf", "not a pdf")])
        XCTAssertTrue(damaged.scannedPages.isEmpty)
        XCTAssertEqual(damaged.errorMessage, PhotoImport.unreadableMessage("broken.pdf", detail: PhotoImport.unreadableDetail))
        let without = makeState(renderer: nil)
        try await importAndWait(without, [try file("scan.pdf", "pages3")])
        XCTAssertTrue(without.scannedPages.isEmpty)
        XCTAssertEqual(without.errorMessage, PhotoImport.unreadableMessage("scan.pdf", detail: PhotoImport.unreadableDetail))
    }
}
