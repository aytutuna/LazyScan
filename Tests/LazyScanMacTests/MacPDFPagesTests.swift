#if os(macOS)
import CoreGraphics
import Foundation
import XCTest
@testable import LazyScanKit
@testable import LazyScanMac

// The PDFKit renderer behind the Mac's PDF import: page count, the 300 dpi drawing, the lower resolution of a
// poster, and the files that are refused.

final class MacPDFPagesTests: XCTestCase {
    /// A PDF with one page per size in points; `password` makes it a protected file.
    private func makePDF(sizes: [CGSize], password: String? = nil) -> Data {
        let data = NSMutableData()
        var info: [CFString: Any] = [:]
        if let password {
            info[kCGPDFContextUserPassword] = password
            info[kCGPDFContextOwnerPassword] = password
        }
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary)!
        for size in sizes {
            var page = CGRect(origin: .zero, size: size)
            context.beginPDFPage([kCGPDFContextMediaBox: Data(bytes: &page, count: MemoryLayout<CGRect>.size)] as CFDictionary)
            context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 10, y: 10, width: size.width / 2, height: 20))
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    func test_openCountsThePages_andTurnsDownLockedAndDamagedFiles() {
        let renderer = MacPDFPages()
        XCTAssertEqual(renderer.open(makePDF(sizes: [CGSize(width: 612, height: 792), CGSize(width: 792, height: 612)])), .pages(2))
        XCTAssertEqual(renderer.open(makePDF(sizes: [CGSize(width: 612, height: 792)], password: "secret")), .locked)
        XCTAssertEqual(renderer.open(Data("not a pdf".utf8)), .unreadable)
    }

    func test_aPageIsDrawnAt300DpiOnWhite() throws {
        let data = makePDF(sizes: [CGSize(width: 612, height: 792)])
        let page = try XCTUnwrap(MacPDFPages().page(data, at: 0))
        XCTAssertEqual(page.dpi, 300)
        XCTAssertEqual(page.image.width, 2550)
        XCTAssertEqual(page.image.height, 3300)
        XCTAssertEqual(page.source, .photo)
        XCTAssertNil(MacPDFPages().page(data, at: 1))
    }

    func test_aPosterIsDrawnAtTheResolutionThatFits() throws {
        let data = makePDF(sizes: [CGSize(width: 3000, height: 1500)])
        let page = try XCTUnwrap(MacPDFPages().page(data, at: 0))
        XCTAssertEqual(page.dpi, 168)
        XCTAssertEqual(page.image.width, 7000)
        XCTAssertEqual(page.image.height, 3500)
    }
}
#endif
