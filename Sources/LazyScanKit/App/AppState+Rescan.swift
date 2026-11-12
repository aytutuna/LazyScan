import Foundation

// Scan Again on the Mac's page strip: the next scan takes the place of a page instead of going to the
// end of the queue.

extension AppState {
    /// Whether the next scanner scan goes to the queue, the only scan that can replace a page.
    var queuesScans: Bool {
        TaskCatalog.flow(of: settings) == .documentQueue && settings.documentMultiPage
    }

    /// Whether Scan Again is offered on a page.
    public var canRescan: Bool { !isBusy && queuesScans && !isStackUnderWay }

    /// Marks the page the next scan replaces; marking another page moves the mark.
    public func armRescan(id: UUID) {
        guard canRescan, scannedPages.contains(where: { $0.id == id }) else { return }
        rescanTarget = id
    }

    public func cancelRescan() {
        rescanTarget = nil
    }

    /// Queues the pages of a scan. When a page is marked the scanner's first page takes its place (the old
    /// one waits in `undoRemove()`) and the rest follow it, also the ones that arrive in later calls of the
    /// same scan; otherwise they go to the end.
    func queueScanned(_ pages: [ScannedPage], source: PageSource) {
        guard source == .scanner, let last = pages.last else {
            scannedPages.append(contentsOf: pages)
            return
        }
        if let anchor = rescanAnchor, let index = scannedPages.firstIndex(where: { $0.id == anchor }) {
            scannedPages.insert(contentsOf: pages, at: index + 1)
            rescanAnchor = last.id
        } else if let target = rescanTarget, let index = scannedPages.firstIndex(where: { $0.id == target }) {
            scannedPages.insert(contentsOf: pages, at: index + 1)
            holdRemoved([target])
            rescanAnchor = last.id
        } else {
            scannedPages.append(contentsOf: pages)
        }
    }
}
