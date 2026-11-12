import Foundation

// Plain pixel loops on integer pixels and Doubles (+ − × ÷ and truncation only), so the C# twin can give the
// same bytes: no CoreImage kernels, no library functions beyond that.

/// Flattens the curl of a book page photographed open, and fills fingers holding it at the margin.
///
/// `flatten` finds the page's top and bottom edges column by column on a gray copy (the first and last
/// rows where the paper is bright, past the table or lid beside it), cleans the two curves up (a median,
/// then a mean, across columns) and draws every column again between them: output row y is the share
/// (y − top reference) ÷ (bottom reference − top reference) of the way down the page, taken from the same
/// share of the way between that column's own edges. Text lines run between the edges, so lines bent and
/// squeezed near the spine come out straight and evenly spaced. Only the height is corrected, not the
/// foreshortening across the columns. A page whose edges are not found, or are straight already, is
/// left alone.
///
/// `fillFingers` looks in a band along each border for skin-colored patches that touch the border and
/// end inside the band (a thumb holding the page, not a picture that runs on) and paints them with the
/// paper's own color.
public enum PageFlatten {
    /// The edges are looked for in this share of the height from the top and from the bottom.
    public static let edgeFraction = 0.25
    /// A row is paper when its brightness is at least this share of the paper's.
    public static let paperShare = 0.5
    /// An edge is the first of this many paper rows in a row.
    public static let edgeRun = 3
    /// Columns around each one averaged when looking for the edge, on each side.
    public static let edgeHalfWidth = 2
    /// The edges must be found in at least this share of the columns.
    public static let minFoundShare = 0.6
    /// A page whose edges are further apart than this share of its height is a page.
    public static let minPageShare = 0.5
    /// The edges are smoothed across this share of the width, on each side (at least `minSmoothColumns`).
    public static let smoothShare = 0.01
    public static let minSmoothColumns = 2
    /// An edge that jumps by more than this share of the height between two neighbouring columns where it is
    /// found is no page edge (a dark banner or a picture along the border), and the page is left alone.
    public static let maxEdgeStepShare = 0.02
    /// A page whose edges bend less than this share of its height is left alone.
    public static let minCurveShare = 0.01
    /// A page whose paper is darker than this gray level is left alone.
    public static let minPaper = 96
    /// The paper's brightness and color are read on the middle rows between these shares of the height…
    public static let paperRowsFrom = 0.3
    public static let paperRowsTo = 0.7
    /// …as this share of the pixels there being darker.
    public static let paperPercentile = 0.8

    /// Fingers are looked for this many inches inside each border…
    public static let fingerBandInches = 1.0
    /// …in patches of at least…
    public static let minFingerSquareInches = 0.03
    /// …and at most this many square inches.
    public static let maxFingerSquareInches = 4.0
    /// A patch is painted over this far beyond its pixels, in inches (the blurred skin at its rim).
    public static let fingerGrowInches = 0.04
    /// A pixel is skin when its red exceeds its green by this much more than the paper's does…
    public static let skinRedOverGreen = 14
    /// …and exceeds its blue by this much more…
    public static let skinRedOverBlue = 25
    /// …and its red is at least this.
    public static let skinMinRed = 80
    /// The paper's color is taken from pixels at least this share as bright as the paper.
    public static let inkShare = 0.7

