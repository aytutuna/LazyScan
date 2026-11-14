import XCTest
import CoreGraphics
@testable import LazyScanKit

// MARK: - Helpers

private func makeContext(width: Int, height: Int) -> CGContext {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                     bytesPerRow: width * 4, space: colorSpace,
                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// Deterministic RGB gradient: r ramps with x, g with y, b with x+y.
private func makeGradientImage(width: Int = 64, height: Int = 64) -> CGImage {
    let ctx = makeContext(width: width, height: height)
    let ptr = ctx.data!.assumingMemoryBound(to: UInt8.self)
    let rowBytes = ctx.bytesPerRow
    for y in 0..<height {
        for x in 0..<width {
            let i = y * rowBytes + x * 4
            ptr[i] = UInt8(x * 255 / (width - 1))
            ptr[i + 1] = UInt8(y * 255 / (height - 1))
            ptr[i + 2] = UInt8((x + y) * 255 / (width + height - 2))
            ptr[i + 3] = 255
        }
    }
    return ctx.makeImage()!
}

/// Mid-gray image with a 3x3 red marker in the top-left corner (pixel coordinates).
private func makeMarkerImage(width: Int, height: Int) -> CGImage {
    let ctx = makeContext(width: width, height: height)
    ctx.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    // Context origin is bottom-left, so the image's top-left corner is at y = height - 3.
    ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: CGFloat(height - 3), width: 3, height: 3))
    return ctx.makeImage()!
}

/// Renders any CGImage to a tightly-packed sRGB RGBA8 buffer (row 0 = top of image).
private func renderRGBA(_ image: CGImage) -> [UInt8] {
    let ctx = makeContext(width: image.width, height: image.height)
    ctx.interpolationQuality = .none
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
    let ptr = ctx.data!.assumingMemoryBound(to: UInt8.self)
    return Array(UnsafeBufferPointer(start: ptr, count: image.width * image.height * 4))
}

private func pixel(_ rgba: [UInt8], width: Int, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
    let i = (y * width + x) * 4
    return (Int(rgba[i]), Int(rgba[i + 1]), Int(rgba[i + 2]))
}

/// Mean and standard deviation of Rec.601 luminance over all pixels (0...255 scale).
private func luminanceStats(_ image: CGImage) -> (mean: Double, stddev: Double) {
    let rgba = renderRGBA(image)
    var values: [Double] = []
    values.reserveCapacity(rgba.count / 4)
    var i = 0
    while i < rgba.count {
        values.append(0.299 * Double(rgba[i]) + 0.587 * Double(rgba[i + 1]) + 0.114 * Double(rgba[i + 2]))
        i += 4
    }
    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    return (mean, variance.squareRoot())
}

// MARK: - Tests

final class ImagePipelineTests: XCTestCase {

    func test_brightnessRaisesMeanLuminance() {
        let input = makeGradientImage()
        var settings = AdjustmentSettings()
        settings.brightness = 0.5
        let output = ImagePipeline.apply(settings, to: input, colorMode: .color)
        XCTAssertEqual(output.width, input.width)
        XCTAssertEqual(output.height, input.height)
        XCTAssertGreaterThan(luminanceStats(output).mean, luminanceStats(input).mean + 10,
                             "brightness +0.5 must raise mean luminance")
    }

    func test_contrastRaisesStddev() {
        let input = makeGradientImage()
        var settings = AdjustmentSettings()
        settings.contrast = 2.0
        let output = ImagePipeline.apply(settings, to: input, colorMode: .color)
        XCTAssertGreaterThan(luminanceStats(output).stddev, luminanceStats(input).stddev * 1.2,
                             "contrast 2.0 must widen the luminance distribution")
    }

