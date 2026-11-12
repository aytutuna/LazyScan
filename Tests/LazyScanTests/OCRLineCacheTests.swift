import XCTest
import CoreGraphics
@testable import LazyScanKit

// Mirrors windows/LazyScan.Core.Tests/OcrLineCacheTests.cs; the C# cache also keys on the OCR language and has no keep.

private func solidImage(_ value: CGFloat) -> CGImage {
    let ctx = CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: value, green: value, blue: value, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
    return ctx.makeImage()!
}

private func makePage() -> ScannedPage {
    ScannedPage(image: solidImage(0.5), dpi: 300, colorMode: .grayscale)
}

final class OCRLineCacheTests: XCTestCase {
    private let sample = [OCRLine(text: "Hello", boundingBox: CGRect(x: 0, y: 0, width: 1, height: 0.1), confidence: 0.9)]

    func test_keepsLinesForTheSamePage() {
        let cache = OCRLineCache()
        let page = makePage()
        XCTAssertNil(cache.lines(for: page))
        cache.store(sample, for: page)
        XCTAssertEqual(cache.lines(for: page)?.map(\.text), ["Hello"])
    }

    func test_keepsLinesWhenOnlyPageFactsChange() {
        let cache = OCRLineCache()
        let page = makePage()
        cache.store(sample, for: page)
        let marked = page.copyMeta(from: page)
        XCTAssertEqual(cache.lines(for: marked)?.map(\.text), ["Hello"])
    }

    func test_turningAPageReadsItAgain() {
        let cache = OCRLineCache()
        var page = makePage()
        cache.store(sample, for: page)
        page.rotationQuarterTurns = 1
        XCTAssertNil(cache.lines(for: page))
        page.rotationQuarterTurns = 0
        XCTAssertNotNil(cache.lines(for: page))
    }

    func test_otherPixelsReadAgain() {
        let cache = OCRLineCache()
        let page = makePage()
        cache.store(sample, for: page)
        XCTAssertNil(cache.lines(for: page.withImage(solidImage(0))))
    }

    func test_otherPagesAreNotAffected() {
        let cache = OCRLineCache()
        cache.store(sample, for: makePage())
        XCTAssertNil(cache.lines(for: makePage()))
    }

    func test_keepForgetsPagesLeftOutOfTheQueue() {
        let cache = OCRLineCache()
        let queued = makePage()
        let gone = makePage()
        cache.store(sample, for: queued)
        cache.store(sample, for: gone)
        cache.keep([queued.id])
        XCTAssertNotNil(cache.lines(for: queued))
        XCTAssertNil(cache.lines(for: gone))
    }

    func test_aRerunReadsOnlyThePagesAnInterruptedPassDidNot() {
        struct Stop: Error {}
        let cache = OCRLineCache()
        let pages = (0..<30).map { _ in makePage() }
        var reads = 0
        func pass(stopAt: Int) throws {
            for (index, page) in pages.enumerated() {
                if index == stopAt { throw Stop() }
                _ = cache.read(page) {
                    reads += 1
                    return sample
                }
            }
        }
        XCTAssertThrowsError(try pass(stopAt: 20))
        XCTAssertEqual(reads, 20)
        XCTAssertNoThrow(try pass(stopAt: -1))
        XCTAssertEqual(reads, 30)
    }
}
