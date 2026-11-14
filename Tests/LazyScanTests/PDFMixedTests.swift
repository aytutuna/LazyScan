import XCTest
import PDFKit
@testable import LazyScanKit

// Mirrors windows/LazyScan.Core.Tests/PdfMixedTests.cs: the same page, the same numbers. Color pages at
// Compact and Smallest as a text mask over a background.

final class PDFMixedTests: XCTestCase {
    private static let width = 240
    private static let height = 320

    private static func page() -> RgbaImage {
        EnhancerPages.shadowed(width: width, height: height, stamp: false, picture: false)
    }

    /// Every luma value in turn, so almost all of the page is ink.
    private static func noise() -> RgbaImage {
        var pixels: [UInt8] = [UInt8](repeating: 255, count: width * height * 4)
        for p in 0..<(width * height) {
            let v = UInt8((p * 37 + p / width * 91) % 256)
            pixels[p * 4] = v
            pixels[p * 4 + 1] = v
            pixels[p * 4 + 2] = v
        }
        return RgbaImage(width: width, height: height, pixels: pixels)
    }

    private static func split(_ image: RgbaImage, dpi: Int, mode: ColorMode = .color,
                              size: PDFSizePreset) -> (split: TextSplit, g4: [UInt8])? {
        PDFImageEncoding.splitPage(rgba: image.pixels, width: image.width, height: image.height, imageDPI: dpi,
                                   mode: mode, size: size)
    }

    private static func mixed() throws -> (image: PDFImageData, g4: [UInt8]) {
        let page = try XCTUnwrap(split(Self.page(), dpi: 300, size: .smallest))
        return (.mixed(background: PDFWriterTests.tinyJPEGData, mask: Data(page.g4), maskWidth: page.split.width,
                       maskHeight: page.split.height), page.g4)
    }

    func testOnlyCompactAndSmallestKeepATextMask() {
        for size in PDFSizePreset.allCases {
            let expected: Bool = size == .compact || size == .smallest
            XCTAssertEqual(PDFImageEncoding.profile(size).textMask, expected, "\(size)")
        }
    }

    func testASplitColorPageIsTheTextSplitWithItsMaskAsG4() throws {
        let image = Self.page()
        let result = try XCTUnwrap(Self.split(image, dpi: 300, size: .smallest))
        let direct = TextSplit.split(image, dpi: 300)
        XCTAssertEqual(result.split.mask, direct.mask)
        XCTAssertEqual(result.split.background.pixels, direct.background.pixels)
        let expected: [UInt8] = try CCITTG4Encoder.encode(direct.mask, width: Self.width, height: Self.height)
        XCTAssertEqual(result.g4, expected)
        XCTAssertGreaterThanOrEqual(result.g4.count, 1)
        XCTAssertLessThanOrEqual(result.g4.count, Self.width * Self.height / 80)
    }

    func testAFinePageIsSplitAtTheBlackAndWhiteLimit() throws {
        let result = try XCTUnwrap(Self.split(Self.page(), dpi: 600, size: .compact))
        XCTAssertEqual(result.split.width, 120)
        XCTAssertEqual(result.split.height, 160)
        XCTAssertEqual(result.split.background.width, 40)
    }

    func testOtherPagesAreNotSplit() {
        let cases: [(PDFSizePreset, ColorMode)] = [(.best, .color), (.standard, .color), (.smallest, .grayscale),
                                                   (.smallest, .blackWhite), (.compact, .grayscale)]
        for (size, mode) in cases {
            XCTAssertNil(Self.split(Self.page(), dpi: 300, mode: mode, size: size), "\(size) \(mode)")
        }
    }

    func testAPageThatIsNotTextIsNotSplit() {
        XCTAssertNil(Self.split(Self.noise(), dpi: 300, size: .smallest))
    }

    func testAPageWithColoredInkIsNotSplit() {
        let red = EnhancerPages.shadowed(width: Self.width, height: Self.height, stamp: true, picture: false)
        XCTAssertNil(Self.split(red, dpi: 300, size: .smallest))
    }

