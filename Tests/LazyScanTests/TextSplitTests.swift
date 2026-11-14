import XCTest
@testable import LazyScanKit

// Mirrors windows/LazyScan.Core.Tests/TextSplitTests.cs: the same page, the same numbers.

final class TextSplitTests: XCTestCase {
    private static let width = 240
    private static let height = 320

    private static func page(picture: Bool = false) -> TextSplit {
        TextSplit.split(EnhancerPages.shadowed(width: width, height: height, stamp: true, picture: picture), dpi: 300)
    }

    func testMaskHoldsThePrintAndTheStampAndNothingElse() {
        let split = TextSplitTests.page()
        XCTAssertEqual(split.width, TextSplitTests.width)
        XCTAssertEqual(split.height, TextSplitTests.height)
        XCTAssertEqual(split.mask.count, Bilevel.stride(TextSplitTests.width) * TextSplitTests.height)
        for y in 0..<TextSplitTests.height {
            for x in 0..<TextSplitTests.width {
                let ink: Bool = EnhancerPages.isInk(x, y, width: TextSplitTests.width, height: TextSplitTests.height)
                    || EnhancerPages.isStamp(x, y)
                XCTAssertEqual(Bilevel.isBlack(split.mask, width: TextSplitTests.width, x: x, y: y), ink, "(\(x), \(y))")
            }
        }
    }

    func testBackgroundIsAHundredDpiAndFreeOfInk() {
        let split = TextSplitTests.page()
        XCTAssertEqual(split.background.width, 80)
        XCTAssertEqual(split.background.height, 107)
        // The shadow darkens the paper toward the bottom right, so the background there is darker, but
        // never as dark as print (luma 40 of 255 under the same light) or the stamp.
        let px: [UInt8] = split.background.pixels
        var p: Int = 0
        while p < px.count {
            XCTAssertTrue(px[p] >= 80 && px[p + 1] >= 80 && px[p + 2] >= 70, "pixel \(p / 4)")
            XCTAssertEqual(px[p + 3], 255)
            p += 4
        }
    }

    func testABlankPageHasNoInk() {
        let split = TextSplit.split(RgbaImage.filled(width: 100, height: 60, r: 230, g: 226, b: 210), dpi: 200)
        XCTAssertTrue(split.mask.allSatisfy { $0 == 0xFF })
        XCTAssertEqual(split.background.width, 50)
        XCTAssertEqual(split.background.height, 30)
        XCTAssertEqual(split.background.pixels[0], 230)
    }

    func testBackgroundUnderAPictureIsFilledFromThePaperAround() {
        let split = TextSplitTests.page(picture: true)
        // The dark picture is cut out with the ink, so it lands in the mask and is wiped from the background.
        // The picture (x 40-139, y 200-289) is at 100 dpi about 13-46, 67-96 in the background.
        let o: Int = (80 * 80 + 30) * 4
        XCTAssertGreaterThan(split.background.pixels[o], 100)
    }

    func testFixturePins() {
        let split = TextSplitTests.page()
        var black: Int = 0
        for y in 0..<TextSplitTests.height {
            for x in 0..<TextSplitTests.width where Bilevel.isBlack(split.mask, width: TextSplitTests.width, x: x, y: y) {
                black += 1
            }
        }
        let px: [UInt8] = split.background.pixels
        let mid: Int = (50 * 80 + 40) * 4
        let last: Int = px.count - 4
        XCTAssertEqual(black, 10292)
        XCTAssertEqual(Array(px[0..<3]), [231, 225, 211])
        XCTAssertEqual(Array(px[mid..<(mid + 3)]), [159, 155, 145])
        XCTAssertEqual(Array(px[last..<(last + 3)]), [87, 85, 80])
    }
}
