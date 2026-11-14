#if os(iOS)
import CoreGraphics
import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import LazyScanIOS
@testable import LazyScanKit

// The presets, the scans of this session and the saved files without a screen (I15): presets saved,
// renamed, applied and deleted through presets.json in a folder of the test's own; the history's rows;
// the save folder listed newest first with the last save marked, and its files' actions.

/// Whether a closure ran.
@MainActor
private final class LibraryFlag {
    var value: Bool = false
}

/// The addresses the file actions asked the system to open.
@MainActor
private final class LibraryOpened {
    var urls: [URL] = []
}

/// A photo of a sheet on a table, for an import that waits on the corner editor.
private func librarySheetPNG() -> Data {
    let corners: [CGPoint] = [CGPoint(x: 150, y: 80), CGPoint(x: 350, y: 80), CGPoint(x: 350, y: 363),
                              CGPoint(x: 150, y: 363)]
    let photo: CGImage = ImportTestSupport.sheetPhoto(width: 600, height: 450, corners: corners)
    return ImportTestSupport.file(UTType.png, images: [photo])
}

/// A page search that is never sure, so each photo waits on the corner editor.
private func unsureFinder() -> @Sendable (RgbaImage) -> IOSFoundPage {
    let corners = Quad(topLeft: CGPoint(x: 150, y: 80), topRight: CGPoint(x: 350, y: 80),
                       bottomRight: CGPoint(x: 350, y: 363), bottomLeft: CGPoint(x: 150, y: 363))
    let found = IOSFoundPage(corners: corners, reason: .unsure, byModel: false)
    return { (_: RgbaImage) -> IOSFoundPage in
        found
    }
}

