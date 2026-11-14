#if os(macOS)
import CoreGraphics
import LazyScanKit
import XCTest
@testable import LazyScanMac

// The angle math of the Adjust Crop sheet (PhotoCropEditorView.swift): the handle's angle and the page clamp after a turn.

final class CropGeometryTests: XCTestCase {
    private let page = CGSize(width: 1000, height: 800)

    func test_angle_isZeroWhenThePointerIsStraightAboveTheCenter() {
        let center = CGPoint(x: 400, y: 400)
        XCTAssertEqual(CropGeometry.angle(from: center, to: CGPoint(x: 400, y: 300)), 0, accuracy: 0.0001)
        XCTAssertEqual(CropGeometry.angle(from: center, to: CGPoint(x: 500, y: 400)), 90, accuracy: 0.0001)
    }

    func test_angle_followsTheHandleOfATurnedRegion() {
        let a = 30.0 * .pi / 180
        let center = CGPoint(x: 400, y: 400)
        let handle = CGPoint(x: center.x + 50 * sin(a), y: center.y - 50 * cos(a))
        XCTAssertEqual(CropGeometry.angle(from: center, to: handle), 30, accuracy: 0.0001)
    }

    func test_rotating_keepsTheCenterAndTheSize() {
        let region = DetectedPhotoRegion(center: CGPoint(x: 500, y: 400), size: CGSize(width: 200, height: 120), angleDegrees: 3.2)
        let turned = CropGeometry.rotated(region, toAngle: 12.5, page: page)
        XCTAssertEqual(turned.angleDegrees, 12.5, accuracy: 0.0001)
        XCTAssertEqual(turned.center, region.center)
        XCTAssertEqual(turned.size, region.size)
        XCTAssertEqual(turned.id, region.id)
    }

    func test_rotating_movesACropNearTheEdgeBackOnThePage() {
        let region = DetectedPhotoRegion(center: CGPoint(x: 500, y: 20), size: CGSize(width: 100, height: 40), angleDegrees: 0)
        let turned = CropGeometry.rotated(region, toAngle: 90, page: page)
        XCTAssertEqual(turned.center.x, 500, accuracy: 0.0001)
        XCTAssertEqual(turned.center.y, 50, accuracy: 0.0001)
        XCTAssertEqual(turned.size, region.size)
        XCTAssertGreaterThanOrEqual(turned.boundingBox.minY, -0.0001)
    }

    func test_rotating_centersACropLargerThanThePage() {
        let region = DetectedPhotoRegion(center: CGPoint(x: 100, y: 100), size: CGSize(width: 1200, height: 100), angleDegrees: 0)
        let turned = CropGeometry.rotated(region, toAngle: 5, page: page)
        XCTAssertEqual(turned.center.x, 500, accuracy: 0.0001)
    }

    func test_rotating_keepsTheAngleWithinHalfATurn() {
        let region = DetectedPhotoRegion(center: CGPoint(x: 500, y: 400), size: CGSize(width: 100, height: 100), angleDegrees: 170)
        XCTAssertEqual(CropGeometry.rotated(region, toAngle: 175, page: page).angleDegrees, 175, accuracy: 0.0001)
        XCTAssertEqual(CropGeometry.rotated(region, toAngle: 190, page: page).angleDegrees, -170, accuracy: 0.0001)
        XCTAssertEqual(CropGeometry.rotated(region, toAngle: 270, page: page).angleDegrees, -90, accuracy: 0.0001)
        XCTAssertEqual(CropGeometry.rotated(region, toAngle: -200, page: page).angleDegrees, 160, accuracy: 0.0001)
    }
}
#endif
