#if os(iOS)
import CoreImage
import Foundation
import LazyScanKit

/// The look a camera page gets when it is saved, as far as the viewfinder can show it: the clean-up of the
/// settings' task (`DocumentEnhancer.mode(for:)`, a photo or an ID card always a photo), the colour mode and
/// the adjustments. Auto-enhance is left out, since Core Image picks its filters from a histogram of the
/// whole picture, which is too slow for every frame.
struct LiveLook: Equatable, Sendable {
    let mode: DocumentEnhanceMode?
    let colorMode: ColorMode
    let adjustments: AdjustmentSettings

    init(settings: ScanSettings) {
        let kind: CaptureKind = CaptureObjects.kind(for: settings)
        let asPhoto: DocumentEnhanceMode? = DocumentEnhancer.mode(.auto, kind: kind) == .photo ? .photo : nil
        if let chosen = DocumentEnhancer.mode(for: settings) ?? asPhoto {
            mode = DocumentEnhancer.mode(chosen, kind: kind)
        } else {
            mode = nil
        }
        colorMode = settings.colorMode
        var kept: AdjustmentSettings = settings.adjustments
        kept.autoEnhance = false
        adjustments = kept
    }

    /// Whether the saved page differs from what the camera sees; false for Original with the adjustments
    /// untouched, where the plain preview is shown and nothing extra is drawn.
    var isFiltering: Bool {
        mode != nil || colorMode != .color || !adjustments.isIdentity
    }
}

/// What a frame has to be measured for to be cleaned up as `DocumentEnhancer` does: the paper's brightness
/// across the frame (as a grid of gains, 255 over the paper), the paper's white balance and the black point,
/// or for a photo (and a light on dark page) the range its levels are stretched from. Measured on a small
/// copy of the frame, a few times a second (`LiveViewfinder`); `LiveFilter` applies it to every frame.
struct LiveStats: Sendable {
    /// Grid cells per tile of the paper map.
    static let cellsPerTile: Int = 8

    /// The paper's gain, row-major, `columns` + 2 by `rows` + 2: the grid with its edge cells repeated, so
    /// the picture is not faded where it is sampled past the first and last cell.
    var gains: [Float]
    var columns: Int
    var rows: Int
    var balance: PaperWhiteBalance
    var blackPoint: Double
    /// The levels (0...255) stretched to black and white; nil for a page evened out against its paper.
    var photoRange: ClosedRange<Double>?
    /// For `.auto`: the clean-up leaves the page gray. Changes only after three measures in a row say so, so
    /// a page on the edge of having colour does not flicker between the two.
    var isGray: Bool?
    private var flips: Int = 0

    /// Fraction of the way a new measure moves the one before.
    static let followShare: Double = 0.5

    /// `image` measured for `mode`, moved part of the way from `previous` so exposure shifts and a
    /// changing estimate do not pump.
    static func measure(_ image: RgbaImage, mode: DocumentEnhanceMode, after previous: LiveStats? = nil) -> LiveStats {
        let gray: GrayImage = GrayImage.luma(image)
        var fresh: LiveStats
        if mode != .photo, !DocumentEnhancer.isLightOnDark(gray), let paper = DocumentEnhancer.paperMap(gray) {
            fresh = document(image, gray: gray, paper: paper)
        } else {
            fresh = photo(image, gray: gray)
        }
        if mode == .auto {
            fresh.isGray = DocumentEnhancer.enhance(image, mode: .auto).mode == .gray
        }
        guard let before = previous else { return fresh }
        return before.moved(toward: fresh)
    }

