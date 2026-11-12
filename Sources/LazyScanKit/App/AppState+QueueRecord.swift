import CoreGraphics
import Foundation

/// The page queue as the iPhone and the Mac keep it beside its spool files (queue.json), so the pages taken
/// survive iOS ending the app in the background and a crash of the Mac app (`AppStateFiles.keepsQueue`): each
/// page's spool files and what the queue knows about it. The previews are read from the files again. The
/// spreads book pages were cut from and the spine's shadow stay in memory only, as the companion package
/// leaves them out. The Mac's is emptied when the app is quit (`AppStateFiles.discardsQueueAtQuit`).
struct QueueRecord: Codable, Sendable {
    var pages: [Page]
    /// How many pages the queue had when it was recorded, those left out included; nil in a record written
    /// before it existed.
    var queued: Int?
    /// What the camera, the task's steps and Save knew besides the pages, set again by `restoreQueue` when
    /// the task is still `taskId`; nil in a record written before they were kept, or with nothing to keep.
    /// The Windows record has none of them and leaves them out when it reads this one.
    var taskId: String?
    var cameraSides: CameraSides?
    var flowCaptures: [String: [UUID]]?
    var flowStep: Int?
    var newDocumentPending: Bool?
    /// The bookmark of `AppState.appendTarget` (`AppState.bookmarkAppendTarget`).
    var appendBookmark: Data?

    struct Page: Codable, Sendable {
        var id: UUID
        var file: String
        var fullPixelSize: CGSize?
        var alternateFile: String?
        var alternatePixelSize: CGSize?
        var dpi: Int
        var colorMode: ColorMode
        var createdAt: Date
        var rotationQuarterTurns: Int
        var side: PageSide?
        var sheetIndex: Int?
        var blank: BlankPageResult?
        var inclusion: PageInclusion
        var geometry: PageGeometry?
        var showsOriginal: Bool
        var patch: PatchCode?
        var barcodes: [BarcodeReading]?
        var documentBreak: DocumentBreak
        var documentLabel: String?
        var upright: UprightTurn?
        var source: PageSource
        var capture: CaptureFacts?
    }

    static let fileName = "queue.json"

    /// Decodes a page without failing the list it sits in: one with an unknown value or a missing field
    /// comes out nil.
    private struct Lenient: Decodable {
        let page: Page?

        init(from decoder: Decoder) throws {
            page = try? Page(from: decoder)
        }
    }

