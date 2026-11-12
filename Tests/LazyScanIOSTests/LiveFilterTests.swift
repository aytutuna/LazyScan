#if os(iOS)
import CoreImage
import XCTest
@testable import LazyScanIOS
@testable import LazyScanKit

// The viewfinder's filter (`LiveFilter`, measured by `LiveStats`) against the saved page (`DocumentEnhancer`):
// a shaded sheet with dark print, in gray and in colour, run through Enhanced, Grayscale and Black and white,
// compared by the mean absolute difference per channel (0...255). The two are not byte for byte: the paper
// is measured on a small copy and smoothed, Core Image works in half floats, and the stretch is not
// quantised to 1024 levels. Same-size measures are held to 2.5 levels (5 for black and white, where a
// differing pixel is 255 off, so 5 is 2 % of the pixels), a measure taken from a copy half the size of the
// frame, as the camera does, to 5 (10). Core Image runs on the software renderer here; the GPU's rounding
// can differ a little more.
final class LiveFilterTests: XCTestCase {
    private let context: CIContext = CIContext(options: [
        .workingColorSpace: NSNull(),
        .outputColorSpace: NSNull(),
        .useSoftwareRenderer: true,
    ])

    // MARK: Fixtures

    /// A sheet of `width` x `height` with lines of print, lit unevenly: darker to the right and the bottom.
    private func sheet(width: Int, height: Int, colored: Bool) -> RgbaImage {
        var pixels: [UInt8] = [UInt8](repeating: 255, count: width * height * 4)
        var y: Int = 0
        while y < height {
            var x: Int = 0
            while x < width {
                let u: Double = (Double(x) + 0.5) / Double(width)
                let v: Double = (Double(y) + 0.5) / Double(height)
                let light: Double = 1.0 - 0.35 * u - 0.15 * v
                let line: Double = v * 20
                let inLine: Bool = line >= 2 && line < 18 && line - floor(line) >= 0.35 && line - floor(line) < 0.6
                let inWord: Bool = u > 0.1 && u < 0.9 && Int(u * 40) % 5 != 4
                var red: Double = colored ? 240 : 232
                var green: Double = colored ? 226 : 232
                var blue: Double = colored ? 200 : 232
                if inLine && inWord {
                    red = colored ? 30 : 35
                    green = colored ? 40 : 35
                    blue = colored ? 120 : 35
                }
                let i: Int = (y * width + x) * 4
                pixels[i] = UInt8(red * light)
                pixels[i + 1] = UInt8(green * light)
                pixels[i + 2] = UInt8(blue * light)
                x += 1
            }
            y += 1
        }
        return RgbaImage(width: width, height: height, pixels: pixels)
    }

    private func frame(_ image: RgbaImage) -> CIImage {
        CIImage(bitmapData: Data(image.pixels), bytesPerRow: image.width * 4,
                size: CGSize(width: image.width, height: image.height), format: .RGBA8, colorSpace: nil)
    }