    func test_identityReturnsUnchangedPixels() {
        let input = makeGradientImage()
        let output = ImagePipeline.apply(AdjustmentSettings(), to: input, colorMode: .color)
        if output === input { return } // returning the same instance is explicitly allowed
        XCTAssertEqual(output.width, input.width)
        XCTAssertEqual(output.height, input.height)
        XCTAssertEqual(renderRGBA(output), renderRGBA(input),
                       "identity settings + .color must be pixel-identical")
    }

    func test_grayscaleMakesChannelsEqual() {
        let input = makeGradientImage()
        let output = ImagePipeline.apply(AdjustmentSettings(), to: input, colorMode: .grayscale)
        let rgba = renderRGBA(output)
        var maxDelta = 0
        var i = 0
        while i < rgba.count {
            let r = Int(rgba[i]), g = Int(rgba[i + 1]), b = Int(rgba[i + 2])
            maxDelta = max(maxDelta, abs(r - g), abs(g - b), abs(r - b))
            i += 4
        }
        XCTAssertLessThanOrEqual(maxDelta, 2, "grayscale output must have r==g==b (±2)")
    }

    func test_blackWhiteBinarizes() {
        let input = makeGradientImage()
        let output = ImagePipeline.apply(AdjustmentSettings(), to: input, colorMode: .blackWhite)
        let rgba = renderRGBA(output)
        var maxMidDistance = 0
        var i = 0
        while i < rgba.count {
            for c in 0..<3 {
                let v = Int(rgba[i + c])
                maxMidDistance = max(maxMidDistance, min(v, 255 - v))
            }
            i += 4
        }
        XCTAssertLessThanOrEqual(maxMidDistance, 6, "blackWhite output must be ~0 or ~255 everywhere")
    }

