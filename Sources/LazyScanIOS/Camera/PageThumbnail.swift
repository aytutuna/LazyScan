#if os(iOS)
import LazyScanKit
import Foundation

/// A small grayscale look at a page in a live frame, to tell whether the automatic shutter is about to
/// take the page it took last: the frame's luma over the page's bounding box (`FrameQuality.area`) as
/// `side` × `side` cell means. Two looks match when their cells correlate (`minCorrelation`), so another
/// exposure or a slightly moved phone still matches while another page does not; two looks that are both
/// nearly flat (blank paper) match when their brightness is close.
public struct PageThumbnail: Equatable, Sendable {
    public static let side: Int = 24
    public static let minCorrelation: Double = 0.9
    /// A look whose cells vary less than this (standard deviation, in luma levels) counts as flat.
    public static let flatSpread: Double = 4
    /// Flat looks match when their mean luma differs by at most this.
    public static let flatBrightness: Double = 12

    private let cells: [Double]

    /// The look at `page` (pixels of `frame`); the whole frame when nil.
    public init(_ frame: RgbaImage, page: Quad?) {
        let gray: GrayImage = GrayImage.luma(frame)
        let box: FrameQualityArea = FrameQuality.area(page, width: gray.width, height: gray.height)
        let side: Int = PageThumbnail.side
        let boxWidth: Int = box.x1 - box.x0
        let boxHeight: Int = box.y1 - box.y0
        var means: [Double] = []
        var cy: Int = 0
        while cy < side {
            let y0: Int = top + cy * boxHeight / side
            let y1: Int = min(max(y0 + 1, top + (cy + 1) * boxHeight / side), bottom)
            var cx: Int = 0
            while cx < side {
                let x0: Int = left + cx * boxWidth / side
                let x1: Int = min(max(x0 + 1, left + (cx + 1) * boxWidth / side), right)
                var sum: Int = 0
                var y: Int = y0
                while y < y1 {
                    var x: Int = x0
                    while x < x1 {
                        sum += Int(gray.pixels[y * gray.width + x])
                        x += 1
                    }
                    y += 1
                }
                means.append(Double(sum) / Double(max((y1 - y0) * (x1 - x0), 1)))
                cx += 1
            }
            cy += 1
        }
        cells = means
    }

    /// Whether `other` is a look at the same page.
    public func matches(_ other: PageThumbnail) -> Bool {
        let n: Double = Double(cells.count)
        let meanA: Double = cells.reduce(0, +) / n
        let meanB: Double = other.cells.reduce(0, +) / n
        var dot: Double = 0
        var spreadA: Double = 0
        var spreadB: Double = 0
        var i: Int = 0
        while i < cells.count {
            let a: Double = cells[i] - meanA
            let b: Double = other.cells[i] - meanB
            dot += a * b
            spreadA += a * a
            spreadB += b * b
            i += 1
        }
        let flat: Double = PageThumbnail.flatSpread * PageThumbnail.flatSpread * n
        if spreadA < flat && spreadB < flat {
            return abs(meanA - meanB) <= PageThumbnail.flatBrightness
        }
        if spreadA < flat || spreadB < flat {
            return false
        }
        return dot / (spreadA * spreadB).squareRoot() >= PageThumbnail.minCorrelation
    }
}
#endif
