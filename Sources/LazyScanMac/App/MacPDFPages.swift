#if os(macOS)
import LazyScanKit
import CoreGraphics
import Foundation
import PDFKit

/// Draws the pages of an imported PDF with PDFKit at `PhotoImport.pdfDPI` on white, the page's rotation
/// applied; a page so large that its long side would pass `PhotoImport.pdfMaxLongSide` pixels is drawn at
/// the resolution that fits, recorded on the page.
struct MacPDFPages: PDFPageRenderer {
    func open(_ data: Data) -> PDFOpening {
        guard let document = PDFDocument(data: data) else { return .unreadable }
        if document.isLocked { return .locked }
        return document.pageCount > 0 ? .pages(document.pageCount) : .unreadable
    }

    func page(_ data: Data, at index: Int) -> ScannedPage? {
        guard let document = PDFDocument(data: data), !document.isLocked,
              index >= 0, index < document.pageCount, let page = document.page(at: index),
              let pageRef = page.pageRef else { return nil }
        let size = Self.shownSize(page)
        let dpi = PhotoImport.pdfResolution(widthPoints: Double(size.width), heightPoints: Double(size.height))
        let scale = Double(dpi) / 72.0
        let pixelWidth = max(1, Int((Double(size.width) * scale).rounded()))
        let pixelHeight = max(1, Int((Double(size.height) * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.interpolationQuality = .high
        context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        // The page's crop box moved to the origin with its rotation applied, at its shown size in points.
        let target = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        context.concatenate(pageRef.getDrawingTransform(.cropBox, rect: target, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(pageRef)
        guard let image = context.makeImage() else { return nil }
        var drawn = ScannedPage(image: image, dpi: dpi, colorMode: .color)
        drawn.source = .photo
        return drawn
    }

    /// The page's size in points as it is shown: its crop box, turned by its rotation.
    static func shownSize(_ page: PDFPage) -> CGSize {
        let box = page.bounds(for: .cropBox)
        let turns = ((page.rotation / 90) % 4 + 4) % 4
        return turns % 2 == 1 ? CGSize(width: box.height, height: box.width) : box.size
    }
}
#endif