    func test_blackWhite_ofAGrayScan_followsTheThresholdAndPacksToOneBit() throws {
        // A scanner that hands over 8-bit gray in Black & White leaves the threshold to the app.
        let width = 64, height = 8
        let gray = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: gray,
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue))
        let ptr = ctx.data!.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width { ptr[y * width + x] = UInt8(x * 255 / (width - 1)) }
        }
        let scan = try XCTUnwrap(ctx.makeImage())

        func blackShare(_ threshold: Double) throws -> Int {
            var settings = AdjustmentSettings()
            settings.blackWhiteThreshold = threshold
            let output = ImagePipeline.apply(settings, to: scan, colorMode: .blackWhite)
            let rgba = renderRGBA(output)
            let black = stride(from: 0, to: rgba.count, by: 4).filter { rgba[$0] < 128 }.count
            let white = stride(from: 0, to: rgba.count, by: 4).filter { rgba[$0] > 127 }.count
            XCTAssertEqual(black + white, width * height)
            XCTAssertTrue(stride(from: 0, to: rgba.count, by: 4).allSatisfy { rgba[$0] <= 6 || rgba[$0] >= 249 })
            let packed = Bilevel.pack(try XCTUnwrap(RgbaImage(cgImage: output)))
            let packedBlack = (0..<height).reduce(0) { sum, y in
                sum + (0..<width).filter { Bilevel.isBlack(packed, width: width, x: $0, y: y) }.count
            }
            XCTAssertEqual(packedBlack, black)
            return black
        }
        let low = try blackShare(0.25)
        let high = try blackShare(0.75)
        XCTAssertLessThan(low, high)
    }

    func test_rotateOneQuarterTurnClockwise() {
        let input = makeMarkerImage(width: 64, height: 32)
        let output = ImagePipeline.rotate(input, quarterTurns: 1)
        XCTAssertEqual(output.width, 32)
        XCTAssertEqual(output.height, 64)

        // Clockwise: source top-left lands at the destination's top-right.
        // Probe (width-2, 1), which maps back to source (1, 1) inside the red marker.
        let rgba = renderRGBA(output)
        let probe = pixel(rgba, width: output.width, x: output.width - 2, y: 1)
        XCTAssertGreaterThan(probe.r, 200, "expected the red marker at the top-right; got \(probe)")
        XCTAssertLessThan(probe.g, 80, "expected the red marker at the top-right; got \(probe)")
        XCTAssertLessThan(probe.b, 80, "expected the red marker at the top-right; got \(probe)")
    }

    func test_rotateZeroKeepsDimensions() {
        let input = makeGradientImage(width: 64, height: 32)
        let output = ImagePipeline.rotate(input, quarterTurns: 0)
        XCTAssertEqual(output.width, 64)
        XCTAssertEqual(output.height, 32)
    }

    // MARK: - Restore faded colors

    /// A ramp from black to white seen through a yellow cast: blue falls short, red runs high.
    private func makeYellowedRamp(width: Int = 64, height: Int = 64) -> CGImage {
        let ctx = makeContext(width: width, height: height)
        let ptr = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let rowBytes = ctx.bytesPerRow
        for y in 0..<height {
            for x in 0..<width {
                let i = y * rowBytes + x * 4
                let ramp = Double(x) * 255.0 / Double(width - 1)
                ptr[i] = UInt8(30 + ramp * 0.85)
                ptr[i + 1] = UInt8(20 + ramp * 0.8)
                ptr[i + 2] = UInt8(ramp * 0.45)
                ptr[i + 3] = 255
            }
        }
        return ctx.makeImage()!
    }

    private func spread(_ p: (r: Int, g: Int, b: Int)) -> Int {
        max(p.r, p.g, p.b) - min(p.r, p.g, p.b)
    }

    private func makeHalftone(size: Int, period: Int) -> CGImage {
        let ctx = makeContext(width: size, height: size)
        let ptr = ctx.data!.assumingMemoryBound(to: UInt8.self)
        let rowBytes = ctx.bytesPerRow
        for y in 0..<size {
            for x in 0..<size {
                let i = y * rowBytes + x * 4
                let dark = (x / (period / 2) + y / (period / 2)) % 2 != 0
                ptr[i] = dark ? 0 : 255
                ptr[i + 1] = dark ? 0 : 255
                ptr[i + 2] = dark ? 0 : 255
                ptr[i + 3] = 255
            }
        }
        return ctx.makeImage()!
    }

    func test_descreenSigmaFollowsDpiFromOnePixel() {
        XCTAssertEqual(ImagePipeline.descreenSigma(dpi: 150), 1)
        XCTAssertEqual(ImagePipeline.descreenSigma(dpi: 300), 1)
        XCTAssertEqual(ImagePipeline.descreenSigma(dpi: 600), 2)
        XCTAssertEqual(ImagePipeline.descreenSigma(dpi: 1200), 4)
    }

    func test_descreenFlattensTheHalftoneMoreAtHigherDpi() {
        var settings = AdjustmentSettings()
        settings.descreen = true
        for dpi in [600, 1200] {
            let input = makeHalftone(size: 96, period: dpi / 75)
            let atDefault = luminanceStats(ImagePipeline.apply(settings, to: input, colorMode: .color)).stddev
            let scaled = luminanceStats(ImagePipeline.apply(settings, to: input, colorMode: .color, dpi: dpi)).stddev
            XCTAssertLessThan(scaled, atDefault * 0.6, "stddev at \(dpi) dpi \(scaled), at 300 dpi \(atDefault)")
        }
    }

    func test_restoreFadedColorsNeutralizesWhitesAndBlacks() {
        let input = makeYellowedRamp()
        let rgba = renderRGBA(input)
        XCTAssertGreaterThan(spread(pixel(rgba, width: 64, x: 63, y: 10)), 100)
        XCTAssertGreaterThan(spread(pixel(rgba, width: 64, x: 0, y: 10)), 20)
        var settings = AdjustmentSettings()
        settings.restoreFadedColors = true
        let output = renderRGBA(ImagePipeline.apply(settings, to: input, colorMode: .color))
        let white = pixel(output, width: 64, x: 63, y: 10)
        let black = pixel(output, width: 64, x: 0, y: 10)
        XCTAssertLessThanOrEqual(spread(white), 12, "white end must be near neutral, got \(white)")
        XCTAssertLessThanOrEqual(spread(black), 12, "black end must be near neutral, got \(black)")
        XCTAssertGreaterThan(white.r, 240)
        XCTAssertLessThan(black.r, 15)
    }

    func test_restoreFadedColorsLeavesGrayscaleToTheModeOnly() {
        let input = makeYellowedRamp()
        var settings = AdjustmentSettings()
        settings.restoreFadedColors = true
        let restored = renderRGBA(ImagePipeline.apply(settings, to: input, colorMode: .grayscale))
        let plain = renderRGBA(ImagePipeline.apply(AdjustmentSettings(), to: input, colorMode: .grayscale))
        XCTAssertLessThan(pixel(restored, width: 64, x: 63, y: 10).r, pixel(plain, width: 64, x: 63, y: 10).r + 20,
                          "grayscale keeps the original white level")
    }

    func test_negativeTablesInvertBetweenPercentiles() {
        let uniform = [Int](repeating: 100, count: 256)
        let tables = ImagePipeline.negativeTables([uniform, uniform, uniform])
        for table in tables {
            XCTAssertEqual(table[0], 255)
            XCTAssertEqual(table[1], 255)
            XCTAssertEqual(table[128], 127)
            XCTAssertEqual(table[254], 0)
            XCTAssertEqual(table[255], 0)
        }
    }

    func test_negativeTablesInvertNarrowChannelsAsTheyAre() {
        var narrow = [Int](repeating: 0, count: 256)
        for v in 100...140 { narrow[v] = 50 }
        let tables = ImagePipeline.negativeTables([narrow, narrow, narrow])
        for v in 0..<256 { XCTAssertEqual(Int(tables[0][v]), 255 - v) }
    }

    func test_invertNegativeTakesTheOrangeBaseToBlackAndKeepsAlpha() {
        // Left half: the film base (orange); right half: a dense patch that came out dark.
        var pixels = [UInt8](repeating: 0, count: 20 * 10 * 4)
        for i in 0..<(20 * 10) {
            let dense = i % 20 >= 10
            pixels[i * 4] = dense ? 40 : 230
            pixels[i * 4 + 1] = dense ? 20 : 150
            pixels[i * 4 + 2] = dense ? 10 : 90
            pixels[i * 4 + 3] = 200
        }
        let positive = ImagePipeline.invertNegative(RgbaImage(width: 20, height: 10, pixels: pixels)).pixels
        XCTAssertEqual(Array(positive[0..<4]), [0, 0, 0, 200])
        XCTAssertEqual(Array(positive[40..<44]), [255, 255, 255, 200])
    }

    func test_fadedColorTablesStretchBetweenPercentiles() {
        let uniform = [Int](repeating: 100, count: 256)
        let tables = ImagePipeline.fadedColorTables([uniform, uniform, uniform])
        for table in tables {
            XCTAssertEqual(table[0], 0)
            XCTAssertEqual(table[1], 0)
            XCTAssertEqual(table[128], 128)
            XCTAssertEqual(table[254], 255)
            XCTAssertEqual(table[255], 255)
        }
    }

    func test_fadedColorTablesLeaveNarrowChannelsAlone() {
        var narrow = [Int](repeating: 0, count: 256)
        for v in 100...140 { narrow[v] = 50 }
        let tables = ImagePipeline.fadedColorTables([narrow, narrow, narrow])
        for v in 0..<256 { XCTAssertEqual(Int(tables[0][v]), v) }
    }

    /// White 64x40 page with dark blocks as (x, y, width, height, kept): a 1 pixel speck, a 2x2 speck, a bar
    /// of 2 pixels, two specks touching only at a corner (four-connected, so apart), then what stays: a full
    /// stop (3x3), a 1 pixel stroke 20 long, and an i (a 3x3 dot over a 3x10 stem).
    private static let speckBlocks: [(Int, Int, Int, Int, Bool)] = [
        (5, 5, 1, 1, false), (15, 5, 2, 2, false), (25, 5, 1, 2, false),
        (35, 5, 1, 1, false), (36, 6, 1, 1, false),
        (45, 5, 3, 3, true), (30, 20, 20, 1, true),
        (10, 20, 3, 3, true), (10, 25, 3, 10, true),
    ]

    private func makeSpeckPage() -> CGImage {
        let ctx = makeContext(width: 64, height: 40)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 40))
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        for (x, y, w, h, _) in Self.speckBlocks {
            ctx.fill(CGRect(x: x, y: 40 - y - h, width: w, height: h))
        }
        return ctx.makeImage()!
    }

    func test_removeSpecks_dropsSmallDarkSpecksAndKeepsText() {
        var settings = AdjustmentSettings()
        settings.removeSpecks = true
        let page = makeSpeckPage()
        let kept = renderRGBA(ImagePipeline.apply(AdjustmentSettings(), to: page, colorMode: .blackWhite))
        let cleaned = renderRGBA(ImagePipeline.apply(settings, to: page, colorMode: .blackWhite))
        for (x, y, w, h, keep) in Self.speckBlocks {
            for py in y..<(y + h) {
                for px in x..<(x + w) {
                    let i = (py * 64 + px) * 4
                    XCTAssertEqual(kept[i], 0, "block at \(x),\(y) is dark without the option")
                    XCTAssertEqual(cleaned[i], keep ? 0 : 255, "block at \(x),\(y)")
                }
            }
        }
        var darkBefore = 0, darkAfter = 0
        var i = 0
        while i < kept.count {
            if kept[i] == 0 { darkBefore += 1 }
            if cleaned[i] == 0 { darkAfter += 1 }
            i += 4
        }
        XCTAssertEqual(darkBefore - darkAfter, 1 + 4 + 2 + 1 + 1)
    }

    func test_removeSpecks_isOffForColorAndGray() {
        var settings = AdjustmentSettings()
        settings.removeSpecks = true
        let page = makeSpeckPage()
        let gray = renderRGBA(ImagePipeline.apply(settings, to: page, colorMode: .grayscale))
        XCTAssertEqual(gray[(5 * 64 + 5) * 4], 0)
        XCTAssertEqual(renderRGBA(ImagePipeline.apply(settings, to: page, colorMode: .color))[(5 * 64 + 5) * 4], 0)
    }

    func test_speckArea_growsWithTheResolutionSquared() {
        XCTAssertEqual(ImagePipeline.speckArea(dpi: 300), 4)
        XCTAssertEqual(ImagePipeline.speckArea(dpi: 600), 16)
        XCTAssertEqual(ImagePipeline.speckArea(dpi: 150), 1)
        XCTAssertEqual(ImagePipeline.speckArea(dpi: 100), 1)
        XCTAssertEqual(ImagePipeline.speckArea(dpi: 200), 2)
    }

    func test_removeSpecks_atTheEdgesAndInOneRow() {
        var pixels = [UInt8](repeating: 255, count: 6 * 3)
        pixels[0] = 0                       // corner
        pixels[5] = 0; pixels[17] = 0       // two on the right edge, apart
        pixels[13] = 0; pixels[14] = 0      // a pair in the last row
        ImagePipeline.removeSpecks(&pixels, width: 6, height: 3, maxArea: 1)
        XCTAssertEqual(pixels.filter { $0 == 0 }.count, 2, "only the pair is bigger than one pixel")
        ImagePipeline.removeSpecks(&pixels, width: 6, height: 3, maxArea: 2)
        XCTAssertEqual(pixels.filter { $0 == 0 }.count, 0)
    }
}
