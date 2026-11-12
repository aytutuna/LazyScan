import CoreGraphics
import Foundation

/// Saving the collected pages as pictures, one file a page: the iPhone's "Save JPEG" (the Mac and Windows
/// save the queue as one PDF, Word document or text file; `OutputFormat.queueFormat`). Swift only, like
/// the other members the app shells use.
extension AppState {
    /// "Save JPEG", or "Save JPEG (3 pages)" for several pages: the button that saves the collected pages as
    /// pictures in `format` (its image format, `OutputFormat.imageFormatOrJPEG`).
    public nonisolated static func imagesSaveTitle(_ format: OutputFormat, pageCount: Int) -> String {
        let name: String = format.imageFormatOrJPEG.label
        if pageCount > 1 { return L10n.plural(pageCount, one: "Save {1} ({0} page)", other: "Save {1} ({0} pages)", name) }
        return L10n.t("Save {0}", name)
    }

    /// "Saved 3 JPEG files: Scan 2026-10-21 4 1.jpg …", the status after `saveImages()`.
    public nonisolated static func imagesSavedMessage(_ urls: [URL], format: OutputFormat) -> String {
        let name: String = format.imageFormatOrJPEG.label
        guard let first = urls.first else { return L10n.t("Saved nothing.") }
        if urls.count == 1 { return L10n.t("Saved {0}: {1}", name, first.lastPathComponent) }
        return L10n.plural(urls.count, one: "Saved {0} {1} file: {2} …", other: "Saved {0} {1} files: {2} …", name, first.lastPathComponent)
    }

    /// Saves the pages the queue would save (`SavePlan`: pages flagged in the strip are left out, now and
    /// only now) as pictures, one file a page in reading order, in the image format chosen
    /// (`settings.format.imageFormatOrJPEG`) at each page's resolution, named by the naming template
    /// with the page's number (`{index}`, appended when the template has none). The full pixels come from
    /// each page's spool file, turned as the page is shown. All or nothing: a failure or Cancel part-way
    /// removes the files written, and the queue stays as it was. Saved, the queue is emptied, the task's
    /// steps start over and the after-save action runs, as `savePDF()` does.
    public func saveImages(sides choice: SidesSaveChoice? = nil) {
        guard !scannedPages.isEmpty, settleSides(choice) else { return }
        let s: ScanSettings = settings
        let format: OutputFormat = s.format.imageFormatOrJPEG
        runExclusive { flag in
            // Let page swaps and turns that were clicked before the save land first.
            await self.pageEditChain?.value
            let queued: [ScannedPage] = self.scannedPages
            guard !queued.isEmpty else { return }
            let plan: SavePlan = SavePlan.make(queued, options: s.document)
            guard !plan.isEmpty else {
                self.errorMessage = PageFilter.nothingToSaveMessage
                self.errorTitle = PageFilter.nothingSavedTitle
                self.statusMessage = L10n.t("{0}.", DocumentSplitter.queueSummary(queued, options: s.document))
                return
            }
            var pages: [ScannedPage] = []
            for document in plan.documents {
                pages.append(contentsOf: document.pages)
            }
            let left: String = plan.leftOutNote()
            var saved: [URL] = []
            do {
                var number: Int = 1
                for page in pages {
                    if flag.isCancelled { throw ScanError.cancelled }
                    self.statusMessage = L10n.t("Saving page {0} of {1}…", number, pages.count)
                    let url: URL = try self.outputURL(fileExtension: format.fileExtension,
                                                      index: pages.count > 1 ? number : nil)
                    let quality: Double = s.jpegQuality
                    let pageNumber: Int = number
                    try await Task.detached(priority: .userInitiated) {
                        let full: CGImage = try Self.fullImage(of: page, number: pageNumber)
                        try ImageExporter.write(full, to: url, format: format, dpi: page.dpi,
                                                jpegQuality: quality, colorMode: page.colorMode)
                    }.value
                    saved.append(url)
                    number += 1
                }
            } catch {
                for url in saved {
                    try? FileManager.default.removeItem(at: url)
                }
                throw error
            }
            self.lastSavedURLs = saved
            self.dropSaved(queued, wrote: saved)
            self.resetFlow()
            self.setStatus(Self.imagesSavedMessage(saved, format: format) + left, StatusDetail(head: .saved))
            self.runAfterSave(s.output.afterSave, saved: saved)
        }
    }

    /// The full pixels of `page` as it is shown: its spool file turned by the page's rotation (the file
    /// stays unturned until it is saved), or the pixels in memory, which show the rotation already. A spooled
    /// page whose file cannot be read throws, naming page `number`.
    public nonisolated static func fullImage(of page: ScannedPage, number: Int) throws -> CGImage {
        guard let spooled = spoolImage(of: page) else {
            if page.fileURL != nil {
                throw ScanError.exportFailed(L10n.t("The picture of page {0} could not be written.", number))
            }
            return page.image
        }
        let turns: Int = ((page.rotationQuarterTurns % 4) + 4) % 4
        if turns == 0 { return spooled }
        return ImagePipeline.rotate(spooled, quarterTurns: turns)
    }
}
