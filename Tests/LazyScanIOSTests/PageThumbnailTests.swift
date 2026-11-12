#if os(iOS)
import XCTest
@testable import LazyScanIOS
@testable import LazyScanKit

final class PageThumbnailTests: XCTestCase {
    func test_thePageSeenAgain_matches_evenInAnotherExposure() {
        let sharp = PageThumbnail(LiveFrames.frame(), page: LiveFrames.sheet)
        let shifted = PageThumbnail(LiveFrames.frame(), page: LiveFrames.sheetMoved(2))
        let dimmed = PageThumbnail(LiveFrames.frame(dim: 150), page: LiveFrames.sheet)
        XCTAssertTrue(sharp.matches(sharp))
        XCTAssertTrue(sharp.matches(shifted))
        XCTAssertTrue(sharp.matches(dimmed))
    }

    func test_anotherPage_doesNotMatch() {
        let frame: RgbaImage = LiveFrames.frame()
        let written: RgbaImage = barred(frame)
        let blank = PageThumbnail(frame, page: LiveFrames.sheet)
        let text = PageThumbnail(written, page: LiveFrames.sheet)
        XCTAssertFalse(blank.matches(text))
        XCTAssertFalse(text.matches(blank))
    }

    func test_blankLooks_matchByBrightness() {
        let grey = PageThumbnail(RgbaImage.filled(width: 64, height: 48, r: 90, g: 90, b: 90), page: nil)
        let nearGrey = PageThumbnail(RgbaImage.filled(width: 64, height: 48, r: 96, g: 96, b: 96), page: nil)
        let white = PageThumbnail(RgbaImage.filled(width: 64, height: 48, r: 230, g: 230, b: 230), page: nil)
        XCTAssertTrue(grey.matches(nearGrey))
        XCTAssertFalse(grey.matches(white))
    }
}
#endif
