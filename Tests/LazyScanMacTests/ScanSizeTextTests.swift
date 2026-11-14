#if os(macOS)
import XCTest
@testable import LazyScanMac

final class ScanSizeTextTests: XCTestCase {
    private let us = Locale(identifier: "en_US")
    private let canada = Locale(identifier: "en_CA")
    private let germany = Locale(identifier: "de_DE")

    func testUnitFollowsMeasurementSystem() {
        XCTAssertTrue(ScanSizeText.usesInches(us))
        XCTAssertFalse(ScanSizeText.usesInches(canada))
        XCTAssertFalse(ScanSizeText.usesInches(germany))
    }

    func testSizeInInches() {
        XCTAssertEqual(ScanSizeText.size(widthInches: 8.5, heightInches: 11, locale: us), "8.5 × 11.0 in")
    }

    func testSizeInMillimeters() {
        XCTAssertEqual(ScanSizeText.size(widthInches: 8.5, heightInches: 11, locale: canada), "216 × 279 mm")
    }

    func testLength() {
        XCTAssertEqual(ScanSizeText.length(inches: 1.5, locale: us), "1.5 in")
        XCTAssertEqual(ScanSizeText.length(inches: 1.5, locale: canada), "38 mm")
    }
}
#endif
