import CoreGraphics
import Foundation
import XCTest
@testable import LazyScanKit

// The queue the iPhone and the Mac keep (AppState+QueueRecord.swift): recorded beside its spool files and
// brought back when the next AppState is made, the pages whose files are there, as long as the settings save
// a queue; otherwise the spool is emptied as it always was. The Mac's queue is emptied at quit
// (discardsQueueAtQuit), so only a crash leaves it. The Core's QueueRecord is the twin.

/// Text recognition that cannot run, so no page is read with Vision here.
private struct RecordScorer: OrientationScorer {
    var isAvailable: Bool { false }

    func score(_ image: RgbaImage) throws -> OrientationScore {
        OrientationScore.none
    }
}

/// Barcode reading that cannot run.
private struct RecordBarcodes: BarcodeReader {
    var isAvailable: Bool { false }

    func read(_ image: GrayImage) throws -> [BarcodeReading] {
        []
    }
}

/// A light page with a dark bar across it.
private func recordPage() -> ScannedPage {
    let space: CGColorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: 300, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.95, green: 0.95, blue: 0.93, alpha: 1))
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

/// Sends "the app may end now" by hand, as going to the background does on the iPhone.
@MainActor
private final class RecordLifecycle: PlatformLifecycle {
    private var endHandlers: [@MainActor () -> Void] = []

    func observeWillTerminate(_ handler: @escaping @MainActor () -> Void) {
        endHandlers.append(handler)
    }

    func observeDidBecomeActive(_ handler: @escaping @MainActor () -> Void) {}

    func sendWillTerminate() {
        for handler in endHandlers {
            handler()
        }
    }
}

