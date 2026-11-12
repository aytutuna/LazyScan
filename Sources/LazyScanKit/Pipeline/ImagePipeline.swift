import CoreGraphics
import CoreImage
import Foundation

public enum ImagePipeline {

    /// Single shared rendering context (sRGB working space), reused across all calls.
    private static let sharedContext: CIContext = {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        return CIContext(options: [
            .workingColorSpace: srgb,
            .outputColorSpace: srgb,
        ])
    }()

    /// Apply adjustments + color-mode conversion. Returns the input unchanged when
    /// `settings.isIdentity && colorMode == .color`.
    public static func apply(_ settings: AdjustmentSettings, to image: CGImage, colorMode: ColorMode) -> CGImage {
        if settings.isIdentity && colorMode == .color { return image }

        let ci = adjusted(CIImage(cgImage: image), with: settings, colorMode: colorMode, levelingChannels: true)

        // 7. Render, preserving the exact pixel dimensions of the input.
        //    Grayscale/B&W output renders as true 8-bit gray so memory and saved
        //    files don't inflate to 4-byte RGBA.
        let renderRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        if colorMode != .color,
           let gray = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2),
           let output = sharedContext.createCGImage(ci, from: renderRect, format: .L8, colorSpace: gray) {
            return output
        }
        guard let output = sharedContext.createCGImage(ci, from: renderRect) else { return image }
        return output
    }

    /// Steps 1-6 of `apply` as a Core Image chain, not rendered: the live viewfinder runs the same chain on
    /// each camera frame. `levelingChannels` adds the per-channel levels of Restore faded colors, which has to
    /// read the pixels, so the viewfinder leaves it off.
    public static func adjusted(_ image: CIImage, with settings: AdjustmentSettings, colorMode: ColorMode,
                                levelingChannels: Bool = false) -> CIImage {
        if settings.isIdentity && colorMode == .color { return image }

        var ci = image

        // 1. Auto enhance (Core Image's suggested filters, red-eye disabled), in order.
        if settings.autoEnhance {
            for filter in ci.autoAdjustmentFilters(options: [.redEye: false]) {
                filter.setValue(ci, forKey: kCIInputImageKey)
                ci = filter.outputImage ?? ci
            }
        }

        // 2. Brightness (-1...1) split across exposure (±1.5 EV) and a small additive
        //    lift, plus contrast and saturation via CIColorControls.
        if settings.brightness != 0 {
            ci = applyFilter("CIExposureAdjust", to: ci, parameters: [
                "inputEV": settings.brightness * 1.5,
            ])
        }
        let additiveBrightness = settings.brightness * 0.15
        if additiveBrightness != 0 || settings.contrast != 1 || settings.saturation != 1 {
            ci = applyFilter("CIColorControls", to: ci, parameters: [
                "inputBrightness": additiveBrightness,
                "inputContrast": settings.contrast,
                "inputSaturation": settings.saturation,
            ])
        }

        // 3. Sharpen — or, for negative values, soften with a small Gaussian blur
        //    (the blur expands the extent, so crop back to the original).
        if settings.sharpness > 0 {
            ci = applyFilter("CISharpenLuminance", to: ci, parameters: [
                "inputSharpness": settings.sharpness,
            ])
        } else if settings.sharpness < 0 {
            let preBlurExtent = ci.extent
            let blurred = applyFilter("CIGaussianBlur", to: ci.clampedToExtent(), parameters: [
                "inputRadius": min(-settings.sharpness, 2) * 2,
            ])
            ci = blurred.cropped(to: preBlurExtent)
        }

        // 4. Descreen: tiny blur to break up halftone moiré, then a mild re-sharpen.
        //    The blur expands the extent, so crop back to the pre-blur extent.
        if settings.descreen {
            let preBlurExtent = ci.extent
            let blurred = applyFilter("CIGaussianBlur", to: ci.clampedToExtent(), parameters: [
                "inputRadius": 1.0,
            ])
            ci = blurred.cropped(to: preBlurExtent)
            ci = applyFilter("CISharpenLuminance", to: ci, parameters: [
                "inputSharpness": 0.4,
            ])
        }

        // 5. Restore faded colors: each channel stretched between its own percentiles with the midtone
        //    cast neutralized (color scans only), then a vibrance boost and slight contrast.
        if settings.restoreFadedColors {
            if levelingChannels && colorMode == .color {
                ci = levelChannels(ci)
            }
            ci = applyFilter("CIVibrance", to: ci, parameters: [
                "inputAmount": 0.5,
            ])
            ci = applyFilter("CIColorControls", to: ci, parameters: [
                "inputContrast": 1.05,
            ])
        }

        // 6. Color-mode conversion.
        switch colorMode {
        case .color:
            break
        case .grayscale:
            ci = applyFilter("CIColorControls", to: ci, parameters: [
                "inputSaturation": 0.0,
            ])
        case .blackWhite:
            // CIColorThreshold binarizes per channel; desaturate first so the
            // threshold applies to luminance (a red pixel must not survive as
            // pure red and land as mid-gray in the L8 output).
            ci = applyFilter("CIColorControls", to: ci, parameters: [
                "inputSaturation": 0.0,
            ])
            ci = applyFilter("CIColorThreshold", to: ci, parameters: [
                "inputThreshold": settings.blackWhiteThreshold,
            ])
        }

        return ci
    }

    /// Lossless 90° steps, clockwise. quarterTurns 0...3.
    public static func rotate(_ image: CGImage, quarterTurns: Int) -> CGImage {
        let turns = ((quarterTurns % 4) + 4) % 4
        guard turns != 0 else { return image }

        let w = image.width, h = image.height
        let swapsAxes = turns % 2 == 1
        let newWidth = swapsAxes ? h : w
        let newHeight = swapsAxes ? w : h
        guard let context = makeContext(width: newWidth, height: newHeight, matching: image) else {
            return image
        }
        context.interpolationQuality = .none

        // CGContext coordinates are bottom-left origin, y up; a *visual* clockwise
        // rotation is a negative rotation there. Rotate the drawing about the origin,
        // then translate its bounding box back into the context.
        switch turns {
        case 1:
            context.translateBy(x: 0, y: CGFloat(w))
            context.rotate(by: -.pi / 2)
        case 2:
            context.translateBy(x: CGFloat(w), y: CGFloat(h))
            context.rotate(by: .pi)
        default: // 3
            context.translateBy(x: CGFloat(h), y: 0)
            context.rotate(by: .pi / 2)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        return context.makeImage() ?? image
    }

    // MARK: - Faded colors

    private static let fadedClip = 5            // per mille cut off at each end
    private static let fadedMinSpan = 64        // narrower channels are left as they are

    /// One 256-entry table per channel from its byte histogram: the channel is stretched between the
    /// values that leave 0.5% of the pixels outside, then a gamma moves its stretched median to the mean of the
    /// three medians, which removes the cast of the midtones.
    static func fadedColorTables(_ histograms: [[Int]]) -> [[UInt8]] {
        var lows = [Int](repeating: 0, count: 3)
        var highs = [Int](repeating: 255, count: 3)
        var medians = [Double](repeating: 0, count: 3)
        for c in 0..<3 {
            let h = histograms[c]
            let total = h.reduce(0, +)
            let skip = total * fadedClip / 1000
            var low = 0, high = 255, median = 0
            var sum = 0
            for v in 0..<256 {
                sum += h[v]
                if sum > skip { low = v; break }
            }
            sum = 0
            for v in stride(from: 255, through: 0, by: -1) {
                sum += h[v]
                if sum > skip { high = v; break }
            }
            sum = 0
            for v in 0..<256 {
                sum += h[v]
                if sum * 2 >= total { median = v; break }
            }
            if high - low >= fadedMinSpan {
                lows[c] = low
                highs[c] = high
            }
            let span = Double(highs[c] - lows[c])
            medians[c] = min(max(Double(median - lows[c]) / span, 0), 1)
        }
        let target = (medians[0] + medians[1] + medians[2]) / 3
        return (0..<3).map { (c: Int) -> [UInt8] in
            var gamma = 1.0
            if medians[c] > 0.02 && medians[c] < 0.98 && target > 0.02 && target < 0.98 {
                gamma = min(max(log(target) / log(medians[c]), 0.7), 1.4)
            }
            let span = Double(highs[c] - lows[c])
            return (0..<256).map { (v: Int) -> UInt8 in
                let t = min(max(Double(v - lows[c]) / span, 0), 1)
                return UInt8(min(max((pow(t, gamma) * 255).rounded(), 0), 255))
            }
        }
    }

    /// Renders the chain to bytes, applies `fadedColorTables` to the color channels and returns the result
    /// as an image again.
    private static func levelChannels(_ image: CIImage) -> CIImage {
        let bounds = image.extent.integral
        guard !bounds.isInfinite, bounds.width > 0, bounds.height > 0 else { return image }
        let width = Int(bounds.width), height = Int(bounds.height)
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        sharedContext.render(image, toBitmap: &bytes, rowBytes: width * 4, bounds: bounds,
                             format: .RGBA8, colorSpace: srgb)
        var histograms = [[Int]](repeating: [Int](repeating: 0, count: 256), count: 3)
        var i = 0
        while i < bytes.count {
            for c in 0..<3 { histograms[c][Int(bytes[i + c])] += 1 }
            i += 4
        }
        let tables = fadedColorTables(histograms)
        i = 0
        while i < bytes.count {
            for c in 0..<3 { bytes[i + c] = tables[c][Int(bytes[i + c])] }
            i += 4
        }
        let leveled = CIImage(bitmapData: Data(bytes), bytesPerRow: width * 4, size: bounds.size,
                              format: .RGBA8, colorSpace: srgb)
        return leveled.transformed(by: CGAffineTransform(translationX: bounds.minX, y: bounds.minY))
    }

    // MARK: - Private helpers

    private static func applyFilter(_ name: String, to image: CIImage, parameters: [String: Any]) -> CIImage {
        guard let filter = CIFilter(name: name) else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        for (key, value) in parameters {
            filter.setValue(value, forKey: key)
        }
        return filter.outputImage ?? image
    }

    /// A bitmap context matching the source image's format where possible, falling
    /// back to standard 8-bit sRGB when the source format is not context-drawable.
    private static func makeContext(width: Int, height: Int, matching image: CGImage) -> CGContext? {
        let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
        if let context = CGContext(data: nil,
                                   width: width,
                                   height: height,
                                   bitsPerComponent: image.bitsPerComponent,
                                   bytesPerRow: 0,
                                   space: image.colorSpace ?? srgb,
                                   bitmapInfo: image.bitmapInfo.rawValue) {
            return context
        }
        return CGContext(data: nil,
                         width: width,
                         height: height,
                         bitsPerComponent: 8,
                         bytesPerRow: 0,
                         space: srgb,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}
