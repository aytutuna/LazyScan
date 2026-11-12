import Foundation
import CoreGraphics

extension AppState {
    /// What "Save" on a history entry writes: a PDF, or the picture format chosen for the Save setting.
    public var historySaveFormat: OutputFormat { settings.format.pageFormat }

    /// Writes the page of `entry` to `url` (a place the user picked, so a file there is replaced) as
    /// `historySaveFormat`. Not a long operation of its own: it runs beside a scan and leaves the queue alone.
    public func saveHistoryPage(_ entry: ScanHistoryEntry, to url: URL) {
        guard let file = entry.pageFile, FileManager.default.fileExists(atPath: file.path) else {
            errorMessage = L10n.t("This scan's page is no longer available.")
            return
        }
        let s = settings
        let format = historySaveFormat
        let page = ScannedPage(image: entry.thumbnail, dpi: entry.dpi, colorMode: entry.colorMode,
                               fileURL: file, fullPixelSize: entry.pixelSize)
        Task { @MainActor in
            do {
                var options: PDFWriteOptions?
                if format == .pdf { options = try await pdfOptions(s, for: url) }
                let pdfOptions = options
                try await Task.detached(priority: .userInitiated) {
                    if format == .pdf {
                        let layer = Self.textLayer(searchable: s.pdfSearchable, collecting: nil, pages: [page])
                        try PDFBuilder.writePDF(pages: [page], pdfSize: s.output.pdfSize, to: url, progress: nil,
                                                textLayer: layer, options: pdfOptions)
                    } else {
                        let full = try Self.fullImage(of: page, number: 1)
                        try ImageExporter.write(full, to: url, format: format, dpi: page.dpi,
                                                jpegQuality: s.jpegQuality, colorMode: page.colorMode)
                    }
                }.value
                if let pdfOptions { notePDFSize(of: url, protected: pdfOptions.isProtected) }
                lastSavedURLs = [url]
                setStatus(TextExport.savedFilesMessage(fileNames: url.lastPathComponent, detail: nil, textFileName: nil),
                          StatusDetail(head: .saved))
            } catch is PDFPasswordNotGiven {
                statusMessage = PDFProtection.notSavedMessage
            } catch {
                errorMessage = error.localizedDescription
            }
            if !isBusy { forgetPDFPassword() }
        }
    }
}