    func testAMixedPageIsNoLargerThanThePlainJPEGPage() throws {
        let image = EnhancerPages.shadowed(width: 1275, height: 1650, stamp: false, picture: false)
        let result = try XCTUnwrap(Self.split(image, dpi: 150, size: .smallest))
        let background = try XCTUnwrap(PDFImageEncoding.encodedBackground(result.split.background, size: .smallest))
        let cg = try XCTUnwrap(image.makeCGImage())
        let plain = try XCTUnwrap(PDFImageEncoding.encodedPage(cg, imageDPI: 150, mode: .color, size: .smallest))
        XCTAssertLessThanOrEqual(background.count + result.g4.count, plain.jpegData.count)
    }

    func testMixedPageDrawsTheMaskInBlackOverTheBackground() throws {
        let stored = try Self.mixed()
        let page = PDFPageInput(image: stored.image, pixelWidth: Self.width, pixelHeight: Self.height, dpi: 300,
                                ocrLines: nil)
        let pdf = try PDFWriter.make([page])
        // Catalog, pages, info, then the page, its image and contents; the mask comes after the pages.
        XCTAssertTrue(PDFWriterTests.has(pdf, "/Resources <</XObject <</Im0 5 0 R /Mk0 7 0 R>>>>"))
        XCTAssertTrue(PDFWriterTests.has(pdf, "7 0 obj\n<</Type /XObject /Subtype /Image /Width \(Self.width) "
            + "/Height \(Self.height) /ImageMask true /BitsPerComponent 1 /Filter /CCITTFaxDecode "
            + "/DecodeParms <</K -1 /Columns \(Self.width) /Rows \(Self.height) /BlackIs1 false>> "
            + "/Length \(stored.g4.count)>>\nstream\n"))
        XCTAssertTrue(PDFWriterTests.has(pdf, "/Im0 Do\n0 g\n/Mk0 Do\nQ\n"))
        XCTAssertTrue(PDFWriterTests.has(pdf, "/ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /DCTDecode"))
        let start = try XCTUnwrap(PDFWriterTests.offset(pdf, "/ImageMask"))
        let data = try XCTUnwrap(PDFWriterTests.offset(pdf, "stream\n", from: start)) + "stream\n".utf8.count
        XCTAssertEqual(pdf.subdata(in: data..<(data + stored.g4.count)), Data(stored.g4))
        XCTAssertEqual(PDFDocument(data: pdf)?.pageCount, 1)
    }

    func testMixedPagesNumberTheirMasksInPageOrder() throws {
        let stored = try Self.mixed()
        let mixed = PDFPageInput(image: stored.image, pixelWidth: Self.width, pixelHeight: Self.height, dpi: 300,
                                 ocrLines: nil)
        let plain = PDFPageInput(jpegData: PDFWriterTests.tinyJPEGData, pixelWidth: 100, pixelHeight: 150, dpi: 300,
                                 ocrLines: nil)
        let pdf = try PDFWriter.make([mixed, plain, mixed])
        XCTAssertTrue(PDFWriterTests.has(pdf, "/XObject <</Im0 5 0 R /Mk0 13 0 R>>"))
        XCTAssertTrue(PDFWriterTests.has(pdf, "/XObject <</Im1 8 0 R>>"))
        XCTAssertTrue(PDFWriterTests.has(pdf, "/XObject <</Im2 11 0 R /Mk2 14 0 R>>"))
        XCTAssertEqual(PDFDocument(data: pdf)?.pageCount, 3)
    }

