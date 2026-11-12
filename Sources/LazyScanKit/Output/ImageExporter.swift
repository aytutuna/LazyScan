import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageExporter {
    /// Write jpeg/png/tiff with DPI metadata. Throws ScanError.unsupported for .pdf, .text and .word.
    /// A black & white page (`colorMode`, the mode it was scanned in) saved as TIFF is a 1-bit CCITT
    /// G4 file (`BilevelTIFF`); everything else is written by ImageIO, TIFFs as LZW. Twin of C#
    /// `WpfImageCodec.SaveAsNew`'s choice.
    /// With `keepingExisting` the picture is written to a hidden temp name and moved to `url` (or the next
    /// free name when `url` has been taken meanwhile), so a failed write leaves no file under a real name
    /// and nothing is replaced; returns where the file went.
    @discardableResult
    public static func write(_ image: CGImage, to url: URL, format: OutputFormat, dpi: Int, jpegQuality: Double,
                             colorMode: ColorMode = .color, keepingExisting: Bool = false) throws -> URL {
        guard keepingExisting else {
            try encode(image, to: url, format: format, dpi: dpi, jpegQuality: jpegQuality, colorMode: colorMode)
            return url
        }
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        do {
            try encode(image, to: tmp, format: format, dpi: dpi, jpegQuality: jpegQuality, colorMode: colorMode,
                       shownAs: url)
            return try NamingTemplate.moveToFreeURL(tmp, to: url)
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            throw error
        }
    }

    private static func encode(_ image: CGImage, to url: URL, format: OutputFormat, dpi: Int, jpegQuality: Double,
                               colorMode: ColorMode, shownAs: URL? = nil) throws {
        let shown = shownAs ?? url
        let fileName = shown.lastPathComponent
        let folder = shown.deletingLastPathComponent()
        let utType: UTType
        switch format {
        case .jpeg: utType = .jpeg
        case .png: utType = .png
        case .tiff, .tiffPages: utType = .tiff
        case .pdf: throw ScanError.unsupported("Use PDFBuilder to write PDF files.")
        case .text, .word: throw ScanError.unsupported("Use TextExport or DocxWriter to write text.")
        }

        if BilevelTIFF.applies(format, colorMode) {
            guard let pixels = RgbaImage(cgImage: image) else {
                throw ScanError.exportFailed(L10n.t("Could not read the page to write {0}.", fileName))
            }
            do {
                try BilevelTIFF.make(pixels, dpi: dpi).write(to: url, options: .atomic)
            } catch {
                throw ScanError.exportFailed(SaveFailure.message(error, folder: folder))
            }
            return
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
                                                                utType.identifier as CFString,
                                                                1, nil) else {
            throw ScanError.exportFailed(SaveFailure.message(nil, folder: folder))
        }

        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        switch format {
        case .jpeg:
            properties[kCGImageDestinationLossyCompressionQuality] = jpegQuality
        case .tiff, .tiffPages:
            // 5 = LZW compression.
            properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFCompression: 5]
        case .png, .pdf, .text, .word:
            break
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ScanError.exportFailed(SaveFailure.message(nil, folder: folder))
        }
    }
}
