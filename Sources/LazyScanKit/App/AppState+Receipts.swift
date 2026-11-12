import CoreGraphics
import Foundation

/// The Receipts task: the receipts on a scan are found (`ReceiptDetector`), cut out, straightened and
/// made easy to read (`ReceiptEnhancer`), reviewed in the photo review, which reads each one's text
/// once with OCR for its date (the file name's {docdate}, editable in the review), the PDF's text layer and
/// the text beside it, then saved: the receipts are written as a file each or as one PDF, all or nothing.
/// Twin of the Windows `AppViewModel.Receipts.cs`.
extension AppState {
    /// The scans of the settings are receipts (the Receipts task).
    public var isReceiptFlow: Bool { TaskCatalog.flow(of: settings) == .receiptSplit }

    /// The review's title: "Found 3 receipts", or for photos "Found 3 photos" (`PhotoReview.title`).
    public var reviewTitle: String {
        isReceiptReview ? Receipts.reviewTitle(detectedPhotos.count) : PhotoReview.title(detectedPhotos.count)
    }

    /// The review's save button: "Save 2 Receipts", "Save as One PDF", "Save 3 photos" (`PhotoReview.saveTitle`).
    public var reviewSaveTitle: String {
        let included = detectedPhotos.filter(\.included).count
        return isReceiptReview
            ? Receipts.saveTitle(included: included, combine: settings.taskOptions.receiptCombine, format: settings.format)
            : PhotoReview.saveTitle(included)
    }

    public func setReceiptNameByDate(_ byDate: Bool) {
        guard settings.taskOptions.receiptNameByDate != byDate else { return }
        settings.taskOptions.receiptNameByDate = byDate
    }

    public func setReceiptCombine(_ combine: Bool) {
        guard settings.taskOptions.receiptCombine != combine else { return }
        settings.taskOptions.receiptCombine = combine
    }

    /// The receipts on one scanned page, cut out, upright and cleaned up: several on the glass, the
    /// whole sheet as one from the feeder; the whole page when nothing looks like a receipt. With a `scorer`
    /// each one cut from the scan is given the quarter turns that read upright (`Receipts.uprightTurns`) as
    /// its rotation in the review.
    nonisolated static func splitReceipts(from page: ScannedPage, settings s: ScanSettings,
                                          scorer: (any OrientationScorer)? = nil,
                                          shouldContinue: () -> Bool = { true }) -> [DetectedPhoto] {
        guard let scan = RgbaImage(cgImage: page.image) else { return [] }
        // One receipt of a camera's shot, cut out already at its roll's width: the whole page, made easy
        // to read as a receipt found on the glass is.
        if CaptureObjects.isCutOut(page), let quad = page.capture?.quad {
            let cleaned: RgbaImage = ReceiptEnhancer.enhance(scan, dpi: page.dpi)
            guard let image = cleaned.makeCGImage() else { return [] }
            return [DetectedPhoto(region: CaptureObjects.region(around: quad), image: image, dpi: page.dpi,
                                  sourcePageID: page.id)]
        }
        let options = ReceiptDetectorOptions(singleReceipt: s.source == .documentFeeder)
        var regions = ReceiptDetector.detectRegions(in: scan, dpi: page.dpi, options: options)
        if regions.isEmpty {
            let w = Double(scan.width), h = Double(scan.height)
            regions = [DetectedPhotoRegion(center: CGPoint(x: w / 2, y: h / 2), size: CGSize(width: w, height: h),
                                           angleDegrees: 0)]
        }
        var receipts: [DetectedPhoto] = []
        for region in regions {
            guard shouldContinue() else { break }
            guard let cut = ReceiptDetector.extractEnhanced(scan, region: region, dpi: page.dpi),
                  let image = cut.makeCGImage() else { continue }
            var receipt = DetectedPhoto(region: region, image: image, dpi: page.dpi, sourcePageID: page.id)
            if let scorer { receipt.rotationQuarterTurns = Receipts.uprightTurns(cut, dpi: page.dpi, scorer: scorer,
                                                                           shouldContinue: shouldContinue) }
            receipts.append(receipt)
        }
        return receipts
    }

