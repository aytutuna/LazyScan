import CoreGraphics
import Foundation
import ImageIO

/// A spread pages in the queue were cut from, as scanned: its full-resolution pixels in a spool file
/// (or in memory when the file could not be written), how it was scanned, and its size in pixels.
/// Twin of the Windows `AppViewModel.SpreadSource`.
struct SpreadSource {
    let fileURL: URL?
    let image: CGImage?
    let dpi: Int
    let colorMode: ColorMode
    let createdAt: Date
    let width: Int
    let height: Int
}

/// What the split sheet shows for a spread (`AppState.spreadEditor(for:)`). Twin of the Windows
/// `SpreadEditorSource`.
public struct SpreadEditorSource: Identifiable {
    /// The queued page the sheet was opened from.
    public let pageID: UUID
    /// The spread as scanned, at most 1600 pixels long.
    public let preview: CGImage
    /// How it is cut now.
    public let axis: GutterAxis
    /// Where it is cut now, along `axis` (0...1).
    public let fraction: Double
    /// It is cut now (not kept whole).
    public let isSplit: Bool
    /// Its number in the queue, from 1.
    public let spreadNumber: Int

    public var id: UUID { pageID }
}

/// Books and magazines: the spreads the queued pages were cut from (kept in the spool so a spread can
/// be joined or split again), joining and splitting a spread by hand. The page strip labels the pages
/// with `BookPages`; the inspector binds the book options directly. Twin of the Windows
/// `AppViewModel.Book.cs`.
extension AppState {
    /// Writes each spread as scanned to a spool TIFF of its own ("{id}-spread.tiff"), for joining and
    /// splitting it again, in `directory` (the app's `spoolDirectory`); a spread whose file cannot be
    /// written is kept in memory.
    nonisolated static func spoolSpreads(_ spreads: [ScannedPage], to directory: URL) -> [UUID: SpreadSource] {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var sources: [UUID: SpreadSource] = [:]
        for spread in spreads {
            let url = directory.appendingPathComponent("\(spread.id.uuidString)-spread.tiff")
            do {
                try ImageExporter.write(spread.image, to: url, format: .tiff, dpi: spread.dpi, jpegQuality: 1.0)
                sources[spread.id] = SpreadSource(fileURL: url, image: nil, dpi: spread.dpi, colorMode: spread.colorMode,
                                                  createdAt: spread.createdAt, width: spread.image.width,
                                                  height: spread.image.height)
            } catch {
                sources[spread.id] = SpreadSource(fileURL: nil, image: spread.image, dpi: spread.dpi,
                                                  colorMode: spread.colorMode, createdAt: spread.createdAt,
                                                  width: spread.image.width, height: spread.image.height)
            }
        }
        return sources
    }

