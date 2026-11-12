#if os(macOS)
import CoreGraphics
import XCTest
@testable import LazyScanMac

// The zoom and pan of the page view (PageZoom.swift): Fit, 100%, the limits, and the page point under the pointer.

final class PageZoomGeometryTests: XCTestCase {
    /// A 2000 x 3000 px page in a 1000 x 800 pt canvas on a 2x screen: Fit shows it at 25%.
    private let tall = PageZoomGeometry(pixels: CGSize(width: 2000, height: 3000),
                                    viewport: CGSize(width: 1000, height: 800), displayScale: 2)

    func test_fit_isTheDefault_andReadsAsItsPercent() {
        let zoom = PageZoom()
        XCTAssertTrue(tall.isFit(zoom))
        XCTAssertEqual(tall.fitScale, 752.0 / 3000, accuracy: 0.0001)
        XCTAssertEqual(tall.percent(of: zoom), 752.0 / 3000 * 2, accuracy: 0.0001)
        XCTAssertFalse(tall.canZoomOut(zoom))
        XCTAssertTrue(tall.canZoomIn(zoom))
    }

    func test_actualSize_isOneImagePixelPerScreenPixel() {
        let zoom = tall.actualSize(PageZoom())
        XCTAssertEqual(tall.scale(of: zoom), 0.5)
        XCTAssertEqual(tall.percent(of: zoom), 1, accuracy: 0.0001)
        XCTAssertTrue(tall.isActualSize(zoom))
        XCTAssertFalse(tall.isFit(zoom))
    }

    func test_zoomIsHeldBetweenFitAndFiveTimesActual() {
        XCTAssertEqual(tall.zoomed(PageZoom(), to: 100).scale, 2.5)
        XCTAssertTrue(tall.isFit(tall.zoomed(tall.actualSize(PageZoom()), to: 0.001)))
        let top = tall.zoomed(PageZoom(), to: 100)
        XCTAssertFalse(tall.canZoomIn(top))
        XCTAssertTrue(tall.canZoomOut(top))
    }

    func test_zoomInAndOut_stepByOneAndAHalf() {
        let actual = tall.actualSize(PageZoom())
        XCTAssertEqual(tall.scale(of: tall.zoomedIn(actual)), 0.75, accuracy: 0.0001)
        XCTAssertEqual(tall.scale(of: tall.zoomedOut(actual)), 0.5 / 1.5, accuracy: 0.0001)
    }

    func test_zoomingAbout_aPoint_keepsThatPageSpotStill() {
        let anchor = CGPoint(x: 120, y: -80)
        let start = tall.actualSize(PageZoom(), about: .zero)
        let spot = CGPoint(x: (anchor.x - start.pan.width) / 0.5, y: (anchor.y - start.pan.height) / 0.5)
        let next = tall.zoomed(start, to: 1, about: anchor)
        XCTAssertEqual(anchor.x - spot.x * 1, next.pan.width, accuracy: 0.0001)
        XCTAssertEqual(anchor.y - spot.y * 1, next.pan.height, accuracy: 0.0001)
    }

    func test_pan_stopsAtThePagesEdges() {
        let zoom = tall.actualSize(PageZoom())
        // 1000 x 1500 pt page in a 1000 x 800 pt canvas: no sideways reach, 350 pt up or down.
        let moved = tall.panned(zoom, by: CGSize(width: 500, height: 900))
        XCTAssertEqual(moved.pan.width, 0)
        XCTAssertEqual(moved.pan.height, 350)
        XCTAssertEqual(tall.panned(moved, by: CGSize(width: 0, height: -2000)).pan.height, -350)
    }

    func test_panningAFittedPage_doesNothing() {
        XCTAssertEqual(tall.panned(PageZoom(), by: CGSize(width: 40, height: 40)), PageZoom())
    }

    func test_doubleClick_togglesFitAndActualSize() {
        let anchor = CGPoint(x: 10, y: 10)
        let zoomed = tall.toggled(PageZoom(), about: anchor)
        XCTAssertTrue(tall.isActualSize(zoomed))
        XCTAssertTrue(tall.isFit(tall.toggled(zoomed, about: anchor)))
    }

    func test_aPageSmallerThanTheCanvas_canZoomOutToItsActualSize() {
        let small = PageZoomGeometry(pixels: CGSize(width: 300, height: 300),
                                 viewport: CGSize(width: 1000, height: 800), displayScale: 2)
        XCTAssertEqual(small.lowestScale, 0.5)
        let actual = small.actualSize(PageZoom())
        XCTAssertEqual(small.percent(of: actual), 1, accuracy: 0.0001)
        XCTAssertTrue(small.canZoomIn(actual))
        XCTAssertEqual(small.clampedPan(CGSize(width: 90, height: 90), scale: 0.5), .zero)
    }
}
#endif