    /// `image` with its page drawn flat between its curved top and bottom edges; nil when the edges are not
    /// found or bend less than `minCurveShare` of the height.
    public static func flatten(_ image: RgbaImage) -> RgbaImage? {
        let w = image.width, h = image.height
        guard w >= 16, h >= 16 else { return nil }
        let gray: [UInt8] = GrayImage.luma(image).pixels
        let paper = paperLevel(gray, width: w, height: h)
        guard paper >= minPaper else { return nil }
        let threshold = Double(paper) * paperShare
        let depth = Int(Double(h) * edgeFraction)
        guard let rawTop = edges(gray, width: w, height: h, threshold: threshold, depth: depth, fromTop: true),
              let rawBottom = edges(gray, width: w, height: h, threshold: threshold, depth: depth, fromTop: false)
        else { return nil }
        let half = max(minSmoothColumns, Int(Double(w) * smoothShare))
        let top = smoothed(rawTop, half: half)
        let bottom = smoothed(rawBottom, half: half)
        var topRef = top[0], bottomRef = bottom[0]
        for x in 0..<w {
            if top[x] < topRef { topRef = top[x] }
            if bottom[x] > bottomRef { bottomRef = bottom[x] }
        }
        guard bottomRef - topRef >= Double(h) * minPageShare else { return nil }
        var bend = 0.0
        for x in 0..<w {
            guard bottom[x] - top[x] >= Double(h) * minPageShare else { return nil }
            bend = max(bend, (top[x] - topRef) + (bottomRef - bottom[x]))
        }
        guard bend >= Double(h) * minCurveShare else { return nil }

        var output = [UInt8](repeating: 255, count: w * h * 4)
        let span = bottomRef - topRef
        let last = Double(h - 1)
        for y in 0..<h {
            let t = (Double(y) - topRef) / span
            for x in 0..<w {
                var s = top[x] + t * (bottom[x] - top[x])
                if s < 0 { s = 0 }
                if s > last { s = last }
                var y0 = Int(s)
                if y0 > h - 2 { y0 = h - 2 }
                let f = s - Double(y0)
                let a = (y0 * w + x) * 4
                let b = a + w * 4
                let o = (y * w + x) * 4
                for c in 0..<3 {
                    let v = Double(image.pixels[a + c]) * (1 - f) + Double(image.pixels[b + c]) * f
                    output[o + c] = UInt8(v + 0.5)
                }
            }
        }
        return RgbaImage(width: w, height: h, pixels: output)
    }

    /// `image`, taken at `dpi`, with the fingers at its margins painted over with paper; nil when there are none.
    public static func fillFingers(_ image: RgbaImage, dpi: Double) -> RgbaImage? {
        let w = image.width, h = image.height
        let band = Int(fingerBandInches * dpi)
        guard w >= 16, h >= 16, band >= 8, band * 4 <= min(w, h) else { return nil }
        let gray: [UInt8] = GrayImage.luma(image).pixels
        let paper = paperLevel(gray, width: w, height: h)
        guard paper >= minPaper, let tone = paperTone(image, gray: gray, level: paper) else { return nil }
        let redOverGreen = tone.r - tone.g + skinRedOverGreen
        let redOverBlue = tone.r - tone.b + skinRedOverBlue

        func isSkin(_ i: Int) -> Bool {
            let r = Int(image.pixels[i]), g = Int(image.pixels[i + 1]), b = Int(image.pixels[i + 2])
            return r >= skinMinRed && r - g >= redOverGreen && r - b >= redOverBlue
        }
        func depthAt(_ x: Int, _ y: Int) -> Int {
            min(min(x, w - 1 - x), min(y, h - 1 - y))
        }

        var skin = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w where depthAt(x, y) < band && isSkin((y * w + x) * 4) {
                skin[y * w + x] = 1
            }
        }

