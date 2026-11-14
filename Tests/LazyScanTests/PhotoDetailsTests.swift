import ImageIO
import XCTest
@testable import LazyScanKit

private func makeSolidImage(width: Int, height: Int,
                            red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: 0, space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    return ctx.makeImage()!
}

private func makeTempDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("PhotoDetailsTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

// Mirrors windows/LazyScan.Core.Tests/PhotoDetailsTests.cs (the same cases for the values) and, for the
// files, windows/LazyScan.App.Tests/PhotoDetailsOutputTests.cs.
final class PhotoDetailsTests: XCTestCase {
    func test_yearAlone_datesTheFirstOfJanuary() {
        XCTAssertEqual(PhotoDetails(year: 1985).exifDate, "1985:01:01 00:00:00")
    }

    func test_yearMonthAndDay_areWritten() {
        XCTAssertEqual(PhotoDetails(year: 1985, month: 7, day: 23).exifDate, "1985:07:23 00:00:00")
    }

    func test_monthOrDayOutOfRange_countAsOne() {
        XCTAssertEqual(PhotoDetails(year: 1985, month: 13, day: 40).exifDate, "1985:01:01 00:00:00")
        XCTAssertEqual(PhotoDetails(year: 1985, month: 2, day: 30).exifDate, "1985:02:01 00:00:00")
        XCTAssertEqual(PhotoDetails(year: 1984, month: 2, day: 29).exifDate, "1984:02:29 00:00:00")
        XCTAssertEqual(PhotoDetails(year: 1985, month: 2, day: 29).exifDate, "1985:02:01 00:00:00")
    }

    func test_noFourDigitYear_hasNoDate() {
        XCTAssertNil(PhotoDetails().exifDate)
        XCTAssertNil(PhotoDetails(month: 5, day: 5).exifDate)
        XCTAssertNil(PhotoDetails(year: 85).exifDate)
        XCTAssertNil(PhotoDetails(year: 10000).exifDate)
    }

    func test_caption_isTrimmed_andBlankHasNone() {
        XCTAssertEqual(PhotoDetails(caption: "  Dad at the lake\n").exifCaption, "Dad at the lake")
        XCTAssertNil(PhotoDetails(caption: " \t ").exifCaption)
        XCTAssertNil(PhotoDetails().exifCaption)
    }

    private func tags(of url: URL) throws -> (date: String?, caption: String?) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        return (exif?[kCGImagePropertyExifDateTimeOriginal] as? String,
                (png?[kCGImagePropertyPNGDescription] as? String)
                    ?? tiff?[kCGImagePropertyTIFFImageDescription] as? String)
    }

    func test_savedImages_carryTheDateAndCaption_andNothingWithoutThem() throws {
        let image = makeSolidImage(width: 40, height: 30, red: 0.3, green: 0.7, blue: 0.4)
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let details = PhotoDetails(year: 1985, caption: "Dad at the lake")

        for format in [OutputFormat.jpeg, .png, .tiff] {
            let tagged = dir.appendingPathComponent("tagged.\(format.fileExtension)")
            try ImageExporter.write(image, to: tagged, format: format, dpi: 300, jpegQuality: 0.9, details: details)
            let found = try tags(of: tagged)
            XCTAssertEqual(found.date, "1985:01:01 00:00:00", "\(format.rawValue) date")
            XCTAssertEqual(found.caption, "Dad at the lake", "\(format.rawValue) caption")

            let plain = dir.appendingPathComponent("plain.\(format.fileExtension)")
            try ImageExporter.write(image, to: plain, format: format, dpi: 300, jpegQuality: 0.9)
            let none = try tags(of: plain)
            XCTAssertNil(none.date, "\(format.rawValue) date")
            XCTAssertNil(none.caption, "\(format.rawValue) caption")
        }
    }

    func test_blackAndWhiteTiff_carriesTheDateAndCaption() throws {
        let image = makeSolidImage(width: 40, height: 30, red: 0, green: 0, blue: 0)
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("bw.tif")
        try ImageExporter.write(image, to: url, format: .tiff, dpi: 300, jpegQuality: 0.9, colorMode: .blackWhite,
                                details: PhotoDetails(year: 1985, month: 7, day: 23, caption: "A"))
        let found = try tags(of: url)
        XCTAssertEqual(found.date, "1985:07:23 00:00:00")
        XCTAssertEqual(found.caption, "A")
    }
}