    func testPDFAWithAMixedPageKeepsItsStructure() throws {
        let stored = try Self.mixed()
        let page = PDFPageInput(image: stored.image, pixelWidth: Self.width, pixelHeight: Self.height, dpi: 300,
                                ocrLines: nil)
        let pdf = try PDFWriter.make([page], options: PDFWriteOptions(conformance: .pdfA2b, title: "Karma sayfa"))
        XCTAssertEqual(PDFWriterTests.text(pdf, at: 0, count: 9), "%PDF-1.7\n")
        XCTAssertTrue(PDFWriterTests.has(pdf, "/OutputIntents"))
        XCTAssertTrue(PDFWriterTests.has(pdf, "/ImageMask true"))
        XCTAssertEqual(PDFDocument(data: pdf)?.pageCount, 1)
    }

    func testProtectedMixedPageOpensWithThePassword() throws {
        let stored = try Self.mixed()
        let page = PDFPageInput(image: stored.image, pixelWidth: Self.width, pixelHeight: Self.height, dpi: 300,
                                ocrLines: nil)
        let protection = try PDFProtection("Şifre 2026")
        let pdf = try PDFWriter.make([page], options: PDFWriteOptions(protection: protection))
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        XCTAssertTrue(document.isLocked)
        XCTAssertTrue(document.unlock(withPassword: "Şifre 2026"))
        XCTAssertEqual(document.pageCount, 1)
    }

    func testAppendedMixedPageIsReadBack() throws {
        let stored = try Self.mixed()
        let original = try PDFWriter.make([PDFPageInput(jpegData: PDFWriterTests.tinyJPEGData, pixelWidth: 850,
                                                        pixelHeight: 1100, dpi: 100, ocrLines: nil)])
        let page = PDFPageInput(image: stored.image, pixelWidth: Self.width, pixelHeight: Self.height, dpi: 300,
                                ocrLines: nil)
        let appended = try PDFAppender.append(original, pages: [page])
        XCTAssertEqual(appended.prefix(original.count), original)
        XCTAssertTrue(PDFWriterTests.has(Data(appended[original.count...]), "/ImageMask true"))
        XCTAssertEqual(PDFDocument(data: appended)?.pageCount, 2)
    }

    func testMixedPageGoldenBytes() throws {
        // PdfMixedTests.Pdf_MixedPage_GoldenBytes: the same bytes as C# writes.
        let stored = try Self.mixed()
        let mixed = PDFPageInput(image: stored.image, pixelWidth: Self.width, pixelHeight: Self.height, dpi: 300,
                                 ocrLines: nil)
        let jpeg = PDFPageInput(jpegData: PDFWriterTests.tinyJPEGData, pixelWidth: 850, pixelHeight: 1100, dpi: 100,
                                ocrLines: nil)
        let options = PDFWriteOptions(title: "Karma sayfa", creationDate: Date(timeIntervalSince1970: 1_792_434_605),
                                      timeZone: TimeZone(secondsFromGMT: 3 * 3600), documentId: Array(0xA0..<0xB0))
        let pdf = try PDFWriter.make([mixed, jpeg], options: options)
        XCTAssertEqual(pdf.count, 2565)
        XCTAssertEqual(CompanionPackage.sha256Hex(pdf).uppercased(),
                       "0105040C139E7FF70AE916665FCA3BEC0EF19469395D8FB2F716C8FE5D92F3E3")
    }

    func testPDFBuilderStoresAColorPageAtTheSmallestSizeAsMaskAndBackground() throws {
        let image = try XCTUnwrap(Self.page().makeCGImage())
        let page = ScannedPage(image: image, dpi: 300, colorMode: .color)
        let pdf = try PDFBuilder.makePDF(pages: [page], pdfSize: .smallest, progress: nil, textLayer: nil)
        XCTAssertTrue(PDFWriterTests.has(pdf, "/ImageMask true"))
        XCTAssertEqual(PDFWriterTests.count(pdf, "/DCTDecode"), 1)
        XCTAssertEqual(PDFDocument(data: pdf)?.pageCount, 1)
        let standard = try PDFBuilder.makePDF(pages: [page], pdfSize: .standard, progress: nil, textLayer: nil)
        XCTAssertFalse(PDFWriterTests.has(standard, "/ImageMask"))
    }
}
