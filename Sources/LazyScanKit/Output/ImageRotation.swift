import CoreGraphics
import Foundation
import ImageIO

extension ImageExporter {
    /// Turns a saved JPEG, PNG or TIFF 90 degrees clockwise in place, keeping its format and DPI (a
    /// black & white TIFF stays CCITT G4). The turned copy is written beside the file and swapped in
    /// atomically, so a failed write never loses the only copy; a multi-page TIFF is refused rather than
    /// cut to its first page. Returns why it failed, worded for the user, or nil. Twin of the Windows
    /// `SavedFiles.RotateFile`'s result texts; the caller must not run two turns of one file at once.
    public static func rotateClockwise(_ url: URL) -> String? {
        let format: OutputFormat
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": format = .jpeg
        case "png": format = .png
        case "tif", "tiff": format = .tiff
        default: return L10n.t("This file type can't be rotated.")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return L10n.t("The file could not be read.")
        }
        let count: Int = CGImageSourceGetCount(source)
        guard count > 0 else {
            return L10n.t("The image could not be decoded.")
        }
        guard count == 1 else {
            return L10n.t("It has multiple pages \u{2014} rotate it in another app instead.")
        }
        // The full-size decode has the EXIF orientation applied, so the pixels match what is seen.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 100_000,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return L10n.t("The image could not be decoded.")
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi: Int = (props?[kCGImagePropertyDPIWidth] as? NSNumber)?.intValue ?? 300
        let depth: Int = (props?[kCGImagePropertyDepth] as? NSNumber)?.intValue ?? 8
        let mode: ColorMode = format == .tiff && depth == 1 ? .blackWhite : .color
        let rotated: CGImage = ImagePipeline.rotate(image, quarterTurns: 1)
        let temp: URL = url.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).\(url.pathExtension)")
        do {
            // High quality to limit the loss of turning a JPEG again and again.
            try write(rotated, to: temp, format: format, dpi: dpi, jpegQuality: 0.95, colorMode: mode)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
            return nil
        } catch {
            try? FileManager.default.removeItem(at: temp)
            return L10n.t("The rotated copy could not be written.")
        }
    }
}
