import CoreGraphics
import Foundation
import XCTest
@testable import LazyScanKit

// The photocopy on the Mac keeps its pages after a print that was cancelled or failed, for Print Again
// and Choose Another Printer in the status bar; a print that went through, a new page and another task
// let them go. The iPhone holds a copy on its own screen (`IOSCopyTests`).

/// A printer that prints whatever it is sent, is cancelled (`answer`) or fails (`failure`), counting what
/// came through `printAgain`.
@MainActor
private final class MacCopyPrintService: PrintService {
    var answer = true
    var failure: Error?
    private(set) var jobs: [PrintJob] = []
    private(set) var againCount = 0

    var printerNames: [String] { ["Office Printer"] }

    var defaultPrinterName: String? { "Office Printer" }

    func setup(printerName: String?, requestedPaper: PaperSize?) -> PrinterSetup? {
        PrinterSetup(printerName: "Office Printer",
                     paper: PrinterPaper.make(paper: CGSize(width: 8.5, height: 11), printable: nil))
    }

    func print(_ document: Data, job: PrintJob) async throws -> Bool {
        if let failure { throw failure }
        if answer { jobs.append(job) }
        return answer
    }

    func printAgain(_ document: Data, job: PrintJob) async throws -> Bool {
        againCount += 1
        return try await print(document, job: job)
    }
}

private struct MacCopyScorer: OrientationScorer {
    var isAvailable: Bool { false }

    func score(_ image: RgbaImage) throws -> OrientationScore {
        OrientationScore.none
    }
}

private struct MacCopyBarcodes: BarcodeReader {
    var isAvailable: Bool { false }

    func read(_ image: GrayImage) throws -> [BarcodeReading] {
        []
    }
}

private func copyPage() -> ScannedPage {
    let image: CGImage = RgbaImage.filled(width: 400, height: 400, r: 255, g: 255, b: 255).makeCGImage()!
    return ScannedPage(image: image, dpi: 100, colorMode: .color)
}

final class AppStateMacCopyTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppStateMacCopyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        // The settings are written 0.4 s after they change: let that write land before the folder goes.
        try await Task.sleep(nanoseconds: 600_000_000)
        try? FileManager.default.removeItem(at: folder)
    }

    @MainActor
    private func makeState(_ printer: MacCopyPrintService) -> AppState {
        let state = AppState(backends: [], presetStore: PresetStore(directory: folder), printService: printer,
                             orientationScorer: MacCopyScorer(), barcodeReader: MacCopyBarcodes(),
                             files: AppStateFiles.all(in: folder))
        state.settings.destinationPath = folder.path
        XCTAssertTrue(state.startTask(.copy))
        return state
    }

    @MainActor
    private func idle(_ state: AppState) async throws {
        let deadline = Date().addingTimeInterval(60)
        while state.isBusy {
            XCTAssertLessThan(Date(), deadline)
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    @MainActor
    func test_aCancelledPrintPanel_keepsThePages_andPrintAgainPrintsThem() async throws {
        let printer = MacCopyPrintService()
        printer.answer = false
        let state: AppState = makeState(printer)
        XCTAssertTrue(state.ingest([copyPage()], source: .photo))
        try await idle(state)
        XCTAssertEqual(state.statusMessage, "Printing cancelled.")
        XCTAssertNil(state.errorMessage)
        XCTAssertNil(state.copyPrintFailure)
        XCTAssertEqual(state.copyPages.count, 1)
        XCTAssertTrue(state.copyIsKept)
        XCTAssertTrue(state.canIngest)

        printer.answer = true
        state.printHeldCopyAgain()
        try await idle(state)
        XCTAssertEqual(printer.againCount, 1)
        XCTAssertEqual(printer.jobs.count, 1)
        XCTAssertNil(state.errorMessage)
        XCTAssertTrue(state.copyPages.isEmpty)
        XCTAssertFalse(state.copyIsKept)
        XCTAssertEqual(state.statusMessage, PrintText.sent(pageCount: 1, copies: 1, printerName: "Office Printer"))
    }

    @MainActor
    func test_aFailedPrint_keepsThePages_saysSo_andChoosingAnotherPrinterPrintsThem() async throws {
        let printer = MacCopyPrintService()
        printer.failure = PrintError.failed("The printer is offline.")
        let state: AppState = makeState(printer)
        XCTAssertTrue(state.ingest([copyPage()], source: .photo))
        try await idle(state)
        XCTAssertEqual(state.statusMessage, "Could not print.")
        XCTAssertEqual(state.errorMessage, "The printer is offline. The copy is still here.")
        XCTAssertEqual(state.copyPrintFailure, "The printer is offline.")
        XCTAssertEqual(state.copyPages.count, 1)

        printer.failure = nil
        state.errorMessage = nil
        state.printHeldCopy()
        try await idle(state)
        XCTAssertEqual(printer.againCount, 0)
        XCTAssertEqual(printer.jobs.count, 1)
        XCTAssertNil(state.errorMessage)
        XCTAssertNil(state.copyPrintFailure)
        XCTAssertTrue(state.copyPages.isEmpty)
    }

    @MainActor
    func test_aNewPage_orAnotherTask_letsTheHeldPagesGo() async throws {
        let printer = MacCopyPrintService()
        printer.answer = false
        let state: AppState = makeState(printer)
        XCTAssertTrue(state.ingest([copyPage()], source: .photo))
        try await idle(state)
        let first: UUID? = state.copyPages.first?.id
        XCTAssertNotNil(first)

        XCTAssertTrue(state.ingest([copyPage()], source: .photo))
        try await idle(state)
        XCTAssertEqual(state.copyPages.count, 1)
        XCTAssertNotEqual(state.copyPages.first?.id, first)

        printer.failure = PrintError.failed("The printer is offline.")
        state.printHeldCopy()
        try await idle(state)
        XCTAssertNotNil(state.copyPrintFailure)

        XCTAssertTrue(state.startTask(.document))
        XCTAssertTrue(state.copyPages.isEmpty)
        XCTAssertNil(state.copyPrintFailure)
        XCTAssertFalse(state.copyIsKept)
    }
}
