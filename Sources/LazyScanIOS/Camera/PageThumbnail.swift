#if os(iOS)
import LazyScanKit
import Foundation

/// A small grayscale look at a page in a live frame, to tell whether the automatic shutter is about to
/// take the page it took last: the frame's luma over the page's bounding box (`FrameQuality.area`) as
/// `side` × `side` cell means, without the outermost ring of cells, which the page's edges (found only to
/// a pixel or two) and the table beside them decide. Two looks match when their cells correlate
/// (`minCorrelation`), so another exposure or a slightly moved phone still matches while another page does
/// not; two looks that are both nearly flat (blank paper) match when their brightness against the rest of
/// the frame is close.
public struct PageThumbnail: Equatable, Sendable {
    public static let side: Int = 24
    public static let minCorrelation: Double = 0.9
    /// A look whose cells vary less than this (standard deviation, in luma levels) counts as flat.
    public static let flatSpread: Double = 4
    /// Flat looks match when their mean luma differs by at most this (when there is no frame around the
    /// page to compare against).
    public static let flatBrightness: Double = 12
    /// Flat looks match when their brightness over the frame's mean differs by at most this share.
    public static let flatRatio: Double = 0.1

    private let cells: [Double]
    /// The frame's mean luma, when the page does not fill the frame.
    private let surround: Double?

    /// The look at `page` (pixels of `frame`); the whole frame when nil.
    public init(_ frame: RgbaImage, page: Quad?) {
        let gray: GrayImage = GrayImage.luma(frame)
        let box: FrameQualityArea = FrameQuality.area(page, width: gray.width, height: gray.height)
        if box.x0 > 0 || box.y0 > 0 || box.x1 < gray.width || box.y1 < gray.height {
            surround = Double(gray.pixels.reduce(0) { $0 + Int($1) }) / Double(max(gray.pixels.count, 1))
        } else {
            surround = nil
        }
        let side: Int = PageThumbnail.side
        let boxWidth: Int = box.x1 - box.x0
        let boxHeight: Int = box.y1 - box.y0
        var means: [Double] = []
        var cy: Int = 1
        while cy < side - 1 {
            let y0: Int = box.y0 + cy * boxHeight / side
            let y1: Int = min(max(y0 + 1, box.y0 + (cy + 1) * boxHeight / side), box.y1)
            var cx: Int = 1
            while cx < side - 1 {
                let x0: Int = box.x0 + cx * boxWidth / side
                let x1: Int = min(max(x0 + 1, box.x0 + (cx + 1) * boxWidth / side), box.x1)
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
            if let a = surround, let b = other.surround, a > 0, b > 0 {
                let ratioA: Double = meanA / a
                let ratioB: Double = meanB / b
                return abs(ratioA - ratioB) <= PageThumbnail.flatRatio * max(ratioA, ratioB)
            }
            return abs(meanA - meanB) <= PageThumbnail.flatBrightness
        }
        if spreadA < flat || spreadB < flat {
            return false
        }
        return dot / (spreadA * spreadB).squareRoot() >= PageThumbnail.minCorrelation
    }
}
#endif
