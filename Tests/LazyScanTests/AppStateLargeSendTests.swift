import CoreGraphics
import Foundation
import XCTest
@testable import LazyScanKit

// Email and share of files over `SaveActions.largeAttachmentBytes` (AppState+LargeSend.swift). Swift only,
// as `AppStateUndoTests`.

@MainActor
private final class MailFileActions: FileActionService {
    private(set) var composed: [[URL]] = []
    private(set) var shared: [[URL]] = []
    private(set) var opened: [URL] = []

    func open(_ url: URL) throws { opened.append(url) }
    func openWith(_ url: URL) throws {}
    func reveal(_ urls: [URL]) {}
    func sendProbe(for urls: [URL]) -> SendProbe { SendProbe(canCompose: true, canShare: true) }
    func share(_ urls: [URL], title: String) throws { shared.append(urls) }
    func composeEmail(_ urls: [URL]) throws { composed.append(urls) }
    func copy(_ content: ClipboardContent) throws {}
    func copyText(_ text: String) throws {}
}

private struct LargeScorer: OrientationScorer {
    var isAvailable: Bool { false }

    func score(_ image: RgbaImage) throws -> OrientationScore {
        OrientationScore.none
    }
}

private struct LargeBarcodes: BarcodeReader {
    var isAvailable: Bool { false }

    func read(_ image: GrayImage) throws -> [BarcodeReading] {
        []
    }
}

