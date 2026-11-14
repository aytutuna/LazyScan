import CoreGraphics
import Foundation
import XCTest
@testable import LazyScanKit

// Pen and highlighter strokes on a queued page (Core/PageMarks.swift, Output/PageMarkRenderer.swift): kept in
// the queue record and drawn into the PDF and the pictures saved, printed and copied.

/// A white page, with a dark bar across the middle when `bar`.
private func whitePage(width: Int = 1000, height: Int = 500, bar: Bool = false) -> CGImage {
    let space: CGColorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    if bar {
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: height / 2 - 2, width: width, height: 4))
    }
    return context.makeImage()!
}

private func allPixels(_ image: CGImage) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let space: CGColorSpace = CGColorSpaceCreateDeviceRGB()
    bytes.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Void in
        let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return bytes
}

/// The pixel at column `x`, row `y` from the top, as red, green and blue.
private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [Int] {
    let bytes = allPixels(image)
    let at = (y * image.width + x) * 4
    return [Int(bytes[at]), Int(bytes[at + 1]), Int(bytes[at + 2])]
}

/// A line across the left part of the picture, at one fifth of its height.
private func line(tool: MarkTool = .pen, ink: MarkInk = .black, onOriginal: Bool = false) -> PageMarks {
    var marks = PageMarks(onOriginal: onOriginal)
    marks.begin(tool: tool, ink: ink, at: MarkPoint(x: 0.1, y: 0.2))
    marks.extend(MarkPoint(x: 0.5, y: 0.2))
    return marks
}