        let minArea = Int(minFingerSquareInches * dpi * dpi)
        let maxArea = Int(maxFingerSquareInches * dpi * dpi)
        let grow = max(2, Int(fingerGrowInches * dpi))
        let brightest = Double(paper) * inkShare
        var output = image
        var painted = false
        var seen = [UInt8](repeating: 0, count: w * h)
        for start in 0..<(w * h) where skin[start] == 1 && seen[start] == 0 {
            var cells: [Int] = [start]
            var stack: [Int] = [start]
            seen[start] = 1
            var runsOn = false
            var minX = w, maxX = 0, minY = h, maxY = 0
            while let at = stack.popLast() {
                let x = at % w, y = at / w
                if depthAt(x, y) >= band - 1 { runsOn = true }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                var next: [Int] = []
                if x > 0 { next.append(at - 1) }
                if x < w - 1 { next.append(at + 1) }
                if y > 0 { next.append(at - w) }
                if y < h - 1 { next.append(at + w) }
                for n in next where skin[n] == 1 && seen[n] == 0 {
                    seen[n] = 1
                    cells.append(n)
                    stack.append(n)
                }
            }
            guard !runsOn, cells.count >= minArea, cells.count <= maxArea else { continue }
            var touches = false
            for at in cells where depthAt(at % w, at / w) == 0 {
                touches = true
                break
            }
            guard touches else { continue }

            // The paper beside the patch: bright pixels around its box that are not skin.
            var sumR = 0, sumG = 0, sumB = 0, count = 0
            let x0 = max(0, minX - grow - 4), x1 = min(w - 1, maxX + grow + 4)
            let y0 = max(0, minY - grow - 4), y1 = min(h - 1, maxY + grow + 4)
            for y in y0...y1 {
                for x in x0...x1 {
                    let i = y * w + x
                    if skin[i] == 0 && Double(gray[i]) >= brightest {
                        sumR += Int(image.pixels[i * 4])
                        sumG += Int(image.pixels[i * 4 + 1])
                        sumB += Int(image.pixels[i * 4 + 2])
                        count += 1
                    }
                }
            }
            guard count >= 20 else { continue }
            let fill: [UInt8] = [UInt8(sumR / count), UInt8(sumG / count), UInt8(sumB / count)]
            let gx0 = max(0, minX - grow), gx1 = min(w - 1, maxX + grow)
            let gy0 = max(0, minY - grow), gy1 = min(h - 1, maxY + grow)
            let bw = gx1 - gx0 + 1, bh = gy1 - gy0 + 1
            var cover = [UInt8](repeating: 0, count: bw * bh)
            for at in cells { cover[(at / w - gy0) * bw + (at % w - gx0)] = 1 }
            let wide = spread(cover, width: bw, height: bh, by: grow, alongRows: true)
            let grown = spread(wide, width: bw, height: bh, by: grow, alongRows: false)
            for y in gy0...gy1 {
                for x in gx0...gx1 where grown[(y - gy0) * bw + (x - gx0)] == 1 {
                    let o = (y * w + x) * 4
                    output.pixels[o] = fill[0]
                    output.pixels[o + 1] = fill[1]
                    output.pixels[o + 2] = fill[2]
                }
            }
            painted = true
        }
        return painted ? output : nil
    }

    /// `mask` with every set cell widened to the `by` cells on each side of it, along its rows or along its columns.
    private static func spread(_ mask: [UInt8], width bw: Int, height bh: Int, by: Int, alongRows: Bool) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: bw * bh)
        let lines = alongRows ? bh : bw
        let length = alongRows ? bw : bh
        let stepAlong = alongRows ? 1 : bw
        let stepAcross = alongRows ? bw : 1
        for line in 0..<lines {
            let start = line * stepAcross
            var since = by + 1
            for k in 0..<length {
                let i = start + k * stepAlong
                since = mask[i] == 1 ? 0 : since + 1
                if since <= by { result[i] = 1 }
            }
            since = by + 1
            for k in stride(from: length - 1, through: 0, by: -1) {
                let i = start + k * stepAlong
                since = mask[i] == 1 ? 0 : since + 1
                if since <= by { result[i] = 1 }
            }
        }
        return result
    }

    /// The paper's gray level: the `paperPercentile` of the middle rows.
    static func paperLevel(_ gray: [UInt8], width: Int, height: Int) -> Int {
        var histogram = [Int](repeating: 0, count: 256)
        let from = Int(Double(height) * paperRowsFrom), to = Int(Double(height) * paperRowsTo)
        for y in from..<max(from + 1, to) {
            for x in 0..<width {
                histogram[Int(gray[y * width + x])] += 1
            }
        }
        let wanted = Double(width * max(1, to - from)) * paperPercentile
        var seen = 0.0
        for level in 0..<256 {
            seen += Double(histogram[level])
            if seen >= wanted { return level }
        }
        return 255
    }

    /// The paper's mean color over the middle rows' pixels at or above `level`; nil when there are none.
    private static func paperTone(_ image: RgbaImage, gray: [UInt8], level: Int) -> (r: Int, g: Int, b: Int)? {
        let w = image.width, h = image.height
        let from = Int(Double(h) * paperRowsFrom), to = Int(Double(h) * paperRowsTo)
        var sumR = 0, sumG = 0, sumB = 0, count = 0
        for y in from..<max(from + 1, to) {
            for x in 0..<w where Int(gray[y * w + x]) >= level {
                let i = (y * w + x) * 4
                sumR += Int(image.pixels[i])
                sumG += Int(image.pixels[i + 1])
                sumB += Int(image.pixels[i + 2])
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return (sumR / count, sumG / count, sumB / count)
    }

    /// The row of the page's top edge in every column (or of its bottom edge, `fromTop` false): the first
    /// of `edgeRun` rows in a row that are paper, looked for within `depth` rows of the border, where a
    /// row is paper when the mean of the 2 × `edgeHalfWidth` + 1 columns around it reaches `threshold`.
    /// Columns with no such row take the nearest column's that has one; nil when fewer than
    /// `minFoundShare` do, or when the edge jumps by more than `maxEdgeStepShare` of the height between
    /// neighbouring columns that have one.
    private static func edges(_ gray: [UInt8], width w: Int, height h: Int, threshold: Double, depth: Int,
                              fromTop: Bool) -> [Double]? {
        var found = [Int](repeating: -1, count: w)
        var foundCount = 0
        for x in 0..<w {
            let c0 = max(0, x - edgeHalfWidth), c1 = min(w - 1, x + edgeHalfWidth)
            let need = threshold * Double(c1 - c0 + 1)
            var run = 0
            for step in 0..<depth {
                let y = fromTop ? step : h - 1 - step
                var sum = 0
                for c in c0...c1 {
                    sum += Int(gray[y * w + c])
                }
                if Double(sum) >= need {
                    run += 1
                    if run == edgeRun {
                        found[x] = fromTop ? y - (edgeRun - 1) : y + (edgeRun - 1)
                        foundCount += 1
                        break
                    }
                } else {
                    run = 0
                }
            }
        }
        guard Double(foundCount) >= Double(w) * minFoundShare else { return nil }
        let maxStep = Double(h) * maxEdgeStepShare
        var last = -1
        for x in 0..<w where found[x] >= 0 {
            if last >= 0 && abs(Double(found[x] - found[last])) > maxStep { return nil }
            last = x
        }
        var result = [Double](repeating: 0, count: w)
        var previous = -1
        for x in 0..<w where found[x] >= 0 {
            if previous < 0 {
                for k in 0..<x { result[k] = Double(found[x]) }
            } else {
                let gap = x - previous
                for k in (previous + 1)..<max(previous + 1, x) {
                    let share = Double(k - previous) / Double(gap)
                    result[k] = Double(found[previous]) + share * Double(found[x] - found[previous])
                }
            }
            result[x] = Double(found[x])
            previous = x
        }
        for k in (previous + 1)..<max(previous + 1, w) { result[k] = Double(found[previous]) }
        return result
    }

    /// `values` with a median over 2 × `half` + 1 columns (specks of text, a finger), then a mean over the same.
    private static func smoothed(_ values: [Double], half: Int) -> [Double] {
        let n = values.count
        var middle = [Double](repeating: 0, count: n)
        for x in 0..<n {
            let window = values[max(0, x - half)...min(n - 1, x + half)].sorted()
            middle[x] = window[window.count / 2]
        }
        var result = [Double](repeating: 0, count: n)
        for x in 0..<n {
            let from = max(0, x - half), to = min(n - 1, x + half)
            var sum = 0.0
            for k in from...to { sum += middle[k] }
            result[x] = sum / Double(to - from + 1)
        }
        return result
    }
}

/// Draws the page of a book taken by a camera flat (`PageFlatten.flatten`), right after `PerspectiveStep`;
/// the photo stays the other version. Once only, as `EnhanceStep`: pages not cut out along their corners,
/// pages already cleaned up or filtered, and pages with edges that are not found or are straight stay
/// as they are.
public struct FlattenStep: PageStep {
    public var name: String { "flatten" }

    public init() {}

    public func apply(_ page: ScannedPage) -> ScannedPage {
        guard let capture = page.capture, capture.scale != nil, capture.enhancement == nil, capture.filter == nil,
              page.geometry?.basis == .perspective,
              let pixels = RgbaImage(cgImage: page.image),
              let flat = PageFlatten.flatten(pixels),
              let image = flat.makeCGImage() else { return page }
        var flattened = page.withImage(image)
        flattened.capture?.flattened = true
        return flattened
    }
}

/// Paints the fingers at the margins of a camera's page with paper (`PageFlatten.fillFingers`); runs where
/// `FlattenStep` does, with the same conditions.
public struct FingerFillStep: PageStep {
    public var name: String { "fingers" }

    public init() {}

    public func apply(_ page: ScannedPage) -> ScannedPage {
        guard let capture = page.capture, capture.scale != nil, capture.enhancement == nil, capture.filter == nil,
              page.geometry?.basis == .perspective,
              let pixels = RgbaImage(cgImage: page.image),
              let filled = PageFlatten.fillFingers(pixels, dpi: Double(page.dpi)),
              let image = filled.makeCGImage() else { return page }
        var painted = page.withImage(image)
        painted.capture?.fingersFilled = true
        return painted
    }
}
