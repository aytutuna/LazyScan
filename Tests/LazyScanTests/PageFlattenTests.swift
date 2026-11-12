import Foundation
import XCTest
@testable import LazyScanKit

final class PageFlattenTests: XCTestCase {
    private let width = 600
    private let height = 400
    private let paper: [UInt8] = [238, 234, 224]
    private let lineShares: [Double] = [0.15, 0.3, 0.45, 0.6, 0.75, 0.9]

    /// 0 at the ends of the page, 1 at its middle (the spine).
    private func bump(_ x: Int) -> Double {
        let u = Double(x) / Double(width - 1)
        return 4 * u * (1 - u)
    }

    /// A page on a dark table whose top and bottom edges dip `bend` pixels towards each other at the spine,
    /// with a line of text at every share of the way between its edges.
    private func curvedPage(bend: Double) -> RgbaImage {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let top = bend * bump(x)
                let bottom = Double(height - 1) - bend * bump(x)
                var color: [UInt8] = [50, 45, 40]
                if Double(y) >= top && Double(y) <= bottom {
                    color = paper
                    for share in lineShares where abs(Double(y) - (top + share * (bottom - top))) < 1.5 {
                        color = [30, 30, 30]
                    }
                }
                let i = (y * width + x) * 4
                pixels[i] = color[0]
                pixels[i + 1] = color[1]
                pixels[i + 2] = color[2]
            }
        }
        return RgbaImage(width: width, height: height, pixels: pixels)
    }

    /// The row of the dark line near `expected` in column x, to a tenth of a pixel; nil when there is none.
    private func lineRow(_ image: RgbaImage, x: Int, near expected: Double) -> Double? {
        var sum = 0.0
        var weight = 0.0
        let from = max(0, Int(expected) - 12), to = min(image.height - 1, Int(expected) + 12)
        for y in from...to {
            let dark = 128 - Double(image.pixels[(y * image.width + x) * 4])
            if dark > 0 {
                sum += dark * Double(y)
                weight += dark
            }
        }
        return weight > 0 ? sum / weight : nil
    }

    func test_flatten_drawsCurvedTextLinesStraight() throws {
        let page = curvedPage(bend: 30)
        // The fixture is bent: the first line sits well off its straight place at the spine.
        let straight = 0.15 * Double(height - 1)
        let bent = try XCTUnwrap(lineRow(page, x: width / 2, near: straight + 20))
        XCTAssertGreaterThan(abs(bent - straight), 0.01 * Double(height))

        let flat = try XCTUnwrap(PageFlatten.flatten(page))
        XCTAssertEqual(flat.width, width)
        XCTAssertEqual(flat.height, height)
        for share in lineShares {
            let expected = share * Double(height - 1)
            for x in stride(from: 20, to: width - 20, by: 10) {
                let row = try XCTUnwrap(lineRow(flat, x: x, near: expected), "x \(x), line \(share)")
                XCTAssertEqual(row, expected, accuracy: 0.01 * Double(height), "x \(x), line \(share)")
            }
        }
    }

    func test_flatten_leavesAPageWithADarkBannerAlongItsTopAlone() {
        var page = curvedPage(bend: 30)
        for y in 0..<80 {
            for x in 0..<(width / 2) {
                let i = (y * width + x) * 4
                page.pixels[i] = 50
                page.pixels[i + 1] = 45
                page.pixels[i + 2] = 40
            }
        }
        XCTAssertNil(PageFlatten.flatten(page))
    }

    func test_flatten_isRepeatable() {
        let page = curvedPage(bend: 24)
        XCTAssertNotNil(PageFlatten.flatten(page))
        XCTAssertEqual(PageFlatten.flatten(page), PageFlatten.flatten(page))
    }

    func test_flatten_leavesStraightAndEdgelessPagesAlone() {
        XCTAssertNil(PageFlatten.flatten(curvedPage(bend: 0)))
        XCTAssertNil(PageFlatten.flatten(curvedPage(bend: 1)))
        let full = RgbaImage.filled(width: width, height: height, r: paper[0], g: paper[1], b: paper[2])
        XCTAssertNil(PageFlatten.flatten(full))
        let dark = RgbaImage.filled(width: width, height: height, r: 40, g: 40, b: 40)
        XCTAssertNil(PageFlatten.flatten(dark))
    }

    // MARK: Fingers

    private let dpi = 150.0

    private func paperPage() -> RgbaImage {
        var page = RgbaImage.filled(width: 900, height: 600, r: paper[0], g: paper[1], b: paper[2])
        for row in stride(from: 150, to: 450, by: 30) {
            for y in row..<(row + 3) {
                for x in 250..<650 {
                    let i = (y * page.width + x) * 4
                    page.pixels[i] = 40
                    page.pixels[i + 1] = 40
                    page.pixels[i + 2] = 40
                }
            }
        }
        return page
    }

    private func paint(_ page: inout RgbaImage, _ color: [UInt8], where inside: (Int, Int) -> Bool) {
        for y in 0..<page.height {
            for x in 0..<page.width where inside(x, y) {
                let i = (y * page.width + x) * 4
                page.pixels[i] = color[0]
                page.pixels[i + 1] = color[1]
                page.pixels[i + 2] = color[2]
            }
        }
    }

    private func pixel(_ image: RgbaImage, _ x: Int, _ y: Int) -> [Int] {
        let i = (y * image.width + x) * 4
        return [Int(image.pixels[i]), Int(image.pixels[i + 1]), Int(image.pixels[i + 2])]
    }

    func test_fillFingers_paintsAThumbAtTheMarginWithPaper() throws {
        var page = paperPage()
        paint(&page, [214, 160, 130]) { x, y in
            let dx = Double(x) / 90, dy = Double(y - 300) / 70
            return dx * dx + dy * dy <= 1
        }
        XCTAssertEqual(pixel(page, 20, 300), [214, 160, 130])
        let filled = try XCTUnwrap(PageFlatten.fillFingers(page, dpi: dpi))
        for (x, y) in [(0, 300), (20, 300), (60, 280), (85, 300), (40, 340)] {
            let p = pixel(filled, x, y)
            for c in 0..<3 {
                XCTAssertLessThanOrEqual(abs(p[c] - Int(paper[c])), 4, "\(x), \(y)")
            }
        }
        // The text and the rest of the page are as they were.
        XCTAssertEqual(pixel(filled, 300, 151), [40, 40, 40])
        XCTAssertEqual(pixel(filled, 800, 100), pixel(page, 800, 100))
        XCTAssertEqual(pixel(filled, 450, 20), pixel(page, 450, 20))
    }

    func test_fillFingers_leavesPicturesThatRunPastTheBandAndPlainPagesAlone() {
        XCTAssertNil(PageFlatten.fillFingers(paperPage(), dpi: dpi))
        var page = paperPage()
        paint(&page, [214, 160, 130]) { x, y in x < 220 && y >= 100 && y < 220 }
        XCTAssertNil(PageFlatten.fillFingers(page, dpi: dpi))
        // A patch that does not touch the border is no finger.
        var island = paperPage()
        paint(&island, [214, 160, 130]) { x, y in x >= 30 && x < 90 && y >= 270 && y < 330 }
        XCTAssertNil(PageFlatten.fillFingers(island, dpi: dpi))
    }

    func test_fillFingers_ignoresPaperThatIsWarmAllOver() {
        var page = RgbaImage.filled(width: 900, height: 600, r: 225, g: 205, b: 160)
        paint(&page, [40, 40, 40]) { x, y in x >= 300 && x < 600 && y >= 200 && y < 203 }
        XCTAssertNil(PageFlatten.fillFingers(page, dpi: dpi))
    }

    // MARK: The book task's steps

    func test_aRecutWithAnotherFilterKeepsThePageFlat() throws {
        let photo = try XCTUnwrap(curvedPage(bend: 30).makeCGImage())
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: Double(width - 1), y: 0),
                       CGPoint(x: Double(width - 1), y: Double(height - 1)), CGPoint(x: 0, y: Double(height - 1))]
        var page = ScannedPage(image: photo, dpi: CaptureScale.nominalDPI, colorMode: .color)
            .withCapture(CaptureFacts(quad: Quad.fromCorners(corners), sourceWidth: width, sourceHeight: height))
        page.source = .photo
        let flat = FlattenStep().apply(PerspectiveStep().apply(page))
        XCTAssertEqual(flat.capture?.flattened, true)

        let recut = try XCTUnwrap(PageRecut.recut(flat, photo: photo, filter: .original))
        XCTAssertEqual(recut.capture?.flattened, true)
        XCTAssertEqual(RgbaImage(cgImage: recut.image)?.pixels, RgbaImage(cgImage: flat.image)?.pixels)
    }

    func test_forCapture_addsTheFlatteningStepsOnlyWhenAskedFor() {
        var s = TaskCatalog.apply(.book, to: ScanSettings())
        XCTAssertEqual(PageProcessor.forCapture(s).prepare.map(\.name), ["perspective", "enhance"])
        s.taskOptions.bookFlattenCurves = true
        XCTAssertTrue(PageProcessor.flattensCurvedPages(s))
        XCTAssertEqual(PageProcessor.forCapture(s).prepare.map(\.name), ["perspective", "flatten", "enhance"])
        s.taskOptions.bookFillFingers = true
        s.taskOptions.cameraSpreads = true
        XCTAssertEqual(PageProcessor.forCapture(s).prepare.map(\.name), ["perspective", "flatten", "fingers", "enhance"])
        // Not for another task.
        var document = TaskCatalog.apply(.document, to: ScanSettings())
        document.taskOptions.bookFlattenCurves = true
        document.taskOptions.bookFillFingers = true
        XCTAssertFalse(PageProcessor.flattensCurvedPages(document))
        XCTAssertFalse(PageProcessor.fillsFingers(document))
        XCTAssertEqual(PageProcessor.forCapture(document).prepare.map(\.name), ["perspective", "enhance"])
    }
}