    /// Opens the review on the receipts found on the pages just scanned. The pages of a scan
    /// (`generation`, the scanner choice they belong to) are dropped when another scanner is chosen
    /// meanwhile; pages that belong to no scanner (nil, `ingest`) are kept (`isCurrent`).
    func showReceipts(_ processed: [ScannedPage], settings s: ScanSettings, flag: CancelFlag,
                      generation: Int?) async throws {
        statusMessage = L10n.t("Finding receipts…")
        let scorer = orientationScorer
        let found: [DetectedPhoto] = try await Task.detached(priority: .userInitiated) {
            var all: [DetectedPhoto] = []
            for page in processed {
                if flag.isCancelled { throw ScanError.cancelled }
                all.append(contentsOf: Self.splitReceipts(from: page, settings: s, scorer: scorer,
                                                           shouldContinue: { !flag.isCancelled }))
                if flag.isCancelled { throw ScanError.cancelled }
            }
            return all
        }.value
        guard isCurrent(generation) else { return }
        if flag.isCancelled { throw ScanError.cancelled }
        // Every page's full-resolution scan stays while the review is open, for Fix crop (a camera's
        // receipt: the photo it was cut from, with its corners).
        let sources: ReviewSources = Self.reviewSources(processed)
        photoSourceImages = sources.images
        photoCaptureFacts = sources.facts
        detectedPhotos = found
        isReceiptReview = true
        recordCaptures(found.map(\.id))
        showPhotoReview = !found.isEmpty
        if found.isEmpty { photoSourceImages = [:] }
        readReceipts()
        setStatus(L10n.plural(found.count, one: "Found {0} receipt.", other: "Found {0} receipts."),
                  StatusDetail(head: .found(found.count, .receipt)))
    }

    /// Reads the text of the receipts in the review that are not read yet (or not as they are turned now),
    /// one after another off the main actor, for their date and the text layer. The reading is kept on each
    /// receipt, so saving does not read it again. An earlier reading finishes first; a receipt that is
    /// turned or cut again meanwhile is read once more.
    func readReceipts() {
        let s = settings
        guard isReceiptReview, Receipts.readsText(s) else { return }
        let byDate = Receipts.namesByDate(s)
        let dayFirst = ReceiptDateExtractor.prefersDayFirst()
        let previous = receiptReading
        receiptReading = Task { @MainActor [weak self] in
            await previous?.value
            while let self, self.isReceiptReview, let receipt = self.detectedPhotos.first(where: { !$0.isRead }) {
                let turns = receipt.rotationQuarterTurns
                let image = receipt.image
                let reading = await Task.detached(priority: .userInitiated) {
                    Self.readReceipt(image, quarterTurns: turns, byDate: byDate, preferDayFirst: dayFirst)
                }.value
                guard let index = self.detectedPhotos.firstIndex(where: { $0.id == receipt.id }),
                      self.detectedPhotos[index].region == receipt.region,
                      self.detectedPhotos[index].rotationQuarterTurns == turns else { continue }
                self.detectedPhotos[index].reading = reading
            }
        }
    }

    /// Turns a receipt in the review and reads it again.
    public func rotateReviewPhoto(id: UUID, by delta: Int) {
        guard let index = detectedPhotos.firstIndex(where: { $0.id == id }) else { return }
        let turns = detectedPhotos[index].rotationQuarterTurns + delta
        detectedPhotos[index].rotationQuarterTurns = ((turns % 4) + 4) % 4
        readReceipts()
    }

    /// The text of `image` turned `quarterTurns` quarter turns, and the date found in it when `byDate`. A
    /// receipt whose text cannot be read is still saved: without a text layer, named by the scan date.
    nonisolated static func readReceipt(_ image: CGImage, quarterTurns: Int, byDate: Bool,
                                        preferDayFirst: Bool) -> ReceiptReading {
        let turned = quarterTurns == 0 ? image : ImagePipeline.rotate(image, quarterTurns: quarterTurns)
        do {
            let lines = try OCRService.recognizeLines(in: turned)
            var date: DocumentDate?
            if byDate {
                date = ReceiptDateExtractor.findDate(
                    Receipts.textLines(lines, pixelWidth: turned.width, pixelHeight: turned.height),
                    today: DocumentDate(date: Date()), preferDayFirst: preferDayFirst)
            }
            return ReceiptReading(quarterTurns: quarterTurns, lines: lines, problem: nil, date: date)
        } catch {
            return ReceiptReading(quarterTurns: quarterTurns, lines: nil, problem: error.localizedDescription, date: nil)
        }
    }

