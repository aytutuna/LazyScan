import Foundation

// Retake a queued page from the iPhone's page viewer. Swift only: the Windows app takes no camera shots.
// The camera is shown with the page marked (`retakingID`); the first page the next photo brings in takes
// its place in the queue and the old page's files go once the new one is in. Leaving the camera any other
// way (Cancel, the page deleted or moved, the queue saved or emptied) drops the mark and leaves the queue alone.

extension AppState {
    /// `page` came from a photo with capture facts (our camera, Photos or Files; not a PDF's page or a scan,
    /// and not half of a book's spread), so the camera can take it again.
    public nonisolated static func canRetake(_ page: ScannedPage) -> Bool {
        page.source == .photo && page.capture != nil && page.spread == nil
    }

    /// The next photo replaces page `id`; nothing happens when it cannot be taken again, or the queue is in use.
    public func startRetake(id: UUID) {
        guard !isBusy, !readsQueue, let page = scannedPages.first(where: { $0.id == id }), Self.canRetake(page) else { return }
        retakingID = id
    }

    /// The page stays as it is.
    public func cancelRetake() {
        retakingID = nil
    }

    /// The camera has said the page was retaken.
    public func clearRetaken() {
        retakenNumber = nil
    }

    /// The place of the page being retaken in the queue, from 1; nil when none is.
    public var retakingNumber: Int? {
        guard let id = retakingID, let index = scannedPages.firstIndex(where: { $0.id == id }) else { return nil }
        return index + 1
    }

    /// The first of `added`, which `queueScanned` put at the end of the queue, takes the place of the page
    /// being retaken: the same side, sheet, document break and name, and the camera's steps stay where they
    /// were. The old page's files are deleted. False, with nothing changed, when no retake is under way or the
    /// page is gone; the pages after the first stay at the end.
    func replaceRetaken(with added: [ScannedPage]) -> Bool {
        guard let oldID = retakingID, let fresh = added.first,
              let oldIndex = scannedPages.firstIndex(where: { $0.id == oldID }),
              let freshIndex = scannedPages.firstIndex(where: { $0.id == fresh.id }) else { return false }
        retakingID = nil
        let old: ScannedPage = scannedPages[oldIndex]
        var pages: [ScannedPage] = scannedPages
        var page: ScannedPage = pages.remove(at: freshIndex)
        page.side = old.side
        page.sheetIndex = old.sheetIndex
        page.documentBreak = old.documentBreak
        page.documentLabel = old.documentLabel
        pages[oldIndex] = page
        scannedPages = pages
        scanHistory.removeAll { $0.pageID == old.id }
        deleteSpoolFiles(of: [old])
        if var sides = cameraSides {
            sides.replaced(old.id, with: page.id)
            cameraSides = sides
        }
        statusMessage = L10n.t("Page {0} retaken", oldIndex + 1)
        retakenNumber = oldIndex + 1
        return true
    }
}