    /// Pages that do not decode are left out; `queued` then counts them, so the restore says some did not
    /// come back. When none does, the record is unreadable as a whole.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try container.decode([Lenient].self, forKey: .pages)
        pages = entries.compactMap(\.page)
        if pages.isEmpty && !entries.isEmpty {
            throw DecodingError.dataCorruptedError(forKey: .pages, in: container, debugDescription: "No page could be read")
        }
        let recorded = try container.decodeIfPresent(Int.self, forKey: .queued)
        queued = recorded ?? (pages.count < entries.count ? entries.count : nil)
        taskId = try? container.decodeIfPresent(String.self, forKey: .taskId)
        cameraSides = try? container.decodeIfPresent(CameraSides.self, forKey: .cameraSides)
        flowCaptures = try? container.decodeIfPresent([String: [UUID]].self, forKey: .flowCaptures)
        flowStep = try? container.decodeIfPresent(Int.self, forKey: .flowStep)
        newDocumentPending = try? container.decodeIfPresent(Bool.self, forKey: .newDocumentPending)
        appendBookmark = try? container.decodeIfPresent(Data.self, forKey: .appendBookmark)
    }

    /// "Bringing back 3 pages…", or "Bringing back pages: 2 of 3…" once the pages come back one by one.
    static func restoringMessage(_ count: Int) -> String {
        L10n.plural(count, one: "Bringing back {0} page…", other: "Bringing back {0} pages…")
    }

    static func restoringMessage(_ done: Int, of count: Int) -> String {
        L10n.t("Bringing back pages: {0} of {1}…", done, count)
    }

    /// "3 pages are back from last time.", or "Pages back from last time: 3 of 4." when fewer came back
    /// than the queue had; when none could be read, says so.
    static func restoredMessage(_ count: Int, of queued: Int) -> String {
        switch count {
        case 0: return L10n.t("The pages kept from last time could not be read.")
        case ..<queued:
            return L10n.t("Pages back from last time: {0} of {1}.", count, queued)
        default:
            return L10n.plural(count, one: "{0} page is back from last time.", other: "{0} pages are back from last time.")
        }
    }

    /// The record of `pages`. A page without a file in `spool` (kept in memory because its spill failed) is
    /// left out, as the record could not bring it back, and so is a version not shown that is in memory only.
    init(_ pages: [ScannedPage], spool: URL) {
        var records: [Page] = []
        for page in pages {
            guard let url = page.fileURL, url.deletingLastPathComponent().path == spool.path else { continue }
            var alternateFile: String?
            if let other = page.alternate?.fileURL, other.deletingLastPathComponent().path == spool.path {
                alternateFile = other.lastPathComponent
            }
            records.append(Page(id: page.id, file: url.lastPathComponent, fullPixelSize: page.fullPixelSize,
                                alternateFile: alternateFile, alternatePixelSize: page.alternate?.fullPixelSize,
                                dpi: page.dpi, colorMode: page.colorMode, createdAt: page.createdAt,
                                rotationQuarterTurns: page.rotationQuarterTurns, side: page.side,
                                sheetIndex: page.sheetIndex, blank: page.blank, inclusion: page.inclusion,
                                geometry: page.geometry, showsOriginal: page.showsOriginal, patch: page.patch,
                                barcodes: page.barcodes, documentBreak: page.documentBreak,
                                documentLabel: page.documentLabel, upright: page.upright, source: page.source,
                                capture: page.capture))
        }
        self.pages = records
        self.queued = pages.count
    }

    /// The record in `spool` when its pages can come back: it reads and the settings the app starts with
    /// save a queue (`TaskFlowKind.documentQueue`, or Photos and Receipts, whose objects the iPhone queues,
    /// `AppState.listsFoundObjects`). A page whose file is gone is left out (the record is
    /// written a moment after a page goes, and the app may end in between); nil when none is left, and the
    /// spool is emptied as it always was. A page that does not decode is left out like one whose file is gone.
    static func read(in spool: URL, settings: ScanSettings) -> QueueRecord? {
        guard keepsQueue(settings), var record = decoded(in: spool) else { return nil }
        record.pages = record.pages.filter { (page: Page) -> Bool in
            FileManager.default.fileExists(atPath: spool.appendingPathComponent(page.file).path)
        }
        return record.pages.isEmpty ? nil : record
    }

    /// True when a record is in `spool` for a queue the settings save but it cannot be decoded at all. The
    /// spool is then left as it is, as the pages are still in it.
    static func isUnreadable(in spool: URL, settings: ScanSettings) -> Bool {
        guard keepsQueue(settings),
              FileManager.default.fileExists(atPath: spool.appendingPathComponent(fileName).path) else {
            return false
        }
        return decoded(in: spool) == nil
    }

    private static func keepsQueue(_ settings: ScanSettings) -> Bool {
        let flow: TaskFlowKind = TaskCatalog.flow(of: settings)
        return flow == .documentQueue || flow == .photoSplit || flow == .receiptSplit
    }

    private static func decoded(in spool: URL) -> QueueRecord? {
        guard let data = try? Data(contentsOf: spool.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(QueueRecord.self, from: data)
    }

    /// Pages kept in Application Support are no use in a backup: they belong to this device's session.
    static func keepOutOfBackups(_ spool: URL) {
        var directory = spool
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
    }

    /// Empties `spool` of what a previous run left, the files of the queue `kept` (and its record) aside.
    static func clear(_ spool: URL, keeping kept: QueueRecord?) {
        let manager = FileManager.default
        guard let kept else {
            try? manager.removeItem(at: spool)
            try? manager.createDirectory(at: spool, withIntermediateDirectories: true)
            return
        }
        var keep: Set<String> = [fileName]
        for page in kept.pages {
            keep.insert(page.file)
            if let other = page.alternateFile { keep.insert(other) }
        }
        let names = (try? manager.contentsOfDirectory(atPath: spool.path)) ?? []
        for name in names where !keep.contains(name) {
            try? manager.removeItem(at: spool.appendingPathComponent(name))
        }
    }
}

extension QueueRecord.Page {
    /// The page this was recorded from, with `preview` (read from its file) as its picture.
    func page(preview: CGImage, spool: URL) -> ScannedPage {
        var page = ScannedPage(image: preview, dpi: dpi, colorMode: colorMode, id: id, createdAt: createdAt,
                               fileURL: spool.appendingPathComponent(file), fullPixelSize: fullPixelSize)
        page.rotationQuarterTurns = rotationQuarterTurns
        page.side = side
        page.sheetIndex = sheetIndex
        page.blank = blank
        page.inclusion = inclusion
        page.geometry = geometry
        page.showsOriginal = showsOriginal
        page.patch = patch
        page.barcodes = barcodes
        page.documentBreak = documentBreak
        page.documentLabel = documentLabel
        page.upright = upright
        page.source = source
        page.capture = capture
        if let alternateFile {
            let other = spool.appendingPathComponent(alternateFile)
            if FileManager.default.fileExists(atPath: other.path) {
                page.alternate = PageVersion(image: nil, fileURL: other, fullPixelSize: alternatePixelSize)
            }
        }
        return page
    }
}