    /// Fix crop on a receipt: cut out upright and cleaned up again, as it was found.
    nonisolated static func recutReceipt(_ source: CGImage, region: DetectedPhotoRegion, dpi: Int) -> CGImage? {
        guard let scan = RgbaImage(cgImage: source),
              let cut = ReceiptDetector.extractEnhanced(scan, region: region, dpi: dpi) else { return nil }
        return cut.makeCGImage()
    }

    /// Saves the receipts kept in the review: each turned as shown, with the text read in the review
    /// (`readReceipts`; read here only when it was not); then a file each, or one PDF for all
    /// (`TaskOptions.receiptCombine`), named by the receipt's date as shown in the review ({docdate}; for
    /// one PDF the earliest), the scan date when none is found. All or nothing: a failed or
    /// cancelled save removes what it wrote and the review stays open.
    func saveReceipts() {
        let s = settings
        let format = s.format.pageFormat
        let byDate = Receipts.namesByDate(s)
        let readsText = Receipts.readsText(s)
        let dayFirst = ReceiptDateExtractor.prefersDayFirst()
        runExclusive { flag in
            await self.recropChain?.value
            if let reading = self.receiptReading {
                self.statusMessage = L10n.t("Reading the receipts…")
                await reading.value
            }
            let receipts = self.detectedPhotos.filter(\.included)
            guard !receipts.isEmpty else { return }
            // A protected PDF's password is asked for before the receipts are read.
            var protection: PDFProtection? = nil
            if format == .pdf { protection = try await self.protectionFor(s) }
            let combine = Receipts.combines(s.taskOptions.receiptCombine, format: s.format, count: receipts.count)

            // 1. Each receipt as shown, with the text read in the review (read now only when it was not).
            self.statusMessage = L10n.t("Reading the receipts…")
            let read: [ReadReceipt] = try await Task.detached(priority: .userInitiated) { () throws -> [ReadReceipt] in
                var out: [ReadReceipt] = []
                for receipt in receipts {
                    if flag.isCancelled { throw ScanError.cancelled }
                    let image = receipt.rotationQuarterTurns == 0
                        ? receipt.image
                        : ImagePipeline.rotate(receipt.image, quarterTurns: receipt.rotationQuarterTurns)
                    var reading: ReceiptReading? = receipt.isRead ? receipt.reading : nil
                    if reading == nil, readsText {
                        reading = Self.readReceipt(receipt.image, quarterTurns: receipt.rotationQuarterTurns,
                                                   byDate: byDate, preferDayFirst: dayFirst)
                    }
                    // A date typed in the review replaces the one found.
                    var date: DocumentDate?
                    if byDate {
                        date = receipt.typedDate != nil ? receipt.receiptDate : reading?.date
                    }
                    out.append(ReadReceipt(image: image, dpi: receipt.dpi, lines: reading?.lines, date: date,
                                           problem: reading?.problem))
                }
                return out
            }.value
            if flag.isCancelled { throw ScanError.cancelled }

            // 2. The files, all or nothing.
            var saved: [URL] = []
            var written: [URL] = []
            var textProblem: String?
            do {
                if combine {
                    let planned = try self.outputURL(fileExtension: "pdf", documentDate: Receipts.combinedDate(read.map(\.date)))
                    self.statusMessage = L10n.t("Writing the PDF…")
                    let options: PDFWriteOptions = try await self.pdfOptions(s, for: planned)
                    let text = try await Task.detached(priority: .userInitiated) { () throws -> (pdf: URL, url: URL?, problem: String?) in
                        try Self.writeReceiptsPDF(read, settings: s, to: planned, options: options,
                                                  shouldContinue: { !flag.isCancelled })
                    }.value
                    saved.append(text.pdf)
                    written.append(text.pdf)
                    if let textURL = text.url { written.append(textURL) }
                    if let problem = text.problem { textProblem = textProblem ?? problem }
                } else {
                    for (index, receipt) in read.enumerated() {
                        if flag.isCancelled { throw ScanError.cancelled }
                        self.statusMessage = L10n.t("Saving receipt {0} of {1}…", index + 1, read.count)
                        let planned = try self.outputURL(fileExtension: format.fileExtension, documentDate: receipt.date)
                        if format == .pdf {
                            let options: PDFWriteOptions = try await self.pdfOptions(s, for: planned)
                            let text = try await Task.detached(priority: .userInitiated) { () throws -> (pdf: URL, url: URL?, problem: String?) in
                                try Self.writeReceiptsPDF([receipt], settings: s, to: planned, options: options,
                                                          shouldContinue: { !flag.isCancelled })
                            }.value
                            saved.append(text.pdf)
                            written.append(text.pdf)
                            if let textURL = text.url { written.append(textURL) }
                            if let problem = text.problem { textProblem = textProblem ?? problem }
                        } else {
                            let url = try await Task.detached(priority: .userInitiated) {
                                try ImageExporter.write(receipt.image, to: planned, format: format, dpi: receipt.dpi,
                                                        jpegQuality: s.jpegQuality, keepingExisting: true)
                            }.value
                            saved.append(url)
                            written.append(url)
                        }
                    }
                }
            } catch {
                for url in written { try? FileManager.default.removeItem(at: url) }
                throw error
            }
            self.lastSavedURLs = saved
            let pdfs: Bool = combine || format == .pdf
            if let url = saved.first, pdfs, saved.count == 1 { self.notePDFSize(of: url, protected: protection != nil) }
            self.detectedPhotos = []
            self.showPhotoReview = false
            self.isReceiptReview = false
            self.photoSourceImages = [:]
            self.resetFlow()
            if let textProblem { self.errorMessage = TextExport.sidecarFailed(textProblem) }
            if textProblem == nil, let problem = read.compactMap(\.problem).first {
                self.errorMessage = TextExport.recognitionFailed(problem)
            }
            let undated = byDate ? read.filter { $0.date == nil }.count : 0
            var names: [String] = saved.map(\.lastPathComponent)
            // Protected PDFs say so after their names: "a.pdf, b.pdf (password-protected)".
            if pdfs, !names.isEmpty, let note = Self.pdfNote(size: nil, isProtected: protection != nil) {
                names[names.count - 1] = L10n.t("{0} ({1})", names[names.count - 1], note)
            }
            self.setStatus(Receipts.savedMessage(count: read.count, fileNames: names, combined: combine, undated: undated),
                           StatusDetail(head: .savedFiles(read.count, .receipt)))
            self.runAfterSave(s.output.afterSave, saved: saved)
        }
    }

