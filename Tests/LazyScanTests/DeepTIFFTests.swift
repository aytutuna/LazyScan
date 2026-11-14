import ImageIO
import XCTest
@testable import LazyScanKit

// Mirrors windows/LazyScan.Core.Tests/DeepTiffTests.cs (the same golden files and cases) and, for the files read
// back, windows/LazyScan.App.Tests/DeepTiffOutputTests.cs. See CONTRACTS.md, "16-bit TIFF".
final class DeepTIFFTests: XCTestCase {
    private let grayGolden = "49492a0010000000000001000001ffff0c000001040001000000020000000101040001000000020000000201030001000000100000000301030001000000010000000601030001000000010000001101040001000000080000001501030001000000010000001601040001000000020000001701040001000000080000001a01050001000000a60000001b01050001000000ae000000280103000100000002000000000000002c010000010000002c01000001000000"

    private let colorGolden = "49492a000e000000ffff008001000e000001040001000000010000000101040001000000010000000201030003000000cc0000000301030001000000010000000601030001000000020000000e01020005000000d20000001101040001000000080000001501030001000000030000001601040001000000010000001701040001000000060000001a01050001000000bc0000001b01050001000000c40000002801030001000000020000006987040001000000ec0000000000000096000000010000009600000001000000100010001000486900000000313938353a30373a32332030303a30303a30300001000390020014000000d800000000000000"

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func onePixelImage() -> CGImage {
        let ctx = CGContext(data: nil, width: 2, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 1))
        return ctx.makeImage()!
    }

    private func tempURL(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DeepTIFFTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    private func properties(_ url: URL) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    func test_gray_isOneUncompressedBlackIsZeroStripOf16BitSamples() {
        let pixels = DeepPixels(width: 2, height: 2, channels: 1, samples: [0, 1, 256, 65535])
        XCTAssertEqual(hex(DeepTIFF.make(pixels, dpi: 300)), grayGolden)
    }

    func test_color_hasThreeSamplesAndTheDetails() {
        let pixels = DeepPixels(width: 1, height: 1, channels: 3, samples: [65535, 32768, 1])
        let tiff = DeepTIFF.make(pixels, dpi: 150, details: PhotoDetails(year: 1985, month: 7, day: 23, caption: "Hi"))
        XCTAssertEqual(hex(tiff), colorGolden)
    }

    func test_details_areLeftOutWhenThereAreNone() {
        let pixels = DeepPixels(width: 2, height: 2, channels: 1, samples: [0, 1, 256, 65535])
        XCTAssertEqual(DeepTIFF.make(pixels, dpi: 300), DeepTIFF.make(pixels, dpi: 300, details: PhotoDetails()))
    }

    func test_onlyASinglePageTIFFIsWrittenHere() {
        XCTAssertTrue(DeepTIFF.applies(.tiff))
        XCTAssertFalse(DeepTIFF.applies(.tiffPages))
        XCTAssertFalse(DeepTIFF.applies(.png))
    }

    func test_imageIO_readsTheFilesBackAt16Bits() throws {
        let gray = try tempURL("gray.tif")
        try ImageExporter.write(onePixelImage(), to: gray, format: .tiff, dpi: 300, jpegQuality: 0.9,
                                deepPixels: DeepPixels(width: 2, height: 1, channels: 1, samples: [0, 65535]))
        let grayProps = try properties(gray)
        XCTAssertEqual(grayProps[kCGImagePropertyDepth] as? Int, 16)
        XCTAssertEqual((grayProps[kCGImagePropertyDPIWidth] as? NSNumber)?.intValue, 300)
        XCTAssertEqual((grayProps[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue, 2)

        let color = try tempURL("color.tif")
        try ImageExporter.write(onePixelImage(), to: color, format: .tiff, dpi: 600, jpegQuality: 0.9,
                                deepPixels: DeepPixels(width: 2, height: 1, channels: 3,
                                                       samples: [65535, 32768, 1, 0, 256, 65534]))
        XCTAssertEqual(try properties(color)[kCGImagePropertyDepth] as? Int, 16)
    }

    func test_withoutDeepPixels_orForAnotherFormat_theFileStays8Bit() throws {
        let plain = try tempURL("plain.tif")
        try ImageExporter.write(onePixelImage(), to: plain, format: .tiff, dpi: 300, jpegQuality: 0.9)
        XCTAssertEqual(try properties(plain)[kCGImagePropertyDepth] as? Int, 8)

        let png = try tempURL("deep.png")
        try ImageExporter.write(onePixelImage(), to: png, format: .png, dpi: 300, jpegQuality: 0.9,
                                deepPixels: DeepPixels(width: 2, height: 1, channels: 1, samples: [0, 65535]))
        XCTAssertEqual(try properties(png)[kCGImagePropertyDepth] as? Int, 8)
    }

    func test_keepingExisting_writesTheDeepFileToo() throws {
        let url = try tempURL("kept.tif")
        let written = try ImageExporter.write(onePixelImage(), to: url, format: .tiff, dpi: 300, jpegQuality: 0.9,
                                              deepPixels: DeepPixels(width: 2, height: 1, channels: 1, samples: [0, 65535]),
                                              keepingExisting: true)
        XCTAssertEqual(try properties(written)[kCGImagePropertyDepth] as? Int, 16)
    }

    private struct MarkStep: PageStep {
        let name = "mark"
        func apply(_ page: ScannedPage) -> ScannedPage {
            var marked = page
            marked.documentLabel = "marked"
            return marked
        }
    }

    func test_pageSteps_leaveAPageWithDeepPixelsAlone() throws {
        let processor = PageProcessor(steps: [MarkStep()])
        let plain = try processor.process([ScannedPage(image: onePixelImage(), dpi: 300, colorMode: .color)]).pages[0]
        var deep = ScannedPage(image: onePixelImage(), dpi: 300, colorMode: .color)
        let pixels = DeepPixels(width: 2, height: 1, channels: 1, samples: [1000, 2000])
        deep.deepPixels = pixels
        let kept = try processor.process([deep]).pages[0]
        XCTAssertEqual(plain.documentLabel, "marked")
        XCTAssertNil(kept.documentLabel)
        XCTAssertEqual(kept.deepPixels, pixels)
    }

    func test_deepPixels_surviveFactsAboutThePage_butNotOtherPixels() {
        var page = ScannedPage(image: onePixelImage(), dpi: 300, colorMode: .color)
        let pixels = DeepPixels(width: 2, height: 1, channels: 1, samples: [1000, 2000])
        page.deepPixels = pixels
        var kept = page
        kept.inclusion = .keep
        XCTAssertEqual(kept.deepPixels, pixels)
        XCTAssertEqual(page.copyMeta(from: page).deepPixels, pixels)
        XCTAssertNil(page.withImage(onePixelImage()).deepPixels)
    }

    func test_cropped_keepsTheRowsAndColumnsInsideTheRect() throws {
        let samples: [UInt16] = (0..<12).map { UInt16($0) }
        let pixels = DeepPixels(width: 2, height: 2, channels: 3, samples: samples)
        let part = try XCTUnwrap(pixels.cropped(to: CGRect(x: 1, y: 0, width: 5, height: 1)))
        XCTAssertEqual(part, DeepPixels(width: 1, height: 1, channels: 3, samples: [3, 4, 5]))
        XCTAssertNil(pixels.cropped(to: CGRect(x: 2, y: 0, width: 1, height: 1)))
    }

    func test_rotated_turnsTheSamplesByQuarterTurns() {
        let pixels = DeepPixels(width: 2, height: 1, channels: 3, samples: [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(pixels.rotated(quarterTurns: 0), pixels)
        XCTAssertEqual(pixels.rotated(quarterTurns: 1),
                       DeepPixels(width: 1, height: 2, channels: 3, samples: [1, 2, 3, 4, 5, 6]))
        XCTAssertEqual(pixels.rotated(quarterTurns: 2),
                       DeepPixels(width: 2, height: 1, channels: 3, samples: [4, 5, 6, 1, 2, 3]))
        XCTAssertEqual(pixels.rotated(quarterTurns: 3),
                       DeepPixels(width: 1, height: 2, channels: 3, samples: [4, 5, 6, 1, 2, 3]))
        XCTAssertEqual(pixels.rotated(quarterTurns: -1), pixels.rotated(quarterTurns: 3))
    }

    func test_photoFlow_asksForSixteenBitsOnlyForATiffInColorOrGray() {
        var s = ScanSettings()
        s.intent = .photo
        s.format = .tiff
        XCTAssertFalse(s.wantsHighBitDepth)
        s.photoHighBitDepth = true
        XCTAssertTrue(s.wantsHighBitDepth)
        s.colorMode = .grayscale
        XCTAssertTrue(s.wantsHighBitDepth)
        s.colorMode = .blackWhite
        XCTAssertFalse(s.wantsHighBitDepth)
        s.colorMode = .color
        s.source = .negatives
        XCTAssertFalse(s.wantsHighBitDepth)
        s.source = .flatbed
        s.adjustments.restoreFadedColors = true
        XCTAssertFalse(s.wantsHighBitDepth)
        s.adjustments.restoreFadedColors = false
        s.format = .png
        XCTAssertFalse(s.wantsHighBitDepth)
        s.format = .tiff
        s.intent = .document
        XCTAssertFalse(s.wantsHighBitDepth)
    }

    func test_wholePagePhoto_carriesThePagesSixteenBitPixels() {
        var page = ScannedPage(image: onePixelImage(), dpi: 300, colorMode: .color)
        let pixels = DeepPixels(width: 2, height: 1, channels: 3, samples: [1, 2, 3, 4, 5, 6])
        page.deepPixels = pixels
        var s = ScanSettings()
        s.photoAutoSplit = false
        XCTAssertEqual(AppState.splitPhotos(from: page, settings: s).first?.deepPixels, pixels)
    }
}