final class AppStateLargeSendTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppStateLargeSendTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        // The settings are written 0.4 s after they change: let that write land before the folder goes.
        try await Task.sleep(nanoseconds: 600_000_000)
        try? FileManager.default.removeItem(at: folder)
    }

    private var saveFolder: URL { folder.appendingPathComponent("Saved", isDirectory: true) }

    @MainActor
    private func makeState(_ files: MailFileActions) -> AppState {
        let state = AppState(presetStore: PresetStore(directory: folder), fileActions: files,
                             orientationScorer: LargeScorer(), barcodeReader: LargeBarcodes(),
                             files: AppStateFiles.all(in: folder))
        state.platform = .ios
        state.keepsSavedForUndo = true
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
        return state
    }

    @MainActor
    private func finish(_ state: AppState) async throws {
        let deadline = Date().addingTimeInterval(60)
        while state.isBusy {
            if Date() > deadline { return XCTFail("Timed out") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNil(state.errorMessage)
    }

    private func file(bytes: Int, named name: String = "Big.pdf") throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(count: bytes).write(to: url)
        return url
    }

    @MainActor
    func test_smallFiles_andTheLimitItself_goStraightToMail() throws {
        let files = MailFileActions()
        let state = makeState(files)
        let atLimit = try file(bytes: Int(SaveActions.largeAttachmentBytes))
        XCTAssertTrue(state.runFileAction(.email, urls: [atLimit]))
        XCTAssertNil(state.largeSendNotice)
        XCTAssertEqual(files.composed, [[atLimit]])
    }

    @MainActor
    func test_largeFiles_areHeldBack_withTheirSize_andSentOnSendAnyway() throws {
        let files = MailFileActions()
        let state = makeState(files)
        let big = try file(bytes: Int(SaveActions.largeAttachmentBytes) + 1)
        XCTAssertFalse(state.runFileAction(.email, urls: [big]))
        XCTAssertFalse(state.runFileAction(.share, urls: [big]))
        XCTAssertTrue(files.composed.isEmpty)
        XCTAssertTrue(files.shared.isEmpty)
        let notice = try XCTUnwrap(state.largeSendNotice)
        XCTAssertEqual(notice.action, .share)
        XCTAssertEqual(notice.bytes, SaveActions.largeAttachmentBytes + 1)
        XCTAssertFalse(notice.canSaveSmaller)
        XCTAssertEqual(notice.title, "Large file")
        XCTAssertTrue(notice.message.hasPrefix("This file is 20"), notice.message)
        XCTAssertTrue(notice.message.hasSuffix("attachments over 20 MB."), notice.message)

        state.sendLargeAnyway(notice)
        XCTAssertNil(state.largeSendNotice)
        XCTAssertEqual(files.shared, [[big]])
    }

    @MainActor
    func test_theSizeIsTheSumOfTheFiles_andOtherActionsAreNotHeldBack() throws {
        let files = MailFileActions()
        let state = makeState(files)
        let half = Int(SaveActions.largeAttachmentBytes) / 2 + 1
        let first = try file(bytes: half, named: "A.pdf")
        let second = try file(bytes: half, named: "B.pdf")
        XCTAssertFalse(state.runFileAction(.email, urls: [first, second]))
        let notice = try XCTUnwrap(state.largeSendNotice)
        XCTAssertEqual(notice.title, "Large files")
        XCTAssertTrue(notice.message.hasPrefix("These files are"), notice.message)
        state.largeSendNotice = nil
        XCTAssertTrue(state.runFileAction(.open, urls: [first]))
        XCTAssertNil(state.largeSendNotice)
        XCTAssertEqual(files.opened, [first])
    }

    @MainActor
    func test_saveSmaller_savesTheHeldPagesAgain_andSendsTheNewFile() async throws {
        let files = MailFileActions()
        let state = makeState(files)
        var pages: [ScannedPage] = []
        for _ in 0..<2 {
            let context = try XCTUnwrap(CGContext(data: nil, width: 300, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                                  space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
            pages.append(ScannedPage(image: try XCTUnwrap(context.makeImage()), dpi: 50, colorMode: .color))
        }
        XCTAssertTrue(state.ingest(pages, source: .photo))
        try await finish(state)
        state.savePDF()
        try await finish(state)
        let pdf = try XCTUnwrap(state.lastSavedURLs.first)

        // Make the saved file look big, as a long colour stack would.
        try Data(count: Int(SaveActions.largeAttachmentBytes) + 1).write(to: pdf)
        state.savedUndo?.stamps[pdf] = FileStamp(of: pdf)
        XCTAssertFalse(state.runFileAction(.email, urls: [pdf]))
        let notice = try XCTUnwrap(state.largeSendNotice)
        XCTAssertTrue(notice.canSaveSmaller)

        state.saveSmaller(notice)
        try await finish(state)
        XCTAssertNil(state.largeSendNotice)
        XCTAssertEqual(files.composed.count, 1)
        let sent = try XCTUnwrap(files.composed.first?.first)
        XCTAssertLessThan(state.attachmentBytes(of: [sent]), SaveActions.largeAttachmentBytes)
        XCTAssertTrue(state.statusMessage.hasPrefix("Saved smaller:"), state.statusMessage)
        XCTAssertEqual(state.settings.output.pdfSize, .standard)
        XCTAssertEqual(state.savedUndo?.smaller, true)
        XCTAssertTrue(state.scannedPages.isEmpty)
    }

    @MainActor
    func test_theOpenNotice_dropsSaveSmaller_whenTheHeldSaveIsDiscarded() async throws {
        let files = MailFileActions()
        let state = makeState(files)
        let context = try XCTUnwrap(CGContext(data: nil, width: 300, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
        let page = ScannedPage(image: try XCTUnwrap(context.makeImage()), dpi: 50, colorMode: .color)
        XCTAssertTrue(state.ingest([page], source: .photo))
        try await finish(state)
        state.savePDF()
        try await finish(state)
        let pdf = try XCTUnwrap(state.lastSavedURLs.first)
        try Data(count: Int(SaveActions.largeAttachmentBytes) + 1).write(to: pdf)
        state.savedUndo?.stamps[pdf] = FileStamp(of: pdf)
        XCTAssertFalse(state.runFileAction(.email, urls: [pdf]))
        XCTAssertEqual(state.largeSendNotice?.canSaveSmaller, true)

        state.discardSavedUndo()
        XCTAssertEqual(state.largeSendNotice?.canSaveSmaller, false)
        XCTAssertEqual(state.largeSendNotice?.urls, [pdf])
    }

    @MainActor
    func test_largeFiles_areHeldBack_onTheMac() throws {
        let files = MailFileActions()
        let state = makeState(files)
        state.platform = .mac
        let big = try file(bytes: Int(SaveActions.largeAttachmentBytes) + 1)
        XCTAssertFalse(state.runFileAction(.email, urls: [big]))
        XCTAssertEqual(state.largeSendNotice?.urls, [big])
        XCTAssertTrue(files.composed.isEmpty)
    }

    @MainActor
    func test_saveSmaller_isNotOffered_forFilesNoSaveIsHolding() throws {
        let files = MailFileActions()
        let state = makeState(files)
        let big = try file(bytes: Int(SaveActions.largeAttachmentBytes) + 1)
        XCTAssertFalse(state.runFileAction(.email, urls: [big]))
        let notice = try XCTUnwrap(state.largeSendNotice)
        XCTAssertFalse(notice.canSaveSmaller)
        state.saveSmaller(notice)
        XCTAssertFalse(state.isBusy)
        XCTAssertNil(state.smallerSend)
    }
}
