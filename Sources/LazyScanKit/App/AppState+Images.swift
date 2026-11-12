import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

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
                    let planned: URL = try self.outputURL(fileExtension: format.fileExtension,
                                                          index: pages.count > 1 ? number : nil)
                    let quality: Double = s.jpegQuality
                    let pageNumber: Int = number
                    let url: URL = try await Task.detached(priority: .userInitiated) { () throws -> URL in
                        let full: CGImage = try Self.fullImage(of: page, number: pageNumber)
                        return try ImageExporter.write(full, to: planned, format: format, dpi: page.dpi,
                                                       jpegQuality: quality, colorMode: page.colorMode, keepingExisting: true)
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

    /// Writes `pages` as one TIFF at `url` (or the next free name when it has been taken), each page at
    /// its own resolution: CCITT G4 when every page is black & white (`BilevelTIFF`), else LZW through
    /// ImageIO. The file is written under a hidden temporary name first, so a failure or Cancel leaves
    /// nothing behind. Returns where the file went.
    nonisolated static func writeTIFFAtomically(pages: [ScannedPage], to url: URL,
                                                shouldContinue: (() -> Bool)? = nil) throws -> URL {
        let folder: URL = url.deletingLastPathComponent()
        let tmp: URL = folder.appendingPathComponent(".\(UUID().uuidString).tiff.tmp")
        do {
            if pages.allSatisfy({ $0.colorMode == .blackWhite }) {
                var bilevel: [BilevelTIFFPage] = []
                for (index, page) in pages.enumerated() {
                    if shouldContinue?() == false { throw ScanError.cancelled }
                    let full: CGImage = try fullImage(of: page, number: index + 1)
                    guard let pixels = RgbaImage(cgImage: full) else {
                        throw ScanError.exportFailed(L10n.t("Could not read the page to write {0}.", url.lastPathComponent))
                    }
                    bilevel.append(BilevelTIFFPage(image: pixels, dpi: page.dpi))
                }
                do {
                    try BilevelTIFF.make(bilevel).write(to: tmp, options: .atomic)
                } catch {
                    throw ScanError.exportFailed(SaveFailure.message(error, folder: folder))
                }
            } else {
                guard let destination = CGImageDestinationCreateWithURL(tmp as CFURL, UTType.tiff.identifier as CFString,
                                                                        pages.count, nil) else {
                    throw ScanError.exportFailed(SaveFailure.message(nil, folder: folder))
                }
                for (index, page) in pages.enumerated() {
                    if shouldContinue?() == false { throw ScanError.cancelled }
                    let full: CGImage = try fullImage(of: page, number: index + 1)
                    // 5 = LZW compression.
                    let properties: [CFString: Any] = [
                        kCGImagePropertyDPIWidth: page.dpi,
                        kCGImagePropertyDPIHeight: page.dpi,
                        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5],
                    ]
                    CGImageDestinationAddImage(destination, full, properties as CFDictionary)
                }
                guard CGImageDestinationFinalize(destination) else {
                    throw ScanError.exportFailed(SaveFailure.message(nil, folder: folder))
                }
            }
            return try NamingTemplate.moveToFreeURL(tmp, to: url)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw error
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
