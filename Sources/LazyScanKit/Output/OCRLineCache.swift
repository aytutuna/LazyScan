import Foundation

/// The lines OCR read on a page, kept so a save that is cancelled or fails does not read the pages
/// again: the next save, a change of format or Copy text takes them from here. A page's lines are good
/// for the same pixels, turn and resolution only (`ScannedPage.pixelsID`); any edit makes a page miss.
/// Twin of C# `OcrLineCache`, which also keys on the OCR language; Vision takes none.
final class OCRLineCache: @unchecked Sendable {
    static let shared = OCRLineCache()

    private struct Entry {
        let pixels: UUID
        let turns: Int
        let dpi: Int
        let lines: [OCRLine]
    }

    private var entries: [UUID: Entry] = [:]
    private let lock = NSLock()

    /// The lines read on `page`, or nil when it has none kept.
    func lines(for page: ScannedPage) -> [OCRLine]? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[page.id], entry.pixels == page.pixelsID,
              entry.turns == page.rotationQuarterTurns, entry.dpi == page.dpi else { return nil }
        return entry.lines
    }

    /// Whether any of `pages` has kept lines with text in them.
    func hasText(in pages: [ScannedPage]) -> Bool {
        pages.contains { (page: ScannedPage) -> Bool in
            (lines(for: page) ?? []).contains { (line: OCRLine) -> Bool in !line.text.isEmpty }
        }
    }

    func store(_ lines: [OCRLine], for page: ScannedPage) {
        lock.lock()
        defer { lock.unlock() }
        entries[page.id] = Entry(pixels: page.pixelsID, turns: page.rotationQuarterTurns, dpi: page.dpi, lines: lines)
    }

    /// The lines kept for `page`, else what `ocr` reads, kept for the next time. A page whose reading
    /// throws keeps nothing.
    func read(_ page: ScannedPage, _ ocr: () throws -> [OCRLine]) rethrows -> [OCRLine] {
        if let kept = lines(for: page) { return kept }
        let fresh = try ocr()
        store(fresh, for: page)
        return fresh
    }

    /// Forgets every page not in `ids`; the queue holds only those.
    func keep(_ ids: Set<UUID>) {
        lock.lock()
        defer { lock.unlock() }
        entries = entries.filter { ids.contains($0.key) }
    }
}