    private static func document(_ image: RgbaImage, gray: GrayImage, paper: BackgroundMap) -> LiveStats {
        let columns: Int = paper.columns * cellsPerTile
        let rows: Int = paper.rows * cellsPerTile
        let across: Int = columns + 2
        var gains: [Float] = [Float](repeating: 1, count: across * (rows + 2))
        var gy: Int = 0
        while gy < rows + 2 {
            let cy: Int = min(max(gy - 1, 0), rows - 1)
            let y: Int = min(image.height - 1, Int((Double(cy) + 0.5) * Double(image.height) / Double(rows)))
            var gx: Int = 0
            while gx < across {
                let cx: Int = min(max(gx - 1, 0), columns - 1)
                let x: Int = min(image.width - 1, Int((Double(cx) + 0.5) * Double(image.width) / Double(columns)))
                gains[gy * across + gx] = Float(255.0 / paper.valueAt(x: x, y: y))
                gx += 1
            }
            gy += 1
        }
        return LiveStats(gains: gains, columns: columns, rows: rows,
                         balance: DocumentEnhancer.whiteBalance(image, gray: gray, paper: paper),
                         blackPoint: DocumentEnhancer.blackPoint(gray, paper: paper), photoRange: nil, isGray: nil)
    }

    /// The range `DocumentEnhancer.photo` stretches, from the same percentiles; the whole range (no change)
    /// when the levels are already close together.
    private static func photo(_ image: RgbaImage, gray: GrayImage) -> LiveStats {
        var histogram: [Int] = [Int](repeating: 0, count: 256)
        for value in gray.pixels {
            histogram[Int(value)] += 1
        }
        let count: Int = image.width * image.height
        let low: Double = Double(BackgroundMap.percentile(histogram, count: count, fraction: DocumentEnhancer.photoClip))
        let high: Double = Double(BackgroundMap.percentile(histogram, count: count, fraction: 1 - DocumentEnhancer.photoClip))
        let range: ClosedRange<Double> = high - low >= Double(DocumentEnhancer.minPhotoRange) ? low...high : 0...255
        return LiveStats(gains: [], columns: 0, rows: 0, balance: PaperWhiteBalance.neutral, blackPoint: 0,
                         photoRange: range, isGray: nil)
    }

    private func moved(toward next: LiveStats) -> LiveStats {
        var result: LiveStats = next
        var gray: Bool? = next.isGray
        if let was = isGray, let now = next.isGray, was != now {
            result.flips = flips + 1
            if result.flips < 3 {
                gray = was
            } else {
                result.flips = 0
            }
        }
        result.isGray = gray
        guard gains.count == next.gains.count, (photoRange == nil) == (next.photoRange == nil) else { return result }
        let share: Double = LiveStats.followShare
        var index: Int = 0
        while index < gains.count {
            result.gains[index] = gains[index] + (next.gains[index] - gains[index]) * Float(share)
            index += 1
        }
        result.balance = PaperWhiteBalance(r: balance.r + (next.balance.r - balance.r) * share,
                                           g: balance.g + (next.balance.g - balance.g) * share,
                                           b: balance.b + (next.balance.b - balance.b) * share)
        result.blackPoint = blackPoint + (next.blackPoint - blackPoint) * share
        if let from = photoRange, let to = next.photoRange {
            let low: Double = from.lowerBound + (to.lowerBound - from.lowerBound) * share
            let high: Double = from.upperBound + (to.upperBound - from.upperBound) * share
            result.photoRange = low...high
        }
        return result
    }
}