final class AppStateQueueRecordTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppStateQueueRecordTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try await Task.sleep(nanoseconds: 600_000_000)
        try? FileManager.default.removeItem(at: folder)
    }

    private func files(keepsQueue: Bool) -> AppStateFiles {
        var files = AppStateFiles.all(in: folder)
        files.keepsQueue = keepsQueue
        return files
    }

    private var spool: URL { folder.appendingPathComponent("pages", isDirectory: true) }

    @MainActor
    private func makeState(keepsQueue: Bool = true) -> AppState {
        AppState(presetStore: PresetStore(directory: folder), orientationScorer: RecordScorer(),
                 barcodeReader: RecordBarcodes(), files: files(keepsQueue: keepsQueue))
    }

    /// An AppState keeping its queue, on Document to PDF with two pages queued, the second skipped by hand
    /// and turned, its record written and `settings` saved as the next launch reads them.
    @MainActor
    private func makeQueue(settings: ((ScanSettings) -> ScanSettings)? = nil) async throws -> AppState {
        let state = makeState()
        XCTAssertTrue(state.startTask(.document))
        state.settings.destinationPath = folder.path
        XCTAssertTrue(state.ingest([recordPage(), recordPage()], source: .photo))
        try await waitUntil(timeout: 60) { !state.isBusy && state.scannedPages.count == 2 }
        state.togglePageInclusion(id: state.scannedPages[1].id)
        state.scannedPages[1].rotationQuarterTurns = 1
        state.writeQueueRecord()
        // The settings' own write lands 0.4 s after they change; this one comes after it.
        try await Task.sleep(nanoseconds: 600_000_000)
        SettingsStore.save(settings?(state.settings) ?? state.settings, directory: folder)
        return state
    }

    @MainActor
    private func spoolNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: spool.path)) ?? []).sorted()
    }

    @MainActor
    func test_aKeptQueue_comesBackAtLaunch_asItWas() async throws {
        let before = try await makeQueue()
        XCTAssertTrue(FileManager.default.fileExists(atPath: spool.appendingPathComponent(QueueRecord.fileName).path))
        let pages: [ScannedPage] = before.scannedPages

        let after = makeState()
        after.queueRecordDelay = 20_000_000
        // Until the pages are back nothing can switch the kind past them, save or take a page.
        XCTAssertTrue(after.isBusy)
        XCTAssertTrue(after.restoringQueue)
        XCTAssertEqual(after.statusMessage, "Bringing back 2 pages\u{2026}")
        XCTAssertFalse(after.startTask(.photos))
        XCTAssertFalse(after.canIngest)
        try await waitUntil(timeout: 30) { !after.isBusy }
        XCTAssertFalse(after.restoringQueue)
        XCTAssertEqual(after.activeTask, .document)
        XCTAssertEqual(after.statusMessage, "2 pages are back from last time.")
        XCTAssertEqual(after.scannedPages.map(\.id), pages.map(\.id))
        XCTAssertEqual(after.scannedPages.map(\.fileURL), pages.map(\.fileURL))
        XCTAssertEqual(after.scannedPages.map(\.inclusion), pages.map(\.inclusion))
        XCTAssertEqual(after.scannedPages.map(\.dpi), pages.map(\.dpi))
        XCTAssertEqual(after.scannedPages.map(\.fullPixelSize), pages.map(\.fullPixelSize))
        XCTAssertEqual(after.scannedPages.map(\.source), pages.map(\.source))
        XCTAssertEqual(after.scannedPages[1].rotationQuarterTurns, 1)
        // The preview is read from the file again, turned as the page was.
        XCTAssertEqual(after.scannedPages[0].image.width, pages[0].image.width)
        XCTAssertEqual(after.scannedPages[1].image.width, pages[0].image.height)
        for page in after.scannedPages {
            XCTAssertTrue(FileManager.default.fileExists(atPath: page.fileURL!.path))
        }

        // Saved or discarded, the queue takes its record with it.
        after.clearPages()
        try await waitUntil(timeout: 5) {
            !FileManager.default.fileExists(atPath: spool.appendingPathComponent(QueueRecord.fileName).path)
        }
    }

    @MainActor
    func test_pagesThatCannotBeSpooled_warnOfFullStorage_once() async throws {
        let state = makeState()
        XCTAssertTrue(state.startTask(.document))
        state.settings.destinationPath = folder.path
        // A file where the spool folder should be: nothing can be written there.
        try FileManager.default.removeItem(at: spool)
        try Data().write(to: spool)
        XCTAssertTrue(state.ingest([recordPage()], source: .photo))
        try await waitUntil(timeout: 60) { !state.isBusy && state.scannedPages.count == 1 }
        XCTAssertNil(state.scannedPages[0].fileURL)
        let warning = L10n.t("Storage is full: these pages are lost if the app closes.")
        state.writeQueueRecord()
        XCTAssertEqual(state.statusMessage, warning)
        state.statusMessage = "Something else"
        state.writeQueueRecord()
        XCTAssertEqual(state.statusMessage, "Something else")
    }

    @MainActor
    func test_aSavesEnd_dropsOnlyThePagesItSaved() async throws {
        let state = try await makeQueue()
        let saved: ScannedPage = state.scannedPages[0]
        let other: ScannedPage = state.scannedPages[1]
        state.dropSaved([saved])
        XCTAssertEqual(state.scannedPages.map(\.id), [other.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: saved.fileURL!.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.fileURL!.path))
    }

    @MainActor
    func test_aQueueTheSettingsCannotSave_isEmptiedAtLaunch() async throws {
        _ = try await makeQueue { (settings: ScanSettings) -> ScanSettings in
            TaskCatalog.apply(.idCard, to: settings)
        }
        let after = makeState()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(after.scannedPages.isEmpty)
        XCTAssertEqual(spoolNames(), [])
    }

    @MainActor
    func test_aQueueOfPhotos_comesBackAtLaunch_asTheIPhoneQueuesThem() async throws {
        let before = try await makeQueue { (settings: ScanSettings) -> ScanSettings in
            TaskCatalog.apply(.photos, to: settings)
        }
        let ids: [UUID] = before.scannedPages.map(\.id)
        let after = makeState()
        try await waitUntil(timeout: 30) { !after.isBusy }
        XCTAssertEqual(after.scannedPages.map(\.id), ids)
        XCTAssertEqual(after.activeTask, .photos)
    }

    @MainActor
    func test_aPageWhoseFileIsGone_isLeftOut_theOthersComeBack() async throws {
        let before = try await makeQueue()
        let kept: ScannedPage = before.scannedPages[1]
        try FileManager.default.removeItem(at: before.scannedPages[0].fileURL!)
        let after = makeState()
        try await waitUntil(timeout: 30) { !after.isBusy }
        XCTAssertEqual(after.scannedPages.map(\.id), [kept.id])
        XCTAssertEqual(after.statusMessage, "Pages back from last time: 1 of 2.")
        XCTAssertTrue(spoolNames().contains(kept.fileURL!.lastPathComponent))
    }

    @MainActor
    func test_aPageKeptInMemory_isLeftOut_theOthersComeBack() async throws {
        let before = try await makeQueue()
        let spooled: [UUID] = before.scannedPages.map(\.id)
        // No file in the spool, as when its spill failed.
        before.scannedPages.append(recordPage())
        before.writeQueueRecord()
        let after = makeState()
        try await waitUntil(timeout: 30) { !after.isBusy }
        XCTAssertEqual(after.scannedPages.map(\.id), spooled)
        XCTAssertEqual(after.statusMessage, "Pages back from last time: 2 of 3.")
    }

    @MainActor
    func test_aQueueWhoseFilesAreAllGone_isEmptiedAtLaunch() async throws {
        let before = try await makeQueue()
        for page in before.scannedPages {
            try FileManager.default.removeItem(at: page.fileURL!)
        }
        let after = makeState()
        XCTAssertFalse(after.isBusy)
        XCTAssertTrue(after.scannedPages.isEmpty)
        XCTAssertEqual(spoolNames(), [])
    }

    @MainActor
    func test_goingToTheBackground_writesTheRecordAtOnce() async throws {
        let lifecycle = RecordLifecycle()
        let state = AppState(presetStore: PresetStore(directory: folder), orientationScorer: RecordScorer(),
                             barcodeReader: RecordBarcodes(), lifecycle: lifecycle, files: files(keepsQueue: true))
        state.queueRecordDelay = 60_000_000_000
        XCTAssertTrue(state.startTask(.document))
        XCTAssertTrue(state.ingest([recordPage()], source: .photo))
        try await waitUntil(timeout: 60) { !state.isBusy && state.scannedPages.count == 1 }
        let record: URL = spool.appendingPathComponent(QueueRecord.fileName)
        try FileManager.default.removeItem(at: record)
        state.scannedPages = state.scannedPages
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.path), "The record waits for its delay")
        lifecycle.sendWillTerminate()
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.path))
    }

    @MainActor
    func test_anOperationThatQueuedPages_writesTheRecordBeforeItEnds() async throws {
        let state = AppState(presetStore: PresetStore(directory: folder), orientationScorer: RecordScorer(),
                             barcodeReader: RecordBarcodes(), files: files(keepsQueue: true))
        state.queueRecordDelay = 60_000_000_000
        XCTAssertTrue(state.startTask(.document))
        XCTAssertTrue(state.ingest([recordPage()], source: .photo))
        try await waitUntil(timeout: 60) { !state.isBusy && state.scannedPages.count == 1 }
        let record: URL = spool.appendingPathComponent(QueueRecord.fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.path))
    }

    @MainActor
    func test_quittingWhereTheQueueIsDiscarded_emptiesTheSpool() async throws {
        let lifecycle = RecordLifecycle()
        var kept: AppStateFiles = files(keepsQueue: true)
        kept.discardsQueueAtQuit = true
        let state = AppState(presetStore: PresetStore(directory: folder), orientationScorer: RecordScorer(),
                             barcodeReader: RecordBarcodes(), lifecycle: lifecycle, files: kept)
        XCTAssertTrue(state.startTask(.document))
        XCTAssertTrue(state.ingest([recordPage(), recordPage()], source: .photo))
        try await waitUntil(timeout: 60) { !state.isBusy && state.scannedPages.count == 2 }
        state.writeQueueRecord()
        XCTAssertFalse(spoolNames().isEmpty)
        lifecycle.sendWillTerminate()
        XCTAssertEqual(spoolNames(), [])
    }

    @MainActor
    func test_withoutKeepingTheQueue_theSpoolIsEmptiedAsBefore() async throws {
        _ = try await makeQueue()
        let after = makeState(keepsQueue: false)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(after.scannedPages.isEmpty)
        XCTAssertEqual(spoolNames(), [])
    }

    /// Rewrites the record `makeQueue` wrote through `change`, as an older or newer version would have left it.
    private func editRecord(_ change: (inout [String: Any], inout [[String: Any]]) -> Void) throws {
        let url: URL = spool.appendingPathComponent(QueueRecord.fileName)
        var record = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var pages = try XCTUnwrap(record["pages"] as? [[String: Any]])
        change(&record, &pages)
        record["pages"] = pages
        try JSONSerialization.data(withJSONObject: record).write(to: url)
    }

    @MainActor
    func test_aPageWithAnUnknownValue_isLeftOut_andTheOthersComeBack() async throws {
        let before = try await makeQueue()
        let kept: ScannedPage = before.scannedPages[0]
        try editRecord { _, pages in
            pages[0]["fromANewerVersion"] = true
            pages[1]["colorMode"] = "a mode from a newer version"
        }
        let after = makeState()
        try await waitUntil(timeout: 30) { !after.isBusy }
        XCTAssertEqual(after.scannedPages.map(\.id), [kept.id])
        XCTAssertEqual(after.statusMessage, "Pages back from last time: 1 of 2.")
    }

    @MainActor
    func test_aRecordFromAnOlderVersion_keepsItsReadablePages() async throws {
        let before = try await makeQueue()
        let kept: ScannedPage = before.scannedPages[0]
        try editRecord { record, pages in
            record["queued"] = nil
            pages[1]["dpi"] = nil
        }
        let after = makeState()
        try await waitUntil(timeout: 30) { !after.isBusy }
        XCTAssertEqual(after.scannedPages.map(\.id), [kept.id])
        XCTAssertEqual(after.statusMessage, "Pages back from last time: 1 of 2.")
    }

    @MainActor
    func test_aRecordThatCannotBeRead_leavesTheSpoolAlone() async throws {
        _ = try await makeQueue()
        let names: [String] = spoolNames()
        try Data("{".utf8).write(to: spool.appendingPathComponent(QueueRecord.fileName))
        let after = makeState()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(after.scannedPages.isEmpty)
        XCTAssertEqual(spoolNames(), names)
        XCTAssertEqual(after.errorMessage, "The pages kept from last time could not be read.")
    }

    @MainActor
    func test_aRecordWhosePagesAllFail_leavesTheSpoolAlone() async throws {
        _ = try await makeQueue()
        let names: [String] = spoolNames()
        try editRecord { _, pages in
            for index in pages.indices {
                pages[index]["colorMode"] = "a mode from a newer version"
            }
        }
        let after = makeState()
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(after.scannedPages.isEmpty)
        XCTAssertEqual(spoolNames(), names)
        XCTAssertEqual(after.errorMessage, "The pages kept from last time could not be read.")
    }

    func test_aRecordWithoutTheQueuedCount_stillDecodes() throws {
        let record: QueueRecord = try JSONDecoder().decode(QueueRecord.self, from: Data(#"{"pages":[]}"#.utf8))
        XCTAssertNil(record.queued)
    }

    func test_aRecordWithoutTheSessionFields_decodesThemAsNil() throws {
        let record: QueueRecord = try JSONDecoder().decode(QueueRecord.self, from: Data(#"{"pages":[],"queued":0}"#.utf8))
        XCTAssertNil(record.taskId)
        XCTAssertNil(record.cameraSides)
        XCTAssertNil(record.flowCaptures)
        XCTAssertNil(record.flowStep)
        XCTAssertNil(record.newDocumentPending)
        XCTAssertNil(record.appendBookmark)
    }

    func test_theSessionFields_roundTrip() throws {
        var sides = CameraSides(mode: .frontsFirst)
        let front: UUID = UUID()
        sides.took([front])
        sides.startBacks()
        var record = QueueRecord([], spool: folder)
        record.taskId = "twoSided"
        record.cameraSides = sides
        record.flowCaptures = ["scan": [front]]
        record.flowStep = 1
        record.newDocumentPending = true
        record.appendBookmark = Data([1, 2, 3])
        let back: QueueRecord = try JSONDecoder().decode(QueueRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(back.taskId, "twoSided")
        XCTAssertEqual(back.cameraSides, sides)
        XCTAssertEqual(back.flowCaptures, ["scan": [front]])
        XCTAssertEqual(back.flowStep, 1)
        XCTAssertEqual(back.newDocumentPending, true)
        XCTAssertEqual(back.appendBookmark, Data([1, 2, 3]))
    }

    @MainActor
    func test_theCamerasFrontsAndTheAppendTarget_comeBackWithTheQueue() async throws {
        let before = makeState()
        before.bookmarkAppendTarget = { (url: URL) -> Data? in Data(url.path.utf8) }
        XCTAssertTrue(before.startTask(.twoSided))
        before.settings.taskOptions.cameraFrontsFirst = true
        before.settings.destinationPath = folder.path
        XCTAssertTrue(before.ingest([recordPage(), recordPage()], source: .photo))
        try await waitUntil(timeout: 60) { !before.isBusy && before.scannedPages.count == 2 }
        let fronts: [UUID] = before.scannedPages.map(\.id)
        before.startCameraBacks()
        XCTAssertEqual(before.cameraSides?.fronts, fronts)
        let target: URL = folder.appendingPathComponent("Contract.pdf")
        before.setAppendTarget(target)
        before.writeQueueRecord()
        // The settings' own write lands 0.4 s after they change; this one comes after it.
        try await Task.sleep(nanoseconds: 600_000_000)
        SettingsStore.save(before.settings, directory: folder)

        let after = makeState()
        after.resolveAppendTarget = { (bookmark: Data) -> URL? in
            URL(fileURLWithPath: String(decoding: bookmark, as: UTF8.self))
        }
        try await waitUntil(timeout: 30) { !after.isBusy }
        XCTAssertEqual(after.cameraSides?.fronts, fronts)
        XCTAssertEqual(after.cameraSides?.next, .back)
        XCTAssertEqual(after.taskFlow?.allCaptures, before.taskFlow?.allCaptures)
        XCTAssertEqual(after.appendTarget?.path, target.path)
    }

    func test_onlyTheIPhonesFiles_keepTheQueue_inApplicationSupport() {
        XCTAssertFalse(AppStateFiles.standard.keepsQueue)
        let kept = AppStateFiles.keepingQueue
        XCTAssertTrue(kept.keepsQueue)
        XCTAssertEqual(kept.settingsDirectory, AppStateFiles.standard.settingsDirectory)
        XCTAssertEqual(kept.spoolDirectory, StoreFiles.defaultDirectory.appendingPathComponent("Pages", isDirectory: true))
    }
}
