import CoreGraphics
import Foundation
import XCTest
@testable import LazyScanKit

// Undo after a save (AppState+Undo.swift): the pages and files of the last save, held while
// `keepsSavedForUndo` is on. Swift only, as `AppStateAppendTests`.

private struct UndoScorer: OrientationScorer {
    var isAvailable: Bool { false }

    func score(_ image: RgbaImage) throws -> OrientationScore {
        OrientationScore.none
    }
}

private struct UndoBarcodes: BarcodeReader {
    var isAvailable: Bool { false }

    func read(_ image: GrayImage) throws -> [BarcodeReading] {
        []
    }
}

private func undoPage(shade: CGFloat = 0.95) -> ScannedPage {
    let space: CGColorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: 300, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: shade, green: shade, blue: shade, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
    context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1))
    context.fill(CGRect(x: 50, y: 200, width: 200, height: 16))
    return ScannedPage(image: context.makeImage()!, dpi: 50, colorMode: .color)
}

@MainActor
private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool,
                       file: StaticString = #filePath, line: UInt = #line) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline {
            XCTFail("Timed out after \(timeout) s", file: file, line: line)
            return
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
}

final class AppStateUndoTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppStateUndoTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        // The settings are written 0.4 s after they change: let that write land before the folder goes.
        try await Task.sleep(nanoseconds: 600_000_000)
        try? FileManager.default.removeItem(at: folder)
    }

    private var saveFolder: URL { folder.appendingPathComponent("Saved", isDirectory: true) }

    @MainActor
    private func makeState(pages count: Int, undo: Bool) async throws -> AppState {
        let state = AppState(presetStore: PresetStore(directory: folder), orientationScorer: UndoScorer(),
                             barcodeReader: UndoBarcodes(), files: AppStateFiles.all(in: folder))
        state.keepsSavedForUndo = undo
        var settings = ScanSettings()
        settings.intent = .document
        settings.documentMultiPage = true
        settings.taskId = nil
        settings.source = .flatbed
        settings.duplex = .off
        settings.resolution = 75
        settings.format = .pdf
        settings.pdfSearchable = false
        settings.destinationPath = saveFolder.path
        state.settings = settings
        try await ingest(state, count)
        return state
    }

    @MainActor
    private func ingest(_ state: AppState, _ count: Int) async throws {
        let before = state.scannedPages.count
        var pages: [ScannedPage] = []
        for number in 0..<count {
            pages.append(undoPage(shade: 0.6 + CGFloat(number) * 0.1))
        }
        XCTAssertTrue(state.ingest(pages, source: .photo))
        try await waitUntil(timeout: 60) { !state.isBusy }
        XCTAssertEqual(state.scannedPages.count, before + count)
    }

    @MainActor
    private func finish(_ state: AppState) async throws {
        try await waitUntil(timeout: 60) { !state.isBusy }
        XCTAssertNil(state.errorMessage)
    }

    private func spoolFiles(of pages: [ScannedPage]) throws -> [URL] {
        try pages.map { try XCTUnwrap($0.fileURL) }
    }

    private func exists(_ urls: [URL]) -> [Bool] {
        urls.map { FileManager.default.fileExists(atPath: $0.path) }
    }

    @MainActor
    func test_undo_putsPagesBackInOrder_andDeletesEveryFileTheSaveWrote() async throws {
        let state = try await makeState(pages: 3, undo: true)
        let queued = state.scannedPages
        let spool = try spoolFiles(of: queued)
        state.saveImages()
        try await finish(state)
        let written = state.lastSavedURLs
        XCTAssertEqual(written.count, 3)
        XCTAssertEqual(exists(written), [true, true, true])
        XCTAssertTrue(state.scannedPages.isEmpty)
        XCTAssertTrue(state.canUndoSave)
        XCTAssertEqual(exists(spool), [true, true, true])

        state.undoSave()
        try await finish(state)
        XCTAssertEqual(state.scannedPages.map(\.id), queued.map(\.id))
        XCTAssertEqual(state.scannedPages.map(\.fileURL), queued.map(\.fileURL))
        XCTAssertEqual(exists(spool), [true, true, true])
        XCTAssertEqual(exists(written), [false, false, false])
        XCTAssertTrue(state.lastSavedURLs.isEmpty)
        XCTAssertFalse(state.canUndoSave)
        XCTAssertEqual(state.statusMessage, AppState.undoneMessage)

        // The pages save again as if nothing happened.
        state.savePDF()
        try await finish(state)
        XCTAssertEqual(state.lastSavedURLs.count, 1)
    }

    @MainActor
    func test_undo_ofAPDFSave_deletesThePDF_andAFileAlreadyGoneIsNoError() async throws {
        let state = try await makeState(pages: 2, undo: true)
        state.savePDF()
        try await finish(state)
        let pdf = try XCTUnwrap(state.lastSavedURLs.first)
        try FileManager.default.removeItem(at: pdf)
        state.undoSave()
        try await finish(state)
        XCTAssertEqual(state.scannedPages.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: pdf.path))
    }

    @MainActor
    func test_aNewScan_purgesTheUndo_andTheSpoolFiles() async throws {
        let state = try await makeState(pages: 2, undo: true)
        let spool = try spoolFiles(of: state.scannedPages)
        state.savePDF()
        try await finish(state)
        XCTAssertTrue(state.canUndoSave)
        XCTAssertEqual(exists(spool), [true, true])

        try await ingest(state, 1)
        XCTAssertFalse(state.canUndoSave)
        XCTAssertEqual(exists(spool), [false, false])
        let saved = try XCTUnwrap(state.lastSavedURLs.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path))
        state.undoSave()
        XCTAssertFalse(state.isBusy)
        XCTAssertEqual(state.scannedPages.count, 1)
    }

    @MainActor
    func test_anotherFileSaved_purgesTheUndo() async throws {
        let state = try await makeState(pages: 1, undo: true)
        let spool = try spoolFiles(of: state.scannedPages)
        state.savePDF()
        try await finish(state)
        XCTAssertTrue(state.canUndoSave)
        state.lastSavedURLs = [saveFolder.appendingPathComponent("Other.pdf")]
        XCTAssertFalse(state.canUndoSave)
        XCTAssertEqual(exists(spool), [false])
    }

    @MainActor
    func test_withoutTheSwitch_theSpoolFilesGoAtOnce() async throws {
        let state = try await makeState(pages: 2, undo: false)
        let spool = try spoolFiles(of: state.scannedPages)
        state.savePDF()
        try await finish(state)
        XCTAssertFalse(state.canUndoSave)
        XCTAssertEqual(exists(spool), [false, false])
        state.undoSave()
        XCTAssertTrue(state.scannedPages.isEmpty)
    }

    @MainActor
    func test_undo_ofAppendedPages_putsThePDFBackAsItWas() async throws {
        let state = try await makeState(pages: 2, undo: true)
        let queued = state.scannedPages
        let data = try PDFBuilder.makePDF(pages: [undoPage()], pdfSize: .best, progress: nil, textLayer: nil, options: nil)
        try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        let url = saveFolder.appendingPathComponent("Contract.pdf")
        try data.write(to: url)

        state.setAppendTarget(url)
        state.savePDF()
        try await finish(state)
        XCTAssertGreaterThan(try Data(contentsOf: url).count, data.count)
        XCTAssertTrue(state.canUndoSave)

        state.undoSave()
        try await finish(state)
        XCTAssertEqual(try Data(contentsOf: url), data)
        XCTAssertEqual(state.scannedPages.map(\.id), queued.map(\.id))
        XCTAssertEqual(state.appendTarget, url)
        XCTAssertEqual(state.statusMessage, AppState.undoneAppendMessage("Contract.pdf"))
        // Only the pages' own files are left in the spool: the copy of the PDF went with the undo.
        let spool = try FileManager.default.contentsOfDirectory(atPath: AppStateFiles.all(in: folder).spoolDirectory.path)
        XCTAssertFalse(spool.contains { $0.hasSuffix(".pdf") })
    }

    @MainActor
    func test_aNewScan_afterAppend_removesTheCopyOfThePDF() async throws {
        let state = try await makeState(pages: 1, undo: true)
        let data = try PDFBuilder.makePDF(pages: [undoPage()], pdfSize: .best, progress: nil, textLayer: nil, options: nil)
        try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        let url = saveFolder.appendingPathComponent("Contract.pdf")
        try data.write(to: url)
        state.appendToPDF(at: url)
        try await finish(state)
        XCTAssertTrue(state.canUndoSave)
        try await ingest(state, 1)
        XCTAssertFalse(state.canUndoSave)
        let spool = try FileManager.default.contentsOfDirectory(atPath: AppStateFiles.all(in: folder).spoolDirectory.path)
        XCTAssertFalse(spool.contains { $0.hasSuffix(".pdf") })
    }
}