extension AppState {
    /// Writes the queue's record beside the spool, or removes it when the queue is empty or none of its pages
    /// has a file in the spool.
    func writeQueueRecord() {
        queueRecordTask?.cancel()
        queueRecordTask = nil
        let url = spoolDirectory.appendingPathComponent(QueueRecord.fileName)
        var record = QueueRecord(scannedPages, spool: spoolDirectory)
        record.taskId = settings.taskId
        record.cameraSides = cameraSides
        record.flowCaptures = taskFlow?.allCaptures
        record.flowStep = taskFlow.map(\.stepIndex)
        record.newDocumentPending = newDocumentPending ? true : nil
        record.appendBookmark = appendTarget.flatMap { bookmarkAppendTarget?($0) }
        guard !record.pages.isEmpty, let data = try? JSONEncoder().encode(record) else {
            try? FileManager.default.removeItem(at: url)
            warnIfNotKept(!scannedPages.isEmpty)
            return
        }
        let written: Bool = (try? data.write(to: url, options: .atomic)) != nil
        warnIfNotKept(!written || record.pages.count < scannedPages.count)
    }

    /// Says once that pages held in memory only are lost when the app ends, and again only after the queue
    /// has been whole in between.
    private func warnIfNotKept(_ notKept: Bool) {
        guard notKept else {
            warnedNotKept = false
            return
        }
        guard !warnedNotKept else { return }
        warnedNotKept = true
        statusMessage = L10n.t("Storage is full: these pages are lost if the app closes.")
    }

    /// Records a queue kept a moment after it last changed (`queueRecordDelay`), so a batch of changes
    /// writes once.
    func scheduleQueueRecord() {
        guard keepsQueue, !restoringQueue else { return }
        queueRecordTask?.cancel()
        let delay = queueRecordDelay
        queueRecordTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self, !self.restoringQueue else { return }
            self.writeQueueRecord()
        }
    }

    /// Brings back the queue kept last time as an operation of its own (`isBusy`), so no kind is picked,
    /// nothing saved and no page taken until the pages are back: their previews are read off the main
    /// actor, and a page whose file cannot be read is left out. Cancel does not stop it.
    func restoreQueue(_ record: QueueRecord) {
        restoringQueue = true
        let spool = spoolDirectory
        statusMessage = QueueRecord.restoringMessage(record.pages.count)
        runExclusive { _ in
            var previews: [CGImage?] = []
            for (index, page) in record.pages.enumerated() {
                let preview: CGImage? = await Task.detached(priority: .userInitiated) {
                    AppState.previewOfSpoolFile(spool.appendingPathComponent(page.file),
                                                quarterTurns: page.rotationQuarterTurns)
                }.value
                previews.append(preview)
                self.statusMessage = QueueRecord.restoringMessage(index + 1, of: record.pages.count)
            }
            var pages: [ScannedPage] = []
            for (page, preview) in zip(record.pages, previews) {
                if let preview {
                    pages.append(page.page(preview: preview, spool: spool))
                }
            }
            self.restoringQueue = false
            self.scannedPages = pages + self.scannedPages
            self.restoreSession(from: record, pages: pages)
            self.statusMessage = QueueRecord.restoredMessage(pages.count, of: record.queued ?? record.pages.count)
        }
    }

    /// Gives back what went with the pages, when the task is still the one they were taken in: the camera's
    /// two-sided steps (when they take the sides the way the settings now say, as `syncCameraSides` made
    /// them), the steps' captures of pages that came back, a pending New document and the PDF to add to.
    private func restoreSession(from record: QueueRecord, pages: [ScannedPage]) {
        guard record.taskId == settings.taskId else { return }
        let ids = Set(pages.map(\.id))
        if var sides = record.cameraSides, sides.mode == cameraSides?.mode {
            for page in record.pages where !ids.contains(page.id) { sides.removed(page.id) }
            cameraSides = sides
        }
        for (stepID, captures) in record.flowCaptures ?? [:] {
            for id in captures where ids.contains(id) {
                taskFlow?.record(stepID: stepID, captureID: id)
            }
        }
        while (taskFlow?.stepIndex ?? 0) < (record.flowStep ?? 0), taskFlow?.advance() == true {}
        if record.newDocumentPending == true && offersNewDocument {
            newDocumentPending = true
        }
        if let bookmark = record.appendBookmark, let url = resolveAppendTarget?(bookmark) {
            appendTarget = url
        }
    }
}
