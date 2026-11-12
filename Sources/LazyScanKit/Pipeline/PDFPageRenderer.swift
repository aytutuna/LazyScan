import Foundation

/// What opening a PDF for import found.
public enum PDFOpening: Equatable, Sendable {
    /// A readable PDF of this many pages (at least 1).
    case pages(Int)
    /// A password-protected PDF: nothing can be drawn without the password.
    case locked
    /// A file that is no PDF, a damaged one, or one without pages.
    case unreadable
}

/// Draws the pages of a PDF for import (`PhotoImport.isPdf`): PDFKit on the Mac (`MacPDFPages`), a stand-in
/// in tests. Each page comes back as a page of the queue, drawn at `PhotoImport.pdfResolution` on white with its
/// rotation applied, so its paper size survives a save (pixels / dpi).
public protocol PDFPageRenderer: Sendable {
    /// Opens the PDF in `data`.
    func open(_ data: Data) -> PDFOpening
    /// Page `index` (from 0) of the PDF in `data`; nil when there is no such page or it cannot be drawn.
    func page(_ data: Data, at index: Int) -> ScannedPage?
}