final class PageMarksTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PageMarksTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try await Task.sleep(nanoseconds: 600_000_000)
        try? FileManager.default.removeItem(at: folder)
    }

    func test_marks_roundTripThroughJSON() throws {
        var marks = line(tool: .highlighter, ink: .yellow, onOriginal: true)
        marks.begin(tool: .pen, ink: .blue, at: MarkPoint(x: 0.3, y: 0.4))
        let data = try JSONEncoder().encode(marks)
        XCTAssertEqual(try JSONDecoder().decode(PageMarks.self, from: data), marks)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"highlighter\""))
        XCTAssertTrue(text.contains("\"yellow\""))
    }

    func test_strokes_extendRemoveAndIgnoreAPointThatHasNotMoved() {
        var marks = PageMarks()
        XCTAssertTrue(marks.isEmpty)
        marks.extend(MarkPoint(x: 0.5, y: 0.5))
        XCTAssertTrue(marks.isEmpty)
        marks.begin(tool: .pen, ink: .black, at: MarkPoint(x: 0.1, y: 0.1))
        marks.extend(MarkPoint(x: 0.1, y: 0.1))
        marks.extend(MarkPoint(x: 0.2, y: 0.1))
        XCTAssertEqual(marks.strokes[0].points.count, 2)
        marks.begin(tool: .pen, ink: .red, at: MarkPoint(x: 0.9, y: 0.9))
        marks.removeLast()
        XCTAssertEqual(marks.strokes.count, 1)
        marks.removeLast()
        XCTAssertTrue(marks.isEmpty)
        marks.removeLast()
        XCTAssertTrue(marks.isEmpty)
    }

    func test_turning_mapsTheFilePictureToTheShownOne_andBack() {
        let corner = MarkPoint(x: 0.1, y: 0.2)
        XCTAssertEqual(corner.turned(quarterTurns: 0), corner)
        let once = corner.turned(quarterTurns: 1)
        XCTAssertEqual(once.x, 0.8, accuracy: 1e-9)
        XCTAssertEqual(once.y, 0.1, accuracy: 1e-9)
        let twice = corner.turned(quarterTurns: 2)
        XCTAssertEqual(twice.x, 0.9, accuracy: 1e-9)
        XCTAssertEqual(twice.y, 0.8, accuracy: 1e-9)
        let thrice = corner.turned(quarterTurns: 3)
        XCTAssertEqual(thrice.x, 0.2, accuracy: 1e-9)
        XCTAssertEqual(thrice.y, 0.9, accuracy: 1e-9)
        for turns in 0..<4 {
            let back = corner.turned(quarterTurns: turns).unturned(quarterTurns: turns)
            XCTAssertEqual(back.x, corner.x, accuracy: 1e-9)
            XCTAssertEqual(back.y, corner.y, accuracy: 1e-9)
        }
    }

    func test_burned_penDrawsBlackOnlyAlongTheStroke() {
        let image = whitePage()
        let burned = PageMarkRenderer.burned(image, marks: line(), quarterTurns: 0, showsOriginal: false)
        XCTAssertEqual(burned.width, 1000)
        XCTAssertEqual(burned.height, 500)
        XCTAssertLessThan(pixel(burned, 300, 100)[0], 40)
        XCTAssertEqual(pixel(burned, 300, 400), [255, 255, 255])
        XCTAssertEqual(pixel(burned, 800, 100), [255, 255, 255])
        let before = allPixels(image), after = allPixels(burned)
        var changed = 0
        for index in stride(from: 0, to: before.count, by: 4) where before[index] != after[index] { changed += 1 }
        XCTAssertGreaterThan(changed, 0)
        XCTAssertLessThan(changed, 3000)
    }

    func test_burned_highlighterKeepsDarkTextDark() {
        var marks = PageMarks()
        marks.begin(tool: .highlighter, ink: .yellow, at: MarkPoint(x: 0.1, y: 0.5))
        marks.extend(MarkPoint(x: 0.9, y: 0.5))
        let burned = PageMarkRenderer.burned(whitePage(bar: true), marks: marks, quarterTurns: 0, showsOriginal: false)
        let text = pixel(burned, 500, 250)
        XCTAssertLessThan(text[0] + text[1] + text[2], 30)
        // The band is 10 pixels either side of the middle row, the bar 2.
        let band = pixel(burned, 500, 258)
        XCTAssertGreaterThan(band[0], 200)
        XCTAssertGreaterThan(band[1], 200)
        XCTAssertLessThan(band[2], 120)
    }

    func test_burned_followsTheQuarterTurns() {
        // The same stroke on a picture turned once clockwise is a vertical line at 0.8 of its width.
        let turned = whitePage(width: 500, height: 1000)
        let burned = PageMarkRenderer.burned(turned, marks: line(), quarterTurns: 1, showsOriginal: false)
        XCTAssertLessThan(pixel(burned, 400, 300)[0], 40)
        XCTAssertEqual(pixel(burned, 100, 300), [255, 255, 255])
    }

    func test_burned_leavesThePageAloneWhenThereIsNothingToDraw() {
        let image = whitePage()
        XCTAssertTrue(PageMarkRenderer.burned(image, marks: nil, quarterTurns: 0, showsOriginal: false) === image)
        XCTAssertTrue(PageMarkRenderer.burned(image, marks: PageMarks(), quarterTurns: 0, showsOriginal: false) === image)
        XCTAssertTrue(PageMarkRenderer.burned(image, marks: line(onOriginal: true), quarterTurns: 0,
                                              showsOriginal: false) === image)
        XCTAssertTrue(PageMarkRenderer.burned(image, marks: line(), quarterTurns: 0, showsOriginal: true) === image)
        XCTAssertFalse(PageMarkRenderer.burned(image, marks: line(onOriginal: true), quarterTurns: 0,
                                               showsOriginal: true) === image)
    }

    func test_fullImage_andThePDF_includeTheMarks() throws {
        var page = ScannedPage(image: whitePage(), dpi: 100, colorMode: .color)
        let plain = try AppState.fullImage(of: page, number: 1)
        XCTAssertEqual(pixel(plain, 300, 100), [255, 255, 255])
        let plainPDF = try PDFBuilder.makePDF(pages: [page], ocrLines: [nil], progress: nil)
        page.marks = line()
        let marked = try AppState.fullImage(of: page, number: 1)
        XCTAssertLessThan(pixel(marked, 300, 100)[0], 40)
        let markedPDF = try PDFBuilder.makePDF(pages: [page], ocrLines: [nil], progress: nil)
        XCTAssertNotEqual(markedPDF, plainPDF)
    }

    func test_aPageKeepsItsMarks_whenRebuilt_butNotInANewCut() {
        var page = ScannedPage(image: whitePage(), dpi: 100, colorMode: .color)
        page.marks = line()
        XCTAssertEqual(page.withImage(whitePage()).marks, page.marks)
        let cut = page.withGeometry(whitePage(), geometry: PageGeometry(cropped: true, angleDegrees: 0, basis: .pageEdges))
        XCTAssertNil(cut.marks)
    }

    func test_swappingVersionsTwice_keepsTheMarks_andHidesThemWhileTheOtherIsShown() {
        var page = ScannedPage(image: whitePage(), dpi: 100, colorMode: .color)
        page.alternate = PageVersion(image: whitePage(), fileURL: nil, fullPixelSize: nil)
        page.marks = line()
        let other = page.withVersionsSwapped(whitePage())
        XCTAssertEqual(other.marks, page.marks)
        XCTAssertTrue(other.showsOriginal)
        let image = whitePage()
        XCTAssertTrue(PageMarkRenderer.burned(image, marks: other.marks, quarterTurns: 0,
                                              showsOriginal: other.showsOriginal) === image)
        let back = other.withVersionsSwapped(whitePage())
        XCTAssertEqual(back.marks, page.marks)
        XCTAssertFalse(back.showsOriginal)
    }

    func test_theQueueRecord_keepsTheMarks_andReadsARecordWithoutThem() throws {
        let spool = folder.appendingPathComponent("pages", isDirectory: true)
        var page = ScannedPage(image: whitePage(), dpi: 100, colorMode: .color,
                               fileURL: spool.appendingPathComponent("a.tiff"))
        let bare = try JSONEncoder().encode(QueueRecord([page], spool: spool))
        XCTAssertFalse(String(decoding: bare, as: UTF8.self).contains("marks"))
        let old = try JSONDecoder().decode(QueueRecord.self, from: bare)
        XCTAssertNil(old.pages[0].page(preview: whitePage(), spool: spool).marks)

        page.marks = line(tool: .highlighter, ink: .pink)
        let data = try JSONEncoder().encode(QueueRecord([page], spool: spool))
        let record = try JSONDecoder().decode(QueueRecord.self, from: data)
        XCTAssertEqual(record.pages[0].page(preview: whitePage(), spool: spool).marks, page.marks)
    }

    @MainActor
    func test_setMarks_setsAndClearsThem() {
        let state = AppState(presetStore: PresetStore(directory: folder), files: AppStateFiles.all(in: folder))
        let page = ScannedPage(image: whitePage(), dpi: 100, colorMode: .color)
        state.scannedPages = [page]
        state.setMarks(line(), for: page.id)
        XCTAssertEqual(state.scannedPages[0].marks, line())
        state.setMarks(PageMarks(), for: page.id)
        XCTAssertNil(state.scannedPages[0].marks)
    }
}