    private func render(_ image: CIImage, width: Int, height: Int) -> [UInt8] {
        var bytes: [UInt8] = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> Void in
            context.render(image, toBitmap: buffer.baseAddress!, rowBytes: width * 4,
                           bounds: CGRect(x: 0, y: 0, width: width, height: height), format: .RGBA8, colorSpace: nil)
        }
        return bytes
    }

    private func meanDifference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var total: Int = 0
        var count: Int = 0
        var i: Int = 0
        while i < a.count {
            total += abs(Int(a[i]) - Int(b[i]))
            total += abs(Int(a[i + 1]) - Int(b[i + 1]))
            total += abs(Int(a[i + 2]) - Int(b[i + 2]))
            count += 3
            i += 4
        }
        return Double(total) / Double(count)
    }

    /// The live look of `image` as `look` says, its paper measured on `measured`, against the saved page's
    /// clean-up of the same pixels.
    private func difference(_ image: RgbaImage, measured: RgbaImage, filter: CaptureFilter) -> Double {
        let look: LiveLook = LiveLook(settings: IOSShell.settingDrawerFilter(filter, in: ScanSettings()))
        let mode: DocumentEnhanceMode = look.mode ?? .auto
        let stats: LiveStats = LiveStats.measure(measured, mode: mode)
        let live: [UInt8] = render(LiveFilter.apply(frame(image), look: look, stats: stats), width: image.width,
                                   height: image.height)
        let saved: RgbaImage = DocumentEnhancer.enhance(image, mode: mode).image
        return meanDifference(live, saved.pixels)
    }

    // MARK: The filters against the saved page

    func test_grayPage_followsTheSavedPage() {
        let image: RgbaImage = sheet(width: 480, height: 360, colored: false)
        XCTAssertLessThan(difference(image, measured: image, filter: .enhanced), 2.5)
        XCTAssertLessThan(difference(image, measured: image, filter: .grayscale), 2.5)
        XCTAssertLessThan(difference(image, measured: image, filter: .blackAndWhite), 5.0)
    }

    func test_colourPage_followsTheSavedPage() {
        let image: RgbaImage = sheet(width: 480, height: 360, colored: true)
        XCTAssertLessThan(difference(image, measured: image, filter: .enhanced), 2.5)
        XCTAssertLessThan(difference(image, measured: image, filter: .grayscale), 2.5)
        XCTAssertLessThan(difference(image, measured: image, filter: .blackAndWhite), 5.0)
    }

    func test_paperMeasuredOnASmallerCopy_stillFollowsTheSavedPage() {
        for colored in [false, true] {
            let image: RgbaImage = sheet(width: 960, height: 720, colored: colored)
            let small: RgbaImage = sheet(width: 480, height: 360, colored: colored)
            XCTAssertLessThan(difference(image, measured: small, filter: .enhanced), 5.0)
            XCTAssertLessThan(difference(image, measured: small, filter: .grayscale), 5.0)
            XCTAssertLessThan(difference(image, measured: small, filter: .blackAndWhite), 10.0)
        }
    }

    func test_blackAndWhite_leavesOnlyBlackAndWhite() {
        let image: RgbaImage = sheet(width: 240, height: 180, colored: true)
        let look: LiveLook = LiveLook(settings: IOSShell.settingDrawerFilter(.blackAndWhite, in: ScanSettings()))
        let stats: LiveStats = LiveStats.measure(image, mode: .blackAndWhite)
        let bytes: [UInt8] = render(LiveFilter.apply(frame(image), look: look, stats: stats), width: 240, height: 180)
        var other: Int = 0
        var i: Int = 0
        while i < bytes.count {
            if bytes[i] > 2 && bytes[i] < 253 || bytes[i] != bytes[i + 1] || bytes[i] != bytes[i + 2] {
                other += 1
            }
            i += 4
        }
        XCTAssertLessThan(Double(other) / Double(240 * 180), 0.001)
    }

    func test_blackAndWhite_blackensMoreOfThePageAsTheThresholdRises() {
        let image: RgbaImage = sheet(width: 240, height: 180, colored: false)
        let stats: LiveStats = LiveStats.measure(image, mode: .blackAndWhite)
        func black(_ threshold: Double) -> Int {
            var settings: ScanSettings = IOSShell.settingDrawerFilter(.blackAndWhite, in: ScanSettings())
            settings.adjustments.blackWhiteThreshold = threshold
            let bytes: [UInt8] = render(LiveFilter.apply(frame(image), look: LiveLook(settings: settings), stats: stats),
                                        width: 240, height: 180)
            var count: Int = 0
            var i: Int = 0
            while i < bytes.count {
                if bytes[i] < 128 { count += 1 }
                i += 4
            }
            return count
        }
        XCTAssertLessThanOrEqual(black(0.2), black(0.5))
        XCTAssertLessThanOrEqual(black(0.5), black(0.8))
        var low: ScanSettings = ScanSettings()
        low.adjustments.blackWhiteThreshold = 0.2
        XCTAssertNotEqual(LiveLook(settings: low), LiveLook(settings: ScanSettings()))
    }

    func test_photoStretch_followsThePhotoLook() {
        let width: Int = 240
        let height: Int = 180
        var pixels: [UInt8] = [UInt8](repeating: 255, count: width * height * 4)
        var p: Int = 0
        while p < width * height {
            let u: Double = Double(p % width) / Double(width)
            let v: Double = Double(p / width) / Double(height)
            pixels[p * 4] = UInt8(60 + 130 * u)
            pixels[p * 4 + 1] = UInt8(70 + 110 * v)
            pixels[p * 4 + 2] = UInt8(80 + 90 * (u + v) / 2)
            p += 1
        }
        let image: RgbaImage = RgbaImage(width: width, height: height, pixels: pixels)
        let look: LiveLook = LiveLook(settings: TaskCatalog.apply(.photos, to: ScanSettings()))
        XCTAssertEqual(look.mode, .photo)
        let stats: LiveStats = LiveStats.measure(image, mode: .photo)
        let live: [UInt8] = render(LiveFilter.apply(frame(image), look: look, stats: stats), width: width, height: height)
        XCTAssertLessThan(meanDifference(live, DocumentEnhancer.photo(image).pixels), 2.0)
    }

    // MARK: When nothing is drawn

    func test_originalWithPlainAdjustments_needsNoFiltering() {
        var settings: ScanSettings = ScanSettings()
        settings.taskOptions.cameraFilter = .original
        XCTAssertFalse(LiveLook(settings: settings).isFiltering)
        // Auto-enhance reads a histogram of the whole picture: not run on frames.
        settings.adjustments.autoEnhance = true
        XCTAssertFalse(LiveLook(settings: settings).isFiltering)
    }

    func test_aFilterColourModeOrAdjustment_needsFiltering() {
        XCTAssertTrue(LiveLook(settings: ScanSettings()).isFiltering)
        var original: ScanSettings = ScanSettings()
        original.taskOptions.cameraFilter = .original
        original.adjustments.brightness = 0.2
        XCTAssertTrue(LiveLook(settings: original).isFiltering)
        for filter in [CaptureFilter.grayscale, CaptureFilter.blackAndWhite] {
            var settings: ScanSettings = IOSShell.settingDrawerFilter(filter, in: ScanSettings())
            settings.taskOptions.cameraFilter = .original
            XCTAssertTrue(LiveLook(settings: settings).isFiltering)
        }
    }

    func test_anIdCard_isShownAsAPhoto_evenUnderOriginal() {
        var card: ScanSettings = TaskCatalog.apply(.idCard, to: ScanSettings())
        card.taskOptions.cameraFilter = .original
        let look: LiveLook = LiveLook(settings: card)
        XCTAssertEqual(look.mode, .photo)
        XCTAssertTrue(look.isFiltering)
    }
}
#endif
