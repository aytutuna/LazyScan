import Foundation

extension AppState {
    /// Shows the queued page `id` large on the canvas. Swift only: Windows builds the same state in its view model.
    public func viewPage(id: UUID) {
        guard scannedPages.contains(where: { $0.id == id }) else { return }
        viewedPageID = id
        viewsPage = true
    }

    /// Back to the overview or the last scan; the page last viewed stays picked.
    public func showPreview() {
        viewsPage = false
    }

    /// The canvas returns to the page last viewed, or shows the first page when none was picked yet.
    public func showPage() {
        guard let id = viewedPageID ?? scannedPages.first?.id else { return }
        viewPage(id: id)
    }

    /// The viewed page, and its place in the queue (1 for the first), while the canvas shows a page.
    public var viewedPage: (page: ScannedPage, number: Int)? {
        guard viewsPage, let id = viewedPageID,
              let index = scannedPages.firstIndex(where: { $0.id == id }) else { return nil }
        return (scannedPages[index], index + 1)
    }

    func resetPageView() {
        viewedPageID = nil
        viewsPage = false
    }

    /// A removed page that was viewed hands the canvas to the next page, else the previous one; an empty
    /// queue goes back to the preview.
    func keepViewedPage(after old: [ScannedPage]) {
        guard let id = viewedPageID, !scannedPages.contains(where: { $0.id == id }) else { return }
        guard let oldIndex = old.firstIndex(where: { $0.id == id }), !scannedPages.isEmpty else {
            resetPageView()
            return
        }
        let left = Set(scannedPages.map(\.id))
        let next = old[(oldIndex + 1)...].first { left.contains($0.id) }
        let previous = old[..<oldIndex].last { left.contains($0.id) }
        guard let target = next ?? previous else {
            resetPageView()
            return
        }
        viewedPageID = target.id
    }
}
