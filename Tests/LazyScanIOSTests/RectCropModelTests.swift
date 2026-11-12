#if os(iOS)
import CoreGraphics
import Foundation
import XCTest
@testable import LazyScanIOS

// The iPhone's rectangle crop without a screen (`RectCropModel`): the page fitted into the view, a finger taking
// the nearest of eight handles and moving only the sides it holds, the rectangle kept on the page and at least a
// tenth of it wide and high, Reset, and VoiceOver's and the keyboard's steps.

/// A 400 × 300 page.
private func model() -> RectCropModel {
    RectCropModel(pageWidth: 400, pageHeight: 300)
}

/// A 448 × 348 view: the page fits its width, 24 pt in from each side, at 1 pt a pixel.
private let viewSize = CGSize(width: 448, height: 348)

final class RectCropModelTests: XCTestCase {
    func test_thePageFitsTheViewCentered_andStartsWhole() {
        let crop: RectCropModel = model()
        XCTAssertEqual(crop.fittedFrame(in: viewSize), CGRect(x: 24, y: 24, width: 400, height: 300))
        XCTAssertEqual(crop.rect, CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertTrue(crop.isWhole)
        let frame: CGRect = crop.fittedFrame(in: viewSize)
        XCTAssertEqual(crop.point(of: .topLeft, frame: frame), CGPoint(x: 24, y: 24))
        XCTAssertEqual(crop.point(of: .bottomRight, frame: frame), CGPoint(x: 424, y: 324))
        XCTAssertEqual(crop.point(of: .right, frame: frame), CGPoint(x: 424, y: 174))
        XCTAssertEqual(crop.point(of: .top, frame: frame), CGPoint(x: 224, y: 24))
    }

    func test_aFingerMovesOnlyTheSidesOfTheHandleItTook() {
        var crop: RectCropModel = model()
        let frame: CGRect = crop.fittedFrame(in: viewSize)
        // Near the middle of the left edge: only the left side moves, whatever the finger does up or down.
        XCTAssertTrue(crop.beginDrag(at: CGPoint(x: 30, y: 170), frame: frame))
        XCTAssertEqual(crop.dragging, .left)
        crop.drag(to: CGPoint(x: 130, y: 250), frame: frame)
        XCTAssertEqual(crop.rect, CGRect(x: 0.25, y: 0, width: 0.75, height: 1))
        crop.endDrag()
        XCTAssertNil(crop.dragging)
        // A corner moves two sides.
        XCTAssertTrue(crop.beginDrag(at: CGPoint(x: 424, y: 324), frame: frame))
        XCTAssertEqual(crop.dragging, .bottomRight)
        crop.drag(to: CGPoint(x: 324, y: 224), frame: frame)
        XCTAssertEqual(crop.rect.maxX, 0.75, accuracy: 0.0001)
        XCTAssertEqual(crop.rect.maxY, 2.0 / 3.0, accuracy: 0.0001)
    }

    func test_aFingerAwayFromEveryHandleMovesNothing() {
        var crop: RectCropModel = model()
        let frame: CGRect = crop.fittedFrame(in: viewSize)
        XCTAssertFalse(crop.beginDrag(at: CGPoint(x: 224, y: 174), frame: frame))
        XCTAssertNil(crop.dragging)
        crop.drag(to: CGPoint(x: 100, y: 100), frame: frame)
        XCTAssertTrue(crop.isWhole)
    }

    func test_theRectangleStaysOnThePage_andAtLeastATenthWideAndHigh() {
        let rect = CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6)
        let out: CGRect = RectCropModel.moved(rect, handle: .topLeft, dx: -0.5, dy: -0.5)
        XCTAssertEqual(out.minX, 0, accuracy: 0.0001)
        XCTAssertEqual(out.minY, 0, accuracy: 0.0001)
        XCTAssertEqual(out.maxX, 0.8, accuracy: 0.0001)
        XCTAssertEqual(out.maxY, 0.8, accuracy: 0.0001)
        let small: CGRect = RectCropModel.moved(rect, handle: .right, dx: -0.9, dy: 0)
        XCTAssertEqual(small.minX, 0.2, accuracy: 0.0001)
        XCTAssertEqual(small.width, 0.1, accuracy: 0.0001)
        let low: CGRect = RectCropModel.moved(rect, handle: .top, dx: 0, dy: 0.9)
        XCTAssertEqual(low.height, 0.1, accuracy: 0.0001)
        XCTAssertEqual(low.maxY, 0.8, accuracy: 0.0001)
        let past: CGRect = RectCropModel.moved(rect, handle: .bottomRight, dx: 0.9, dy: 0.9)
        XCTAssertEqual(past.maxX, 1, accuracy: 0.0001)
        XCTAssertEqual(past.maxY, 1, accuracy: 0.0001)
    }

    func test_reset_goesBackToTheWholePage() {
        var crop: RectCropModel = model()
        crop.nudge(.top, dx: 0, dy: 0.3)
        XCTAssertFalse(crop.isWhole)
        crop.reset()
        XCTAssertTrue(crop.isWhole)
    }

    func test_aCropOpenedOnAKeptPart_startsThere_andOnlyAChangeCanBeCropped() {
        let kept = CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6)
        var crop = RectCropModel(pageWidth: 400, pageHeight: 300, start: kept)
        XCTAssertEqual(crop.rect, kept)
        XCTAssertFalse(crop.isWhole)
        XCTAssertFalse(crop.isChanged)
        crop.reset()
        XCTAssertTrue(crop.isWhole)
        XCTAssertTrue(crop.isChanged)
        XCTAssertFalse(model().isChanged)
    }

    func test_theKeyboardPicksHandlesInOrder_andNudgesTheSelectedOne() {
        var crop: RectCropModel = model()
        XCTAssertEqual(crop.selected, .topLeft)
        for _ in 0..<7 { crop.selectNext() }
        XCTAssertEqual(crop.selected, .right)
        crop.selectNext()
        XCTAssertEqual(crop.selected, .topLeft)
        crop.nudge(.topLeft, dx: 0.05, dy: 0.01)
        XCTAssertEqual(crop.rect.minX, 0.05, accuracy: 0.0001)
        XCTAssertEqual(crop.rect.minY, 0.01, accuracy: 0.0001)
    }

    func test_voiceOverHearsWhereAHandleIs_andHowBigTheAreaIs() {
        var crop: RectCropModel = model()
        crop.nudge(.left, dx: 0.12, dy: 0)
        crop.nudge(.top, dx: 0, dy: 0.08)
        crop.nudge(.right, dx: -0.08, dy: 0)
        XCTAssertEqual(crop.value(of: .topLeft), "12 percent from the left, 8 percent from the top")
        XCTAssertEqual(crop.areaName, "Crop area, 80 percent of the page wide, 92 percent high")
        XCTAssertEqual(crop.selected, .right)
    }
}
#endif