    static func deleteSpreadFiles(_ sources: [SpreadSource]) {
        for source in sources {
            if let url = source.fileURL { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// The spread's full-resolution pixels: from memory, or read from its spool file; nil when it
    /// cannot be read.
    nonisolated static func loadSpread(_ source: SpreadSource) -> CGImage? {
        if let image = source.image { return image }
        guard let url = source.fileURL, let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    }

    /// Drops the spreads no queued page was cut from any more, and their files. Runs whenever the
    /// queue changes (`scannedPages`); a save or a removal held for Undo keeps the spreads of its pages.
    func pruneSpreads() {
        guard !spreadSources.isEmpty else { return }
        let held = (savedUndo?.pages ?? []) + (removedUndo?.pages.map { $0.page } ?? [])
        let used = Set((scannedPages + held).compactMap(\.spreadID))
        for (id, source) in spreadSources where !used.contains(id) {
            Self.deleteSpreadFiles([source])
            spreadSources[id] = nil
        }
    }

    /// Which spread of the queue (from 1, in queue order) `spreadID` is; 0 when none.
    func spreadNumber(_ spreadID: UUID) -> Int {
        var order: [UUID] = []
        for page in scannedPages {
            if let id = page.spreadID, !order.contains(id) { order.append(id) }
        }
        return (order.firstIndex(of: spreadID) ?? -1) + 1
    }

    /// The spread a queued page was cut from can be joined or split again: its spread is at hand.
    public func canEditSpread(id: UUID) -> Bool {
        guard let page = scannedPages.first(where: { $0.id == id }) else { return false }
        return canEditSpread(of: page)
    }

    /// `canEditSpread(id:)` for a page already at hand, without looking it up in the queue (the strip
    /// asks this for every cell on every refresh).
    public func canEditSpread(of page: ScannedPage) -> Bool {
        guard let spreadID = page.spreadID else { return false }
        return spreadSources[spreadID] != nil
    }

    /// What the split sheet shows for the spread a queued page was cut from: a preview of the spread as
    /// scanned, where it is cut now (a spread kept whole: across its longer side, in the middle), and its
    /// number. With Cut at "Same as last" the cut starts where the last one made by hand was. nil
    /// when the page is no book page or its spread can no longer be read.
    public func spreadEditor(for pageID: UUID) async -> SpreadEditorSource? {
        guard let page = scannedPages.first(where: { $0.id == pageID }), let part = page.spread,
              let source = spreadSources[part.spreadID] else { return nil }
        let preview: CGImage? = await Task.detached(priority: .userInitiated) {
            Self.loadSpread(source).map { Self.makePreview($0, maxSide: 1600) ?? $0 }
        }.value
        guard let preview else {
            errorMessage = L10n.t("The spread could not be read.")
            return nil
        }
        let options = BookSplitOptions.of(settings)
        var fraction = part.gutter?.fraction(width: source.width, height: source.height) ?? 0.5
        if options.cutAt == .sameAsLast, let last = options.lastCut { fraction = last }
        let axis = part.gutter?.axis ?? BookSplitter.defaultAxis(width: source.width, height: source.height)
        return SpreadEditorSource(pageID: pageID, preview: preview, axis: axis,
                                  fraction: fraction, isSplit: !part.isWhole, spreadNumber: spreadNumber(part.spreadID))
    }

    /// The split sheet's Split: the spread the page was cut from is cut again along `axis` at
    /// `fraction` of it, and its pages in the queue are replaced by the new ones, checked, straightened
    /// and turned as a scan is (`PageProcessor.processSpread`); a page the user removed stays out, and
    /// each page keeps its document break, name and keep or skip (`BookPages.replacementPages`).
    public func splitSpread(id: UUID, axis: GutterAxis, fraction: Double) {
        guard !isBusy, canEditSpread(id: id) else { return }
        settings.taskOptions.bookLastCut = fraction
        runExclusive { flag in
            try await self.recutSpread(id: id, cut: (axis, fraction), flag: flag)
        }
    }

    /// How many spreads in the queue are kept whole and can be cut by hand: what the split sheet's
    /// "Split all unsplit spreads here" would cut.
    public var unsplitSpreadCount: Int {
        Set(scannedPages.filter { ($0.spread?.isWhole ?? false) && canEditSpread(of: $0) }.compactMap(\.spreadID)).count
    }

    /// The split sheet's "Split all unsplit spreads here": the spread the sheet is open on is cut along
    /// `axis` at `fraction`, and so is every other spread of the queue kept whole, along its own longer
    /// side. The fraction is kept as the last cut. A spread that cannot be cut stays as it is; the first
    /// error is reported once the others are done.
    public func splitUnsplitSpreads(including id: UUID, axis: GutterAxis, fraction: Double) {
        guard !isBusy, canEditSpread(id: id) else { return }
        settings.taskOptions.bookLastCut = fraction
        runExclusive { flag in
            await self.pageEditChain?.value
            var ids: [UUID] = [id]
            for page in self.scannedPages where page.id != id && (page.spread?.isWhole ?? false) && self.canEditSpread(of: page) {
                ids.append(page.id)
            }
            var firstError: Error?
            var done = 0
            for pageID in ids {
                guard let spreadID = self.scannedPages.first(where: { $0.id == pageID })?.spreadID,
                      let source = self.spreadSources[spreadID] else { continue }
                let cutAxis = pageID == id ? axis : BookSplitter.defaultAxis(width: source.width, height: source.height)
                do {
                    try await self.recutSpread(id: pageID, cut: (cutAxis, fraction), flag: flag)
                    done += 1
                } catch ScanError.cancelled {
                    throw ScanError.cancelled
                } catch {
                    if firstError == nil { firstError = error }
                }
            }
            if done > 1 {
                self.statusMessage = L10n.plural(done, one: "{0} spread split into pages.", other: "{0} spreads split into pages.")
            }
            if let firstError { throw firstError }
        }
    }

    /// "Join the Two Pages" (and the sheet's "Keep as One Page"): the pages cut from the spread are
    /// replaced by the whole spread, as one page.
    public func joinSpread(id: UUID) {
        guard !isBusy, canEditSpread(id: id) else { return }
        runExclusive { flag in
            try await self.recutSpread(id: id, cut: nil, flag: flag)
        }
    }

    /// The spreads in the queue that are split and can be cut again, in queue order.
    private var splitSpreadIDs: [UUID] {
        var ids: [UUID] = []
        for page in scannedPages {
            guard let part = page.spread, !part.isWhole, spreadSources[part.spreadID] != nil,
                  !ids.contains(part.spreadID) else { continue }
            ids.append(part.spreadID)
        }
        return ids
    }

    /// The offer to cut the spreads in the queue again after the reading order or the rotation changed:
    /// nil when neither changed since, or no split spread is queued. The count follows the queue.
    public var bookReorderOffer: BookReorderOffer? {
        guard let changed = bookReorderChanged else { return nil }
        let count = splitSpreadIDs.count
        return count > 0 ? BookReorderOffer(count: count, changed: changed) : nil
    }

    /// Raises the offer when the settings just changed the book's reading order or rotation with split
    /// spreads queued (`settings`' didSet); the options still apply to the next scan either way.
    func noteBookOptionChange(from old: ScanSettings) {
        guard settings.taskId == old.taskId else {
            bookReorderChanged = nil
            return
        }
        let order = settings.taskOptions.bookRightToLeft != old.taskOptions.bookRightToLeft
        let turns = BookSplitter.normalizedTurns(settings.taskOptions.bookRotationQuarterTurns)
        let turned = turns != BookSplitter.normalizedTurns(old.taskOptions.bookRotationQuarterTurns)
        guard order || turned, settings.document.splitFacingPages, !splitSpreadIDs.isEmpty else { return }
        var changed: BookReorderOffer.Changed = order ? .order : .rotation
        if order && turned { changed = .both }
        if let before = bookReorderChanged, before != changed { changed = .both }
        bookReorderChanged = changed
    }

    /// "Not now": the spreads stay as they are. Changing an option again raises the offer again.
    public func dismissBookReorder() {
        bookReorderChanged = nil
    }

    /// The offer's Apply: every split spread in the queue is cut again where it is cut now, with the
    /// current reading order and rotation, as "Change the split" does one (`PageProcessor.processSpread`);
    /// the pages keep their document break, name and keep or skip (`BookPages.replacementPages`). The old
    /// pages wait in the hold of `undoRemove()`, so the whole reorder is one Undo. A spread that cannot be
    /// read keeps its pages.
    public func applyBookReorder() {
        guard !isBusy, !readsQueue, bookReorderOffer != nil else { return }
        let s = settings
        let scorer = orientationScorer
        let barcodes = barcodeReader
        let spool = spoolDirectory
        let previewSide = queuePreviewSide
        runExclusive { flag in
            // Turns and swaps clicked before must not land on pages about to be replaced.
            await self.pageEditChain?.value
            self.statusMessage = BookPages.reorderingStatus
            var fresh: [UUID: [ScannedPage]] = [:]
            var unread = 0
            do {
                for spreadID in self.splitSpreadIDs {
                    guard let page = self.scannedPages.first(where: { $0.spreadID == spreadID }),
                          let source = self.spreadSources[spreadID] else { continue }
                    let cut = page.spread?.gutter
                    let side = page.side
                    let sheetIndex = page.sheetIndex
                    let pages: [ScannedPage]? = try await Task.detached(priority: .userInitiated) { () throws -> [ScannedPage]? in
                        guard let image = Self.loadSpread(source) else { return nil }
                        var spread = ScannedPage(image: image, dpi: source.dpi, colorMode: s.colorMode, id: spreadID,
                                                 createdAt: source.createdAt)
                        spread.side = side
                        spread.sheetIndex = sheetIndex
                        let processed = try PageProcessor.forScan(s, arrangement: .asScanned, scorer: scorer, barcodes: barcodes)
                            .processSpread(spread, cut: cut, options: BookSplitOptions.of(s), shouldContinue: { !flag.isCancelled })
                        return Self.spoolPages(processed, to: spool, previewSide: previewSide)
                    }.value
                    if let pages, !pages.isEmpty {
                        fresh[spreadID] = pages
                    } else {
                        unread += 1
                    }
                }
            } catch {
                for pages in fresh.values { self.deleteSpoolFiles(of: pages) }
                throw error
            }
            guard !flag.isCancelled, !fresh.isEmpty else {
                for pages in fresh.values { self.deleteSpoolFiles(of: pages) }
                if flag.isCancelled { throw ScanError.cancelled }
                if unread > 0 { self.errorMessage = L10n.t("The spread could not be read.") }
                return
            }
            let before = self.scannedPages
            // What goes in the hold: the pages of the spreads cut again, each with the place it had once the
            // ones before it were gone (`holdRemoved`).
            var held: [(page: ScannedPage, index: Int)] = []
            for (index, page) in before.enumerated() {
                guard let spreadID = page.spreadID, fresh[spreadID] != nil else { continue }
                held.append((page: page, index: index - held.count))
            }
            var queue = before
            var added: [UUID] = []
            for (spreadID, pages) in fresh {
                let indices = queue.indices.filter { queue[$0].spreadID == spreadID }
                guard let firstIndex = indices.first else {
                    self.deleteSpoolFiles(of: pages)
                    continue
                }
                let old = indices.map { queue[$0] }
                var replacement = BookPages.replacementPages(old, fresh: pages)
                // A break or a name marks a place in the queue, so it stays there when the halves swap.
                if replacement.count == old.count {
                    for i in replacement.indices {
                        replacement[i] = replacement[i].withDocumentBreak(old[i].documentBreak).withDocumentLabel(old[i].documentLabel)
                    }
                }
                let kept = Set(replacement.map(\.id))
                self.deleteSpoolFiles(of: pages.filter { !kept.contains($0.id) })
                for index in indices.reversed() { queue.remove(at: index) }
                queue.insert(contentsOf: replacement, at: firstIndex)
                added.append(contentsOf: replacement.map(\.id))
            }
            self.discardRemovedUndo()
            self.scannedPages = queue
            self.removedUndo = RemovedUndo(pages: held, cleared: false, taskFlow: nil, cameraSides: nil,
                                           replacedBy: added, reordered: fresh.count)
            self.bookReorderChanged = nil
            self.statusMessage = BookPages.reorderedNote(fresh.count)
            if unread > 0 { self.errorMessage = L10n.t("The spread could not be read.") }
        }
    }

    /// Replaces the pages of the spread `id` is one of with the spread cut at `cut`, or whole.
    private func recutSpread(id: UUID, cut: (axis: GutterAxis, fraction: Double)?, flag: CancelFlag) async throws {
        let s = settings
        let scorer = orientationScorer
        let barcodes = barcodeReader
        let spool = spoolDirectory
        let previewSide = queuePreviewSide
        // Turns and swaps clicked before must not land on pages about to be replaced.
        await self.pageEditChain?.value
        guard let page = self.scannedPages.first(where: { $0.id == id }), let spreadID = page.spreadID,
              let source = self.spreadSources[spreadID] else { return }
        self.statusMessage = cut == nil ? L10n.t("Joining the pages…") : L10n.t("Splitting the spread…")
        // The spread keeps the sheet and side its pages were given. Its pages are made with the
        // current settings, color mode included: the adjustment step makes the pixels that mode
        // says (black & white thresholded at the user's level); when it does not run (color, no
        // adjustments) the pages are the spread as scanned, labelled color.
        let side = page.side
        let sheetIndex = page.sheetIndex
        let pages: [ScannedPage] = try await Task.detached(priority: .userInitiated) { () throws -> [ScannedPage] in
            guard let image = Self.loadSpread(source) else {
                throw ScanError.scanFailed(reason: { L10n.t("The spread could not be read.") })
            }
            var spread = ScannedPage(image: image, dpi: source.dpi, colorMode: s.colorMode, id: spreadID,
                                     createdAt: source.createdAt)
            spread.side = side
            spread.sheetIndex = sheetIndex
            let gutter = cut.map { BookSplitter.manual($0.axis, fraction: $0.fraction, width: image.width, height: image.height) }
            let processed = try PageProcessor.forScan(s, arrangement: .asScanned, scorer: scorer, barcodes: barcodes)
                .processSpread(spread, cut: gutter, options: BookSplitOptions.of(s), shouldContinue: { !flag.isCancelled })
            return Self.spoolPages(processed, to: spool, previewSide: previewSide)
        }.value
        let indices = self.scannedPages.indices.filter { self.scannedPages[$0].spreadID == spreadID }
        guard !flag.isCancelled, let firstIndex = indices.first, !pages.isEmpty else {
            self.deleteSpoolFiles(of: pages)
            if flag.isCancelled { throw ScanError.cancelled }
            return
        }
        // The new pages take what the user decided about the old ones; a part the user removed stays out.
        let removed = indices.map { self.scannedPages[$0] }
        let replacement = BookPages.replacementPages(removed, fresh: pages)
        let kept = Set(replacement.map(\.id))
        self.deleteSpoolFiles(of: pages.filter { !kept.contains($0.id) })
        // One change to the queue, so the spread is never without a page (`pruneSpreads`).
        var queue = self.scannedPages
        for index in indices.reversed() { queue.remove(at: index) }
        queue.insert(contentsOf: replacement, at: firstIndex)
        self.scannedPages = queue
        self.deleteSpoolFiles(of: removed)
        self.statusMessage = BookPages.splitNote(spreadNumber: self.spreadNumber(spreadID), split: cut != nil)
            + PageFilter.scanNote(replacement, options: s.document) + PageCorrections.scanNote(replacement)
            + PageTurns.scanNote(replacement)
    }
}