/// A small picture of the test's own.
private func libraryPicture(width: Int, height: Int) -> CGImage {
    let context: CGContext = ImportTestSupport.context(width: width, height: height)
    context.setFillColor(CGColor(srgbRed: 0.9, green: 0.9, blue: 0.85, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

final class IOSLibraryTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = try ImportTestSupport.makeFolder("library")
    }

    override func tearDownWithError() throws {
        if let folder {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    // MARK: Presets

    @MainActor
    func test_presets_savedRenamedAppliedAndDeleted_throughPresetsJSON() throws {
        let state: AppState = ImportTestSupport.makeState(in: folder)
        // Printer mode, where Receipts is a kind of its own: camera mode applies it as Document (IOSFlowTests).
        let suite: String = "presets.\(UUID().uuidString)"
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(IOSScanMode.printer.rawValue, forKey: IOSShell.scanModeKey)
        let model: IOSPresetsModel = IOSPresetsModel(state: state, importer: IOSImportSession(state: state),
                                                     defaults: defaults)
        XCTAssertTrue(model.rows.isEmpty, "A first run has no presets")
        XCTAssertFalse(model.save(named: "   "))
        XCTAssertTrue(state.presets.isEmpty)

        var receipts: ScanSettings = TaskCatalog.apply(.receipt, to: state.settings)
        receipts.resolution = 600
        state.settings = receipts
        XCTAssertTrue(model.save(named: "  Receipts 600 "))
        let rows: [IOSPresetRow] = model.rows
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].name, "Receipts 600")
        XCTAssertEqual(rows[0].taskTitle, IOSScanKind.receipts.title)
        XCTAssertEqual(rows[0].summary, TaskCatalog.summary(receipts))
        XCTAssertEqual(rows[0].symbol, IOSScanKind.receipts.symbol)
        XCTAssertEqual(rows[0].accessibilityLabel, "Receipts 600 preset")
        let id: UUID = rows[0].id

        var stored: [Preset] = PresetStore(directory: folder).load()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].name, "Receipts 600")
        XCTAssertEqual(stored[0].settings.resolution, 600)

        XCTAssertFalse(model.rename(id, to: "  "))
        XCTAssertFalse(model.rename(UUID(), to: "Nobody"))
        XCTAssertTrue(model.rename(id, to: " Till slips "))
        stored = PresetStore(directory: folder).load()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].name, "Till slips")
        XCTAssertEqual(stored[0].id, id)

        var plain: ScanSettings = state.settings
        plain.taskId = nil
        plain.resolution = 150
        state.settings = plain
        // A PDF picked on the start screen is forgotten: the preset's pages are not added to it.
        state.setAppendTarget(folder.appendingPathComponent("Contract.pdf"))
        let applied: LibraryFlag = LibraryFlag()
        let outcome: IOSPresetApply = model.apply(id) {
            applied.value = true
        }
        XCTAssertEqual(outcome, IOSPresetApply.applied)
        XCTAssertTrue(applied.value)
        XCTAssertEqual(state.settings.resolution, 600)
        XCTAssertEqual(state.activeTask, ScanTask.receipt)
        XCTAssertNil(state.appendTarget)
        XCTAssertTrue(state.statusMessage.contains("Till slips"), state.statusMessage)
        let missing: IOSPresetApply = model.apply(UUID()) {}
        XCTAssertEqual(missing, IOSPresetApply.refused)

        model.delete(id)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertTrue(PresetStore(directory: folder).load().isEmpty)
    }

    @MainActor
    func test_presetRows_areNamedByThePhonesKinds_notTheDesktopsTasks() {
        let state: AppState = ImportTestSupport.makeState(in: folder)
        let model: IOSPresetsModel = IOSPresetsModel(state: state, importer: IOSImportSession(state: state))
        let base: ScanSettings = state.settings
        let tasks: [ScanTask] = [.document, .twoSided, .email, .photoRestore, .quickScan]
        for (index, task) in tasks.enumerated() {
            state.settings = TaskCatalog.apply(task, to: base)
            XCTAssertTrue(model.save(named: "Preset \(index)"))
        }
        let rows: [IOSPresetRow] = model.rows
        XCTAssertEqual(rows.map(\.taskTitle), ["Document", "Document", "Document", "Photos", "Text"])
        // An Email preset keeps the Document's icon, not an envelope.
        let kinds: [IOSScanKind] = [.document, .document, .document, .photos, .text]
        XCTAssertEqual(rows.map(\.symbol), kinds.map(\.symbol))
        XCTAssertEqual(rows[1].accessibilityHint, "Preset for Document. \(rows[1].summary).")
    }

    @MainActor
    func test_aPresetTurnedOverByHand_takesBothSides_withNoScanner() throws {
        let state: AppState = ImportTestSupport.makeState(in: folder)
        let model: IOSPresetsModel = IOSPresetsModel(state: state, importer: IOSImportSession(state: state))
        var feeder: ScanSettings = TaskCatalog.apply(.document, to: state.settings)
        feeder.source = .documentFeeder
        feeder.duplex = .manual
        state.settings = feeder
        XCTAssertTrue(model.save(named: "Stack by hand"))
        let id: UUID = try XCTUnwrap(model.rows.first?.id)
        state.settings = TaskCatalog.apply(.document, to: state.settings)
        XCTAssertNil(state.selectedDeviceID)

        XCTAssertEqual(model.apply(id) {}, IOSPresetApply.applied)
        XCTAssertEqual(state.settings.source, .documentFeeder)
        XCTAssertEqual(state.settings.duplex, .both)
        XCTAssertFalse(state.isTurningOverByHand)
        XCTAssertTrue(state.canIngest)
    }

    @MainActor
    func test_presets_notAppliedWhileAnImportRuns() async throws {
        let state: AppState = ImportTestSupport.makeState(in: folder)
        let importer: IOSImportSession = IOSImportSession(state: state, finder: unsureFinder())
        let model: IOSPresetsModel = IOSPresetsModel(state: state, importer: importer)
        var fine: ScanSettings = state.settings
        fine.resolution = 600
        state.settings = fine
        XCTAssertTrue(model.save(named: "Fine"))
        let id: UUID = try XCTUnwrap(model.rows.first?.id)
        var plain: ScanSettings = state.settings
        plain.resolution = 150
        state.settings = plain

        let item = IOSImportItem(name: "sheet.png", data: librarySheetPNG(), kind: .image)
        let importing: Task<IOSImportOutcome, Never> = Task { @MainActor in
            await importer.importItems([item])
        }
        try await ImportTestSupport.waitUntil(timeout: 60) { importer.cornerRequest != nil }
        XCTAssertTrue(importer.isImporting)
        let applied: LibraryFlag = LibraryFlag()
        let during: IOSPresetApply = model.apply(id) {
            applied.value = true
        }
        XCTAssertEqual(during, IOSPresetApply.refused)
        XCTAssertFalse(applied.value)
        XCTAssertEqual(state.settings.resolution, 150)

        importer.answer(PhotoCornersAnswer.skip)
        _ = await importing.value
        XCTAssertFalse(importer.isImporting)
        let after: IOSPresetApply = model.apply(id) {
            applied.value = true
        }
        XCTAssertEqual(after, IOSPresetApply.applied)
        XCTAssertTrue(applied.value)
        XCTAssertEqual(state.settings.resolution, 600)
    }

    @MainActor
    func test_presets_thatDoNotCollectPages_waitForTheQueuedPages() async throws {
        let state: AppState = ImportTestSupport.makeState(in: folder)
        let model: IOSPresetsModel = IOSPresetsModel(state: state, importer: IOSImportSession(state: state))
        let document: ScanSettings = state.settings
        state.settings = TaskCatalog.apply(.idCard, to: document)
        XCTAssertTrue(model.save(named: "Card"))
        var single: ScanSettings = TaskCatalog.apply(.document, to: document)
        single.documentMultiPage = false
        state.settings = single
        XCTAssertTrue(model.save(named: "One by one"))
        state.settings = TaskCatalog.apply(.book, to: document)
        XCTAssertTrue(model.save(named: "Book"))
        let rows: [IOSPresetRow] = model.rows
        XCTAssertEqual(rows.map(\.name), ["Card", "One by one", "Book"])
        let card: UUID = rows[0].id
        state.settings = document

        let pages: [ScannedPage] = [0, 1].map { (_: Int) -> ScannedPage in
            ScannedPage(image: libraryPicture(width: 120, height: 160), dpi: 60, colorMode: .color)
        }
        XCTAssertTrue(state.ingest(pages, source: .photo))
        try await ImportTestSupport.waitUntil(timeout: 60) { !state.isBusy && state.scannedPages.count == 2 }
        let files: [URL] = state.scannedPages.compactMap(\.fileURL)
        XCTAssertEqual(files.count, 2)

        let applied: LibraryFlag = LibraryFlag()
        let idCard: IOSPresetApply = model.apply(card) {
            applied.value = true
        }
        XCTAssertEqual(idCard, IOSPresetApply.waitsForPages("Card"))
        // Document with Collect pages before saving off has no Save for a queue either.
        let oneByOne: IOSPresetApply = model.apply(rows[1].id) {
            applied.value = true
        }
        XCTAssertEqual(oneByOne, IOSPresetApply.waitsForPages("One by one"))
        XCTAssertFalse(applied.value)
        XCTAssertEqual(IOSShell.shownKind(state.settings), IOSScanKind.document)
        XCTAssertTrue(state.settings.documentMultiPage)
        XCTAssertEqual(state.scannedPages.count, 2)

        let book: IOSPresetApply = model.apply(rows[2].id) {}
        XCTAssertEqual(book, IOSPresetApply.applied)
        XCTAssertEqual(state.activeTask, ScanTask.book)
        XCTAssertEqual(state.scannedPages.count, 2)

        // No preset while a share or a send reads the pages.
        state.queueReaders = 1
        let reading: IOSPresetApply = model.apply(card, discardingPages: true) {
            applied.value = true
        }
        XCTAssertEqual(reading, IOSPresetApply.refused)
        XCTAssertEqual(state.scannedPages.count, 2)
        state.queueReaders = 0

        let discarded: IOSPresetApply = model.apply(card, discardingPages: true) {
            applied.value = true
        }
        XCTAssertEqual(discarded, IOSPresetApply.applied)
        XCTAssertTrue(applied.value)
        XCTAssertEqual(state.activeTask, ScanTask.idCard)
        XCTAssertTrue(state.scannedPages.isEmpty)
        for file in files {
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), file.lastPathComponent)
        }
    }

    // MARK: Scans of this session

    func test_history_rows_sayModeResolutionAndTime() throws {
        var calendar: Calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let locale: Locale = Locale(identifier: "en_US")
        var parts: DateComponents = DateComponents()
        parts.year = 2026
        parts.month = 10
        parts.day = 20
        parts.hour = 16
        parts.minute = 23
        let now: Date = calendar.date(from: parts)!
        parts.day = 19
        parts.hour = 9
        let yesterday: Date = calendar.date(from: parts)!
        let picture: CGImage = libraryPicture(width: 4, height: 6)
        let today: ScanHistoryEntry = ScanHistoryEntry(date: now, intent: .document, dpi: 300, thumbnail: picture,
                                                       pixelSize: CGSize(width: 2550, height: 3510))
        let earlier: ScanHistoryEntry = ScanHistoryEntry(date: yesterday, intent: .photo, dpi: 600, thumbnail: picture,
                                                         pixelSize: CGSize(width: 1800, height: 1200))

        let rows: [IOSHistoryRow] = IOSHistory.rows([today, earlier], now: now, calendar: calendar, locale: locale)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].id, today.id)
        XCTAssertEqual(rows[0].title, "Document \u{00B7} 300 dpi")
        XCTAssertEqual(rows[1].title, "Photos \u{00B7} 600 dpi")
        XCTAssertEqual(rows[0].symbol, "doc.text")
        XCTAssertEqual(rows[1].symbol, "photo")
        XCTAssertTrue(rows[0].time.contains("4:23"), rows[0].time)
        XCTAssertFalse(rows[0].time.contains("Oct"), rows[0].time)
        XCTAssertTrue(rows[1].time.contains("Oct 19"), rows[1].time)
        XCTAssertTrue(rows[0].accessibilityLabel.hasPrefix("Document scan, 300 dpi, 2550 by 3510 pixels, "),
                      rows[0].accessibilityLabel)
        XCTAssertTrue(rows[1].accessibilityLabel.hasPrefix("Photo scan, 600 dpi, 1800 by 1200 pixels, "),
                      rows[1].accessibilityLabel)
        XCTAssertEqual(IOSHistory.countText(1), "1 scan")
        XCTAssertEqual(IOSHistory.countText(13), "13 scans")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let kit = root.appendingPathComponent("l10n/out/ios/tr.lproj/Kit.strings")
        let table = try XCTUnwrap(NSDictionary(contentsOf: kit) as? [String: String])
        L10n.withTable(table, language: "tr") {
            XCTAssertEqual(IOSHistory.countText(1), "1 tarama")
            XCTAssertEqual(IOSHistory.countText(1234), "1.234 tarama")
        }
        XCTAssertTrue(IOSHistory.rows([], now: now).isEmpty)
    }

    @MainActor
    func test_history_ofThisSession_listsAPageTaken() async throws {
        let state: AppState = ImportTestSupport.makeState(in: folder)
        XCTAssertTrue(IOSHistory.rows(state.scanHistory, now: Date()).isEmpty)
        let page: ScannedPage = ScannedPage(image: libraryPicture(width: 120, height: 160), dpi: 60, colorMode: .color)
        XCTAssertTrue(state.ingest([page], source: .photo))
        try await ImportTestSupport.waitUntil(timeout: 60) { state.scanHistory.count == 1 }
        let rows: [IOSHistoryRow] = IOSHistory.rows(state.scanHistory, now: Date())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.title, "Document \u{00B7} 60 dpi")
    }

    @MainActor
    func test_history_dropsAPageRemovedFromTheQueue_andClearEmptiesIt() async throws {
        let state: AppState = ImportTestSupport.makeState(in: folder)
        let pages: [ScannedPage] = [ScannedPage(image: libraryPicture(width: 120, height: 160), dpi: 60, colorMode: .color),
                                    ScannedPage(image: libraryPicture(width: 120, height: 160), dpi: 60, colorMode: .color)]
        XCTAssertTrue(state.ingest(pages, source: .photo))
        try await ImportTestSupport.waitUntil(timeout: 60) { !state.isBusy && state.scanHistory.count == 2 }
        defer { state.deleteSpoolFiles(of: state.scannedPages) }
        state.removePage(id: pages[0].id)
        XCTAssertEqual(state.scanHistory.map(\.pageID), [pages[1].id])
        state.clearHistory()
        XCTAssertTrue(state.scanHistory.isEmpty)
    }

    // MARK: Saved files

    func test_savedFiles_listTheSaveFolder_newestFirst_theLastSaveMarked() throws {
        let saved: URL = folder.appendingPathComponent("Saved", isDirectory: true)
        try FileManager.default.createDirectory(at: saved, withIntermediateDirectories: true)
        let now: Date = Date()
        let names: [String] = ["a.pdf", "b.jpg", "c.txt", "d.xyz", ".hidden.pdf"]
        let ages: [Double] = [300, 100, 200, 50, 10]
        var index: Int = 0
        while index < names.count {
            let url: URL = saved.appendingPathComponent(names[index])
            try Data("file \(index)".utf8).write(to: url)
            let date: Date = now.addingTimeInterval(-ages[index])
            try FileManager.default.setAttributes([FileAttributeKey.modificationDate: date], ofItemAtPath: url.path)
            index += 1
        }
        try FileManager.default.createDirectory(at: saved.appendingPathComponent("e.pdf", isDirectory: true),
                                                withIntermediateDirectories: true)

        let listed: IOSSavedFolder = IOSSavedFiles.list(in: saved, justSaved: [saved.appendingPathComponent("b.jpg")])
        XCTAssertFalse(listed.failed)
        var listedNames: [String] = []
        var marks: [Bool] = []
        for file in listed.files {
            listedNames.append(file.name)
            marks.append(file.isNew)
        }
        XCTAssertEqual(listedNames, ["b.jpg", "c.txt", "a.pdf"])
        XCTAssertEqual(marks, [true, false, false])
        XCTAssertEqual(listed.files[0].symbol, "photo")
        XCTAssertEqual(listed.files[1].symbol, "doc.text")
        XCTAssertEqual(listed.files[2].symbol, "doc.richtext")
        let detail: String = listed.files[2].detail(pages: nil)
        XCTAssertTrue(detail.contains("\u{00B7}"), detail)

        let missing: IOSSavedFolder = IOSSavedFiles.list(in: folder.appendingPathComponent("Nowhere", isDirectory: true),
                                                         justSaved: [])
        XCTAssertTrue(missing.files.isEmpty)
        XCTAssertFalse(missing.failed, "A folder not made yet is empty, not a failure")
        let notAFolder: IOSSavedFolder = IOSSavedFiles.list(in: saved.appendingPathComponent("c.txt"), justSaved: [])
        XCTAssertTrue(notAFolder.failed)

        XCTAssertEqual(IOSSavedFiles.moreActions(lazyPrint: false), [FileAction.open, FileAction.email, FileAction.copy])
        XCTAssertEqual(IOSSavedFiles.moreActions(lazyPrint: true),
                       [FileAction.open, FileAction.email, FileAction.lazyPrint, FileAction.copy])
        XCTAssertEqual(IOSSavedFiles.label(FileAction.reveal), "Show in Files")
        XCTAssertEqual(IOSSavedFiles.label(FileAction.copy), FileAction.copy.label)
    }

    func test_savedFiles_groups_todayThisWeekEarlier() throws {
        var calendar: Calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        calendar.firstWeekday = 2
        // A Thursday; the week began on Monday the 9th.
        let now: Date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 15)))
        func file(_ name: String, _ day: Int, month: Int = 11) throws -> IOSSavedFile {
            let date: Date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 9)))
            return IOSSavedFile(url: URL(fileURLWithPath: "/tmp/\(name)"), modified: date, byteCount: 1000, isNew: false)
        }
        let files: [IOSSavedFile] = [try file("a.pdf", 12), try file("b.pdf", 11), try file("c.pdf", 9),
                                     try file("d.pdf", 8), try file("e.pdf", 2, month: 10)]
        let groups: [IOSSavedGroup] = IOSSavedFiles.groups(files, now: now, calendar: calendar)
        XCTAssertEqual(groups.map(\.section), [IOSSavedSection.today, IOSSavedSection.thisWeek, IOSSavedSection.earlier])
        XCTAssertEqual(groups[0].files.map(\.name), ["a.pdf"])
        XCTAssertEqual(groups[1].files.map(\.name), ["b.pdf", "c.pdf"])
        XCTAssertEqual(groups[2].files.map(\.name), ["d.pdf", "e.pdf"])

        let onlyEarlier: [IOSSavedGroup] = IOSSavedFiles.groups([files[4]], now: now, calendar: calendar)
        XCTAssertEqual(onlyEarlier.map(\.section), [IOSSavedSection.earlier])
        XCTAssertTrue(IOSSavedFiles.groups([], now: now, calendar: calendar).isEmpty)
    }

    func test_savedFiles_sortAndFilter() throws {
        func file(_ name: String, size: Int, age: Double) -> IOSSavedFile {
            IOSSavedFile(url: URL(fileURLWithPath: "/tmp/\(name)"), modified: Date(timeIntervalSince1970: 1_000_000 - age),
                         byteCount: size, isNew: false)
        }
        let files: [IOSSavedFile] = [file("Scan 10.pdf", size: 500, age: 10), file("scan 2.pdf", size: 900, age: 20),
                                     file("Notes.docx", size: 500, age: 5), file("photo.JPG", size: 100, age: 30),
                                     file("page.tif", size: 100, age: 40), file("a.txt", size: 50, age: 50)]
        XCTAssertEqual(IOSSavedFiles.sorted(files, by: IOSSavedSort.date).map(\.name),
                       ["Notes.docx", "Scan 10.pdf", "scan 2.pdf", "photo.JPG", "page.tif", "a.txt"])
        XCTAssertEqual(IOSSavedFiles.sorted(files, by: IOSSavedSort.name).map(\.name),
                       ["a.txt", "Notes.docx", "page.tif", "photo.JPG", "scan 2.pdf", "Scan 10.pdf"])
        XCTAssertEqual(IOSSavedFiles.sorted(files, by: IOSSavedSort.size).map(\.name),
                       ["scan 2.pdf", "Notes.docx", "Scan 10.pdf", "photo.JPG", "page.tif", "a.txt"])

        XCTAssertEqual(files.filter { IOSSavedFilter.all.matches($0) }.count, 6)
        XCTAssertEqual(files.filter { IOSSavedFilter.pdf.matches($0) }.map(\.name), ["Scan 10.pdf", "scan 2.pdf"])
        XCTAssertEqual(files.filter { IOSSavedFilter.images.matches($0) }.map(\.name), ["photo.JPG", "page.tif"])
        XCTAssertEqual(files.filter { IOSSavedFilter.word.matches($0) }.map(\.name), ["Notes.docx"])
        XCTAssertEqual(IOSSavedFiles.sortFilterValue(IOSSavedSort.size, IOSSavedFilter.pdf), "Sorted by Size, showing PDF")
        XCTAssertEqual(IOSSavedFilter.images.emptyLine, "Nothing in the folder is an image.")
    }

    func test_savedFiles_aFileInAFolderNamesIt() throws {
        let saved: URL = folder.appendingPathComponent("Saved", isDirectory: true)
        let taxes: URL = saved.appendingPathComponent("Taxes", isDirectory: true)
        try FileManager.default.createDirectory(at: taxes, withIntermediateDirectories: true)
        try Data("a".utf8).write(to: saved.appendingPathComponent("top.pdf"))
        try Data("b".utf8).write(to: taxes.appendingPathComponent("inner.pdf"))

        let listed: [IOSSavedFile] = IOSSavedFiles.list(in: saved, justSaved: []).files
        let top: IOSSavedFile = try XCTUnwrap(listed.first { $0.name == "top.pdf" })
        let inner: IOSSavedFile = try XCTUnwrap(listed.first { $0.name == "inner.pdf" })
        XCTAssertNil(top.folder)
        XCTAssertEqual(inner.folder, "Taxes")
        XCTAssertTrue(inner.detail(pages: 2).hasPrefix("Taxes \u{00B7} 2 pages \u{00B7} "), inner.detail(pages: 2))
        XCTAssertFalse(top.detail(pages: 2).contains("Taxes"))
    }

    func test_savedFiles_detail_pagesSizeAndDate() throws {
        var calendar: Calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now: Date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 15)))
        let thisYear: Date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 5, hour: 9)))
        let lastYear: Date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 3, day: 5, hour: 9)))
        let recent: IOSSavedFile = IOSSavedFile(url: URL(fileURLWithPath: "/tmp/a.pdf"), modified: thisYear, byteCount: 340_000, isNew: false)
        let old: IOSSavedFile = IOSSavedFile(url: URL(fileURLWithPath: "/tmp/b.pdf"), modified: lastYear, byteCount: 340_000, isNew: false)

        let plain: String = recent.detail(pages: nil, now: now, calendar: calendar)
        XCTAssertFalse(plain.contains("page"), plain)
        XCTAssertTrue(plain.contains("\u{00B7}"), plain)
        XCTAssertFalse(plain.contains("2026"), plain)
        XCTAssertTrue(recent.detail(pages: 1, now: now, calendar: calendar).hasPrefix("1 page \u{00B7} "))
        XCTAssertTrue(recent.detail(pages: 3, now: now, calendar: calendar).hasPrefix("3 pages \u{00B7} "))
        XCTAssertTrue(old.detail(pages: nil, now: now, calendar: calendar).contains("2025"))
    }

    func test_savedFiles_thumbnails_ofAPictureAndAPDF() throws {
        let picture: URL = folder.appendingPathComponent("page.png")
        try ImportTestSupport.file(UTType.png, images: [libraryPicture(width: 400, height: 300)]).write(to: picture)
        let small: CGImage? = IOSSavedFiles.thumbnail(of: picture, maxSide: 100)
        XCTAssertEqual(small.map { (image: CGImage) -> Int in max(image.width, image.height) }, 100)

        let pdf: URL = folder.appendingPathComponent("page.pdf")
        var box: CGRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let writer: CGContext = try XCTUnwrap(CGContext(pdf as CFURL, mediaBox: &box, nil))
        writer.beginPDFPage(nil)
        writer.setFillColor(CGColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1))
        writer.fill(CGRect(x: 72, y: 72, width: 200, height: 100))
        writer.endPDFPage()
        writer.closePDF()
        let first: CGImage? = IOSSavedFiles.thumbnail(of: pdf, maxSide: 160)
        XCTAssertEqual(first?.height, 160)
        XCTAssertNil(IOSSavedFiles.thumbnail(of: folder.appendingPathComponent("notes.txt"), maxSide: 160))
        XCTAssertEqual(IOSSavedFiles.pageCount(of: pdf), 1)
        XCTAssertNil(IOSSavedFiles.pageCount(of: folder.appendingPathComponent("notes.txt")))
    }

    @MainActor
    func test_savedFiles_shareAndShowInFiles_goThroughTheFileActions() throws {
        let opened: LibraryOpened = LibraryOpened()
        let actions: IOSFileActions = IOSFileActions(pasteboard: nil, openSystemURL: { (url: URL) -> Void in
            opened.urls.append(url)
        })
        let state: AppState = AppState(backends: [], presetStore: PresetStore(directory: folder), fileActions: actions,
                                       orientationScorer: ImportTestScorer(), barcodeReader: ImportTestBarcodes(),
                                       files: AppStateFiles.all(in: folder))
        let file: URL = folder.appendingPathComponent("Scan.pdf")
        try Data("%PDF-1.4\n".utf8).write(to: file)

        XCTAssertTrue(state.runFileAction(FileAction.share, urls: [file]))
        XCTAssertEqual(actions.shareRequest?.urls, [file])
        XCTAssertTrue(state.runFileAction(FileAction.reveal, urls: [file]))
        XCTAssertEqual(opened.urls.count, 1)
        XCTAssertEqual(opened.urls.first?.scheme, "shareddocuments")
        XCTAssertTrue(state.runFileAction(FileAction.open, urls: [file]))
        XCTAssertEqual(actions.previewURL, file)

        // Show in Files for the save folder opens that folder, not the one holding it.
        var settings: ScanSettings = state.settings
        settings.destinationPath = folder.appendingPathComponent("Saved", isDirectory: true).path
        let saveFolder: URL = IOSSavedFiles.folder(settings)
        state.revealInFinder(saveFolder)
        XCTAssertEqual(opened.urls.count, 2)
        XCTAssertEqual(opened.urls.last?.scheme, "shareddocuments")
        XCTAssertEqual(opened.urls.last?.path, saveFolder.path)
    }
}
#endif
