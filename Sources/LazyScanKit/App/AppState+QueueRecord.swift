import CoreGraphics
import Foundation

/// The page queue as the iPhone keeps it beside its spool files (queue.json), so the pages taken survive iOS
/// ending the app in the background (`AppStateFiles.keepsQueue`): each page's spool files and what the queue
/// knows about it. The previews are read from the files again. The spreads book pages were cut from and the
/// spine's shadow stay in memory only, as the companion package leaves them out. Swift only: Windows keeps
/// emptying its spool at launch.
struct QueueRecord: Codable, Sendable {
    var pages: [Page]
    /// How many pages the queue had when it was recorded, those left out included; nil in a record written
    /// before it existed.
    var queued: Int?

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

    /// "Bringing back 3 pages…"
    static func restoringMessage(_ count: Int) -> String {
        L10n.plural(count, one: "Bringing back {0} page…", other: "Bringing back {0} pages…")
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
    /// spool is emptied as it always was.
    static func read(in spool: URL, settings: ScanSettings) -> QueueRecord? {
        let flow: TaskFlowKind = TaskCatalog.flow(of: settings)
        guard flow == .documentQueue || flow == .photoSplit || flow == .receiptSplit,
              let data = try? Data(contentsOf: spool.appendingPathComponent(fileName)),
              var record = try? JSONDecoder().decode(QueueRecord.self, from: data) else {
            return nil
        }
        record.pages = record.pages.filter { (page: Page) -> Bool in
            FileManager.default.fileExists(atPath: spool.appendingPathComponent(page.file).path)
        }
        return record.pages.isEmpty ? nil : record
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
        let record = QueueRecord(scannedPages, spool: spoolDirectory)
        guard !record.pages.isEmpty, let data = try? JSONEncoder().encode(record) else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    /// Records a queue kept a moment after it last changed (`queueRecordDelay`), so a batch of changes
    /// writes once.
    func scheduleQueueRecord() {
        guard keepsQueue, !restoringQueue else { return }
        queueRecordTask?.cancel()
        let delay = queueRecordDelay
        queueRecordTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self else { return }
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
            let previews: [CGImage?] = await Task.detached(priority: .userInitiated) {
                record.pages.map { (page: QueueRecord.Page) -> CGImage? in
                    AppState.previewOfSpoolFile(spool.appendingPathComponent(page.file),
                                                quarterTurns: page.rotationQuarterTurns)
                }
            }.value
            var pages: [ScannedPage] = []
            for (page, preview) in zip(record.pages, previews) {
                if let preview {
                    pages.append(page.page(preview: preview, spool: spool))
                }
            }
            self.restoringQueue = false
            self.scannedPages = pages + self.scannedPages
            self.statusMessage = QueueRecord.restoredMessage(pages.count, of: record.queued ?? record.pages.count)
        }
    }
}
