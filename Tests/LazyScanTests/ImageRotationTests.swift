import ImageIO
import XCTest
@testable import LazyScanKit

final class ImageRotationTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageRotationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func picture(width: Int, height: Int) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func size(of url: URL) throws -> (width: Int, height: Int, dpi: Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap((props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue)
        let height = try XCTUnwrap((props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue)
        let dpi = try XCTUnwrap((props[kCGImagePropertyDPIWidth] as? NSNumber)?.intValue)
        return (width, height, dpi)
    }

    func test_rotateClockwise_swapsTheSidesAndKeepsFormatAndDpi() throws {
        for (name, format) in [("a.jpg", OutputFormat.jpeg), ("a.png", .png), ("a.tif", .tiff)] {
            let url = folder.appendingPathComponent(name)
            try ImageExporter.write(picture(width: 40, height: 20), to: url, format: format, dpi: 150, jpegQuality: 0.9)
            XCTAssertNil(ImageExporter.rotateClockwise(url), name)
            let after = try size(of: url)
            XCTAssertEqual(after.width, 20, name)
            XCTAssertEqual(after.height, 40, name)
            XCTAssertEqual(after.dpi, 150, name)
        }
    }

    func test_rotateClockwise_refusesAFileThatIsNotAPicture() throws {
        let text = folder.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: text)
        XCTAssertEqual(ImageExporter.rotateClockwise(text), L10n.t("This file type can't be rotated."))
        let broken = folder.appendingPathComponent("b.png")
        try Data("not a png".utf8).write(to: broken)
        XCTAssertEqual(ImageExporter.rotateClockwise(broken), L10n.t("The image could not be decoded."))
        XCTAssertEqual(try Data(contentsOf: broken), Data("not a png".utf8))
    }

    func test_rotateClockwise_leavesNoTempFileBeside() throws {
        let url = folder.appendingPathComponent("a.png")
        try ImageExporter.write(picture(width: 8, height: 4), to: url, format: .png, dpi: 72, jpegQuality: 0.9)
        XCTAssertNil(ImageExporter.rotateClockwise(url))
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(left, ["a.png"])
    }
}
