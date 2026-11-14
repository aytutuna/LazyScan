#if os(iOS)
import CoreGraphics
import Foundation
import XCTest
@testable import LazyScanIOS
@testable import LazyScanKit

// Mark Up without a screen (`MarkUpModel`): the page fitted into the view, strokes that start on the page and
// are kept as points of the unturned picture, the two sets of four colors, Undo, what counts as a change, and
// the viewer's picture with the marks drawn in (`MarkedPictures`).

private let viewSize = CGSize(width: 224, height: 324)

/// A 200 × 300 page shown unturned.
private func model(marks: PageMarks? = nil, showsOriginal: Bool = false, quarterTurns: Int = 0) -> MarkUpModel {
    let size: CGSize = quarterTurns % 2 == 0 ? CGSize(width: 200, height: 300) : CGSize(width: 300, height: 200)
    return MarkUpModel(marks: marks, showsOriginal: showsOriginal, quarterTurns: quarterTurns, pageSize: size)
}

private func pictureOfWhite(width: Int = 8, height: Int = 8) throws -> CGImage {
    let space: CGColorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
    let context: CGContext = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                                     space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try XCTUnwrap(context.makeImage())
}

final class MarkUpModelTests: XCTestCase {
    func test_thePageFitsTheViewCentered_inItsMargin() {
        let markUp: MarkUpModel = model()
        // 200 × 300 into 200 × 300 after the 12 pt margin: scale 1.
        XCTAssertEqual(markUp.fittedFrame(in: viewSize), CGRect(x: 12, y: 12, width: 200, height: 300))
    }

    func test_aStrokeKeepsPointsOfThePage_andACrossingBeyondTheEdgeLandsOnIt() {
        var markUp: MarkUpModel = model()
        let frame: CGRect = markUp.fittedFrame(in: viewSize)
        XCTAssertTrue(markUp.begin(at: CGPoint(x: 12, y: 12), frame: frame))
        markUp.extend(to: CGPoint(x: 112, y: 162), frame: frame)
        markUp.extend(to: CGPoint(x: 500, y: 162), frame: frame)
        markUp.end()
        XCTAssertEqual(markUp.marks.strokes.count, 1)
        XCTAssertEqual(markUp.marks.strokes[0].points, [MarkPoint(x: 0, y: 0), MarkPoint(x: 0.5, y: 0.5), MarkPoint(x: 1, y: 0.5)])
        XCTAssertFalse(markUp.drawing)
    }

    func test_aFingerThatComesDownOffThePage_drawsNothing() {
        var markUp: MarkUpModel = model()
        let frame: CGRect = markUp.fittedFrame(in: viewSize)
        XCTAssertFalse(markUp.begin(at: CGPoint(x: 4, y: 4), frame: frame))
        markUp.extend(to: CGPoint(x: 50, y: 50), frame: frame)
        XCTAssertTrue(markUp.marks.isEmpty)
        XCTAssertFalse(markUp.isChanged)
    }

    func test_onATurnedPage_strokesAreKeptOnTheUnturnedPicture() {
        var markUp: MarkUpModel = model(quarterTurns: 1)
        let frame: CGRect = markUp.fittedFrame(in: CGSize(width: 324, height: 224))
        // The top left of the turned picture is the bottom left of the file's picture.
        XCTAssertTrue(markUp.begin(at: CGPoint(x: frame.minX, y: frame.minY), frame: frame))
        XCTAssertEqual(markUp.marks.strokes[0].points, [MarkPoint(x: 0, y: 1)])
        let back: CGPoint = MarkUpModel.viewPoint(markUp.marks.strokes[0].points[0], quarterTurns: 1, frame: frame)
        XCTAssertEqual(back.x, frame.minX, accuracy: 0.001)
        XCTAssertEqual(back.y, frame.minY, accuracy: 0.001)
    }

    func test_penAndHighlighterHaveFourColorsEach_andKeepTheDotPosition() {
        var markUp: MarkUpModel = model()
        XCTAssertEqual(markUp.tool, .pen)
        XCTAssertEqual(markUp.inks, [.black, .blue, .red, .green])
        markUp.pick(color: 2)
        XCTAssertEqual(markUp.ink, .red)
        markUp.select(.highlighter)
        XCTAssertEqual(markUp.inks, [.yellow, .green, .pink, .orange])
        XCTAssertEqual(markUp.ink, .pink)
    }

