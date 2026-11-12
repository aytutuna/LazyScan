import CoreGraphics
import Foundation
import XCTest
@testable import LazyScanKit

// The system's background time held across a save (`AppState.runExclusive`), and the sweep of the
// temporary files an ended save leaves. Swift only, as `AppStateUndoTests`.

private struct BackgroundScorer: OrientationScorer {
    var isAvailable: Bool { false }

    func score(_ image: RgbaImage) throws -> OrientationScore {
        OrientationScore.none
    }
}

private struct BackgroundBarcodes: BarcodeReader {
    var isAvailable: Bool { false }

    func read(_ image: GrayImage) throws -> [BarcodeReading] {
        []
    }
}

@MainActor
private final class FakeBackground: BackgroundActivity {
    private(set) var begun: [String] = []
    private(set) var ended: [Int] = []
    /// The system's time is up as soon as an activity begins.
    var expiresAtOnce = false

    func beginActivity(_ name: String, expired: @escaping @MainActor () -> Void) -> Int? {
        begun.append(name)
        if expiresAtOnce {
            expired()
        }
        return begun.count
    }

    func endActivity(_ token: Int) {
        ended.append(token)
    }
}

private func backgroundPage() -> ScannedPage {
    let space: CGColorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: 300, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
    return ScannedPage(image: context.makeImage()!, dpi: 50, colorMode: .color)
}

@MainActor
private func waitUntilIdle(_ state: AppState, timeout: TimeInterval = 60,
                           file: StaticString = #filePath, line: UInt = #line) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while state.isBusy {
        if Date() > deadline {
            XCTFail("Timed out after \(timeout) s", file: file, line: line)
            return
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
}

final class AppStateBackgroundTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppStateBackgroundTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try await Task.sleep(nanoseconds: 600_000_000)
        try? FileManager.default.removeItem(at: folder)
    }

    private var saveFolder: URL { folder.appendingPathComponent("Saved", isDirectory: true) }

    @MainActor
    private func makeState(background: FakeBackground?) async throws -> AppState {
        let state = AppState(presetStore: PresetStore(directory: folder), orientationScorer: BackgroundScorer(),
                             barcodeReader: BackgroundBarcodes(), background: background,
                             files: AppStateFiles.all(in: folder))
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
        XCTAssertTrue(state.ingest([backgroundPage(), backgroundPage()], source: .photo))
        try await waitUntilIdle(state)
        XCTAssertEqual(state.scannedPages.count, 2)
        return state
    }

    private func savedNames() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: saveFolder.path)) ?? []
    }

    @MainActor
    func test_save_holdsBackgroundTimeUntilItIsDone() async throws {
        let background = FakeBackground()
        let state = try await makeState(background: background)
        let before = background.begun.count
        state.savePDF()
        XCTAssertEqual(background.begun.count, before + 1)
        XCTAssertEqual(background.ended.count, before)
        try await waitUntilIdle(state)
        XCTAssertEqual(background.ended.count, background.begun.count)
        XCTAssertEqual(state.lastSavedURLs.count, 1)
    }

    @MainActor
    func test_save_whenTheSystemsTimeIsUp_isCancelledAndLeavesTheQueueAndNoTempFile() async throws {
        let background = FakeBackground()
        let state = try await makeState(background: background)
        background.expiresAtOnce = true
        state.savePDF()
        try await waitUntilIdle(state)
        XCTAssertTrue(state.lastSavedURLs.isEmpty)
        XCTAssertEqual(state.scannedPages.count, 2)
        XCTAssertEqual(savedNames().filter { $0.hasSuffix(".pdf") || $0.hasSuffix(".pdf.tmp") }, [])
        XCTAssertEqual(background.ended.count, background.begun.count)
    }

    @MainActor
    func test_removeStaleSaveTemps_removesHiddenTempFilesOnly() async throws {
        let state = try await makeState(background: nil)
        try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
        let stale = saveFolder.appendingPathComponent(".\(UUID().uuidString).pdf.tmp")
        let kept = saveFolder.appendingPathComponent("Scan 1.pdf")
        let other = saveFolder.appendingPathComponent("notes.pdf.tmp")
        for url in [stale, kept, other] {
            try Data("x".utf8).write(to: url)
        }
        let recent = saveFolder.appendingPathComponent(".\(UUID().uuidString).pdf.tmp")
        try Data("x".utf8).write(to: recent)
        let old = Date().addingTimeInterval(-7200)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: stale.path)
        state.removeStaleSaveTemps()
        let deadline = Date().addingTimeInterval(10)
        while savedNames().contains(stale.lastPathComponent), Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(savedNames().sorted(), ["Scan 1.pdf", "notes.pdf.tmp", recent.lastPathComponent].sorted())
    }

    @MainActor
    func test_ingest_whenTheSystemsTimeIsUp_stillQueuesItsPages() async throws {
        let background = FakeBackground()
        background.expiresAtOnce = true
        let state = try await makeState(background: background)
        XCTAssertEqual(state.scannedPages.count, 2)
        XCTAssertEqual(background.ended.count, background.begun.count)
    }
}