/// `DocumentEnhancer` and `ImagePipeline` as Core Image, for the camera's frames. The paper is not
/// estimated here: `LiveStats` brings it from a small copy of a recent frame, and this divides the frame by
/// it, white balances it, stretches the levels (black and white thresholds them where the saved page does, at
/// `blackShare` of the paper) and then runs the adjustments through the same chain as the saved page. The frame
/// is read as plain numbers (no colour management, so the maths is the saved page's, on the same values).
/// Not run per frame: straightening, the cut along the page's corners, the receipt clean-up, auto-enhance.
enum LiveFilter {
    static func apply(_ frame: CIImage, look: LiveLook, stats: LiveStats?) -> CIImage {
        var image: CIImage = frame
        var colorMode: ColorMode = look.colorMode
        if let mode = look.mode, let measured = stats {
            let gray: Bool = mode == .gray || mode == .blackAndWhite || (mode == .auto && measured.isGray == true)
            image = stretched(image, with: measured, gray: gray)
            if mode == .blackAndWhite {
                // The saved page is black below `blackShare` of the paper, which is this value once stretched;
                // a light-on-dark page is stretched as a photo and cut at the threshold itself.
                let threshold: Double = look.adjustments.blackWhiteThreshold
                var level: Double = threshold
                if measured.photoRange == nil {
                    let share: Double = DocumentEnhancer.blackShare(threshold: threshold)
                    level = (share - measured.blackPoint) / (DocumentEnhancer.whitePoint - measured.blackPoint)
                }
                image = image.applyingFilter("CIColorThreshold", parameters: ["inputThreshold": level])
            }
            // A page the clean-up left gray is adjusted as a gray one (`AdjustmentStep.mode(for:)`).
            if gray && colorMode == .color {
                colorMode = .grayscale
            }
        }
        return ImagePipeline.adjusted(image, with: look.adjustments, colorMode: colorMode)
    }

    private static func stretched(_ image: CIImage, with stats: LiveStats, gray: Bool) -> CIImage {
        var source: CIImage = image
        let scale: Double
        let bias: Double
        if let range = stats.photoRange {
            let span: Double = range.upperBound - range.lowerBound
            scale = 255 / span
            bias = -range.lowerBound / span
        } else {
            let span: Double = DocumentEnhancer.whitePoint - stats.blackPoint
            scale = 1 / span
            bias = -stats.blackPoint / span
            source = divided(source, by: stats, balanced: !gray)
        }
        var red: CIVector = CIVector(x: scale, y: 0, z: 0, w: 0)
        var green: CIVector = CIVector(x: 0, y: scale, z: 0, w: 0)
        var blue: CIVector = CIVector(x: 0, y: 0, z: scale, w: 0)
        if gray {
            let luma: CIVector = CIVector(x: 0.299 * scale, y: 0.587 * scale, z: 0.114 * scale, w: 0)
            red = luma
            green = luma
            blue = luma
        }
        let matrix: CIImage = source.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": red,
            "inputGVector": green,
            "inputBVector": blue,
            "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0),
        ])
        return matrix.applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
        ])
    }

    /// `image` against the paper: each channel times the paper's gain there (and its white balance). The
    /// gain grid is a small float image, scaled up by Core Image with bilinear sampling, as the paper map
    /// is interpolated between tile centres.
    private static func divided(_ image: CIImage, by stats: LiveStats, balanced: Bool) -> CIImage {
        let across: Int = stats.columns + 2
        let down: Int = stats.rows + 2
        var red: Float = 1
        var green: Float = 1
        var blue: Float = 1
        if balanced {
            red = Float(stats.balance.r)
            green = Float(stats.balance.g)
            blue = Float(stats.balance.b)
        }
        var floats: [Float] = [Float](repeating: 1, count: across * down * 4)
        var cell: Int = 0
        while cell < across * down {
            let gain: Float = stats.gains[cell]
            floats[cell * 4] = gain * red
            floats[cell * 4 + 1] = gain * green
            floats[cell * 4 + 2] = gain * blue
            cell += 1
        }
        let data: Data = floats.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Data in
            Data(buffer: buffer)
        }
        let grid: CIImage = CIImage(bitmapData: data, bytesPerRow: across * 16, size: CGSize(width: across, height: down),
                                    format: .RGBAf, colorSpace: nil)
        let extent: CGRect = image.extent
        let fit: CGAffineTransform = CGAffineTransform(translationX: -1, y: -1)
            .concatenating(CGAffineTransform(scaleX: extent.width / CGFloat(stats.columns),
                                             y: extent.height / CGFloat(stats.rows)))
            .concatenating(CGAffineTransform(translationX: extent.minX, y: extent.minY))
        let map: CIImage = grid.transformed(by: fit).cropped(to: extent)
        return map.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: image])
    }
}
#endif