    func test_theStrokeTakesTheToolAndColorPickedWhenItBegan() {
        var markUp: MarkUpModel = model()
        let frame: CGRect = markUp.fittedFrame(in: viewSize)
        markUp.select(.highlighter)
        markUp.pick(color: 3)
        XCTAssertTrue(markUp.begin(at: CGPoint(x: 50, y: 50), frame: frame))
        markUp.end()
        XCTAssertEqual(markUp.marks.strokes[0].tool, .highlighter)
        XCTAssertEqual(markUp.marks.strokes[0].ink, .orange)
    }

    func test_undoTakesOffTheLastStroke_andIsOffWhenThereIsNone() {
        var markUp: MarkUpModel = model()
        let frame: CGRect = markUp.fittedFrame(in: viewSize)
        XCTAssertFalse(markUp.canUndo)
        for x in [50, 80] as [CGFloat] {
            XCTAssertTrue(markUp.begin(at: CGPoint(x: x, y: 50), frame: frame))
            markUp.end()
        }
        XCTAssertTrue(markUp.canUndo)
        XCTAssertTrue(markUp.isChanged)
        markUp.undo()
        XCTAssertEqual(markUp.marks.strokes.count, 1)
        markUp.undo()
        XCTAssertFalse(markUp.canUndo)
        XCTAssertFalse(markUp.isChanged)
    }

    func test_strokesOfAnEarlierVisitAreThereToUndo() {
        var earlier: PageMarks = PageMarks()
        earlier.begin(tool: .pen, ink: .red, at: MarkPoint(x: 0.2, y: 0.2))
        var markUp: MarkUpModel = model(marks: earlier)
        XCTAssertTrue(markUp.canUndo)
        XCTAssertFalse(markUp.isChanged)
        markUp.undo()
        XCTAssertTrue(markUp.isChanged)
        XCTAssertTrue(markUp.marks.isEmpty)
    }

    func test_marksOnTheOtherVersionOfThePage_areLeftAlone_untilAStrokeIsDrawn() {
        var other: PageMarks = PageMarks(onOriginal: true)
        other.begin(tool: .pen, ink: .black, at: MarkPoint(x: 0.5, y: 0.5))
        var markUp: MarkUpModel = model(marks: other, showsOriginal: false)
        XCTAssertFalse(markUp.canUndo)
        XCTAssertFalse(markUp.isChanged)
        let frame: CGRect = markUp.fittedFrame(in: viewSize)
        XCTAssertTrue(markUp.begin(at: CGPoint(x: 50, y: 50), frame: frame))
        XCTAssertTrue(markUp.isChanged)
        XCTAssertFalse(markUp.marks.onOriginal)
    }
}

final class MarkedPicturesTests: XCTestCase {
    private func page(marks: PageMarks?, showsOriginal: Bool = false) throws -> ScannedPage {
        var page = ScannedPage(image: try pictureOfWhite(), dpi: 72, colorMode: .color)
        page.marks = marks
        page.showsOriginal = showsOriginal
        return page
    }

    private func marks(onOriginal: Bool) -> PageMarks {
        var marks = PageMarks(onOriginal: onOriginal)
        marks.begin(tool: .pen, ink: .black, at: MarkPoint(x: 0.5, y: 0.5))
        return marks
    }

    func test_theMarksShowOnlyOnTheVersionTheyWereDrawnOn() throws {
        XCTAssertFalse(MarkedPictures.shows(try page(marks: nil)))
        XCTAssertTrue(MarkedPictures.shows(try page(marks: marks(onOriginal: false))))
        XCTAssertFalse(MarkedPictures.shows(try page(marks: marks(onOriginal: true))))
        XCTAssertTrue(MarkedPictures.shows(try page(marks: marks(onOriginal: true), showsOriginal: true)))
    }

    func test_aMarkedPageGetsItsMarksDrawnIn_onceForTheSamePictureAndMarks() throws {
        let marked: ScannedPage = try page(marks: marks(onOriginal: false))
        let pictures = MarkedPictures()
        let drawn: CGImage = pictures.picture(marked.image, of: marked)
        XCTAssertFalse(drawn === marked.image)
        XCTAssertTrue(pictures.picture(marked.image, of: marked) === drawn)
    }

    func test_aPageWithoutMarksShowsItsOwnPicture() throws {
        let plain: ScannedPage = try page(marks: nil)
        XCTAssertTrue(MarkedPictures().picture(plain.image, of: plain) === plain.image)
    }
}
#endif