    /// One PDF of `receipts` (a page each, gray, at the PDF size chosen) with the text read beforehand as
    /// its layer when searchable, and the text beside it when asked for. Returns where the PDF went (the
    /// next free name when `url` has been taken meanwhile) and the text file written
    /// (the next free name when the PDF's is taken; nil when none was), else why it was not (the PDF is kept).
    nonisolated static func writeReceiptsPDF(_ receipts: [ReadReceipt], settings s: ScanSettings, to url: URL,
                                             options: PDFWriteOptions?,
                                             shouldContinue: @escaping () -> Bool) throws -> (pdf: URL, url: URL?, problem: String?) {
        let pages = receipts.map { ScannedPage(image: $0.image, dpi: $0.dpi, colorMode: .grayscale) }
        let lines = receipts.map(\.lines)
        var layer: PDFTextLayer?
        if s.pdfSearchable {
            layer = { index, _ in index < lines.count ? lines[index] : nil }
        }
        let pdf = try writePDFAtomically(pages: pages, pdfSize: s.output.pdfSize, to: url, textLayer: layer, options: options,
                                         shouldContinue: shouldContinue, progress: nil)
        guard s.output.savesTextBeside else { return (pdf, nil, nil) }
        let text = PDFTextCollector()
        for receipt in receipts {
            if let found = receipt.lines {
                text.pages.append(OCRPage.of(found, pixelWidth: receipt.image.width, pixelHeight: receipt.image.height,
                                             dpi: receipt.dpi))
            } else if text.problem == nil {
                text.problem = receipt.problem ?? L10n.t("The text could not be read.")
            }
        }
        let beside = writeTextBeside(pdf: pdf, text: text)
        return (pdf, beside.url, beside.problem)
    }
}

/// A receipt's text as read from its image turned `quarterTurns` quarter turns: the lines (nil when the text
/// could not be read, and why in `problem`) and the date found in them (nil when none, or not looked for).
public struct ReceiptReading {
    public let quarterTurns: Int
    public let lines: [OCRLine]?
    public let problem: String?
    public let date: DocumentDate?
}

/// A receipt as saved: its image turned as shown, its text (nil when it was not read or could not be),
/// its date and why its text could not be read.
struct ReadReceipt {
    let image: CGImage
    let dpi: Int
    let lines: [OCRLine]?
    let date: DocumentDate?
    let problem: String?
}
