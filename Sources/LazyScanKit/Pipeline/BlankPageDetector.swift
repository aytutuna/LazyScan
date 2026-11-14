import CoreGraphics
import Foundation

/// What `BlankPageDetector.analyze` looks for. Twin of C# `BlankPageOptions`.
public struct BlankPageOptions: Equatable, Sendable {
    /// How much may be on the page for it to count as blank.
    public var sensitivity: BlankSensitivity
    /// The band along every edge that is not looked at: edge shadows and staples live there.
    /// Punched holes reach past it and are dealt with by `BlankPageDetector.holeBandInches`.
    /// Pages whose short side is under `BlankPageDetector.smallPageInches` use
    /// `BlankPageDetector.smallPageMarginFraction` of it instead.
    public var marginInches: Double

    public init(sensitivity: BlankSensitivity = .medium, marginInches: Double = BlankPageDetector.marginInches) {
        self.sensitivity = sensitivity
        self.marginInches = marginInches
    }
}

/// What the blank-page check found on a page. Twin of C# `BlankPageResult`.
public struct BlankPageResult: Equatable, Codable, Sendable {
    /// Share of the area looked at covered by marks larger than dust (0...1).
    public let inkCoverage: Double
    /// Marks larger than dust.
    public let inkComponents: Int
    /// A photo, a dark block or a dark band covers part of the page: such a page is never blank.
    public let hasLargeDarkArea: Bool
    /// The page counts as blank at the sensitivity it was checked with.
    public let isBlank: Bool

    public init(inkCoverage: Double, inkComponents: Int, hasLargeDarkArea: Bool, isBlank: Bool) {
        self.inkCoverage = inkCoverage
        self.inkComponents = inkComponents
        self.hasLargeDarkArea = hasLargeDarkArea
        self.isBlank = isBlank
    }

    /// Whether the page counts as blank at `sensitivity`.
    public func isBlankAt(_ sensitivity: BlankSensitivity) -> Bool {
        !hasLargeDarkArea && inkCoverage < BlankPageDetector.threshold(sensitivity)
    }
}

/// Tells blank pages (the empty back of a one-sided sheet in a two-sided scan, a separator left
/// in the stack) from pages with something on them, robust to what scanners add to an empty
/// page: noise, dust, tinted or uneven paper, edge shadows, punched holes and the other side
/// showing through. All at `GrayImage.analysisDPI`:
/// 1. The edges are left out (`BlankPageOptions.marginInches`).
/// 2. The paper's brightness is mapped in tiles (`BackgroundMap`, 90th percentile), each tile
///    raised to the brightest of its neighbors, and to no less than the page's median minus
///    `darkAreaDrop`, so a photo or a dark block is never taken for paper. When more than
///    `darkTileFraction` of the tiles are that dark, the page has a large dark area and is never
///    blank.
/// 3. A pixel is ink when it is darker than (1 − `inkContrast`) of the paper there: print and
///    pencil are, show-through and paper texture are not. Solid dark marks within
///    `holeBandInches` of the edge are punched holes, not ink. When the page's chroma is known,
///    a pixel is also ink when its chroma is more than `inkChroma` above the page's median
///    chroma: a yellow highlighter line or a pale stamp is as light as paper but colored.
/// 4. Marks (8-connected, so a thin slanted pencil stroke stays one mark) smaller than
///    `minMarkPixels` are dust and dropped.
/// 5. The page is blank when the remaining ink covers less than `threshold` of the area.
/// The decision only flags a page: the app leaves flagged pages out at save time, and the user can
/// keep any of them (`PageFilter`). Twin of C# `BlankPageDetector`: same constants, same steps,
/// same arithmetic, so a page gives the same result on both platforms.
public enum BlankPageDetector {
    /// Edge band left out on normal pages, in inches.
    public static let marginInches = 0.3
    /// Punched holes sit between `marginInches` and this distance from the edge. Inside it, dark
    /// marks too solid to be writing (`holeRadiusInches`) are not ink.
    public static let holeBandInches = 0.7
    /// A mark counts as a punched hole when a square of this radius fits inside it, in inches.
    public static let holeRadiusInches = 0.04
    /// Pages with a shorter side than this (cards, receipts) use `smallPageMarginFraction`.
    public static let smallPageInches = 2.5
    /// Edge band of small pages, as a share of their short side.
    public static let smallPageMarginFraction = 0.15
    /// Side of a background tile, in inches (25 pixels at the analysis resolution).
    public static let tileInches = 0.25
    /// A tile's background is this percentile of its pixels.
    public static let backgroundPercentile = 0.9
    /// Tiles darker than the page's median tile by more than this (of 255) are a dark area, not paper.
    public static let darkAreaDrop = 64
    /// A page with more than this share of dark-area tiles is never blank.
    public static let darkTileFraction = 0.01
    /// A pixel is ink when darker than (1 − this) of the paper around it.
    public static let inkContrast = 0.30
    /// A pixel is also ink when its chroma (max − min of R, G, B) is more than this above the
    /// page's median chroma.
    public static let inkChroma = ColorAnalysis.chromaThreshold
    /// Marks smaller than this many pixels at the analysis resolution are dust.
    public static let minMarkPixels = 6

    /// The largest ink coverage a blank page may have: Low 0.008 %, Medium 0.024 %, High 0.08 %. A
    /// lone page number (about 0.01 %) is blank at Medium; one line of text or a signature (about
    /// 0.12 % and more) is never blank.
    public static func threshold(_ sensitivity: BlankSensitivity) -> Double {
        switch sensitivity {
        case .low: return 0.00008
        case .high: return 0.0008
        case .medium: return 0.00024
        }
    }

    /// Checks `image`, scanned at `dpi`, read as gray at the analysis resolution
    /// (`GrayImage(cgImage:sourceDPI:analysisDPI:)`). A page that cannot be read is not blank.
    public static func analyze(_ image: CGImage, dpi: Int, options: BlankPageOptions = BlankPageOptions()) -> BlankPageResult {
        guard let planes = GrayImage.lumaAndChroma(cgImage: image, sourceDPI: dpi) else {
            return BlankPageResult(inkCoverage: 0, inkComponents: 0, hasLargeDarkArea: false, isBlank: false)
        }
        return analyze(planes.luma, chroma: planes.chroma, options: options)
    }

    /// Checks `page`, scanned at `dpi`: converted to gray at the analysis resolution first
    /// (`GrayImage.from(_:sourceDPI:analysisDPI:)`), with its chroma at the same resolution
    /// (`GrayImage.chroma(_:sourceDPI:analysisDPI:)`).
    public static func analyze(_ page: RgbaImage, dpi: Int, options: BlankPageOptions = BlankPageOptions()) -> BlankPageResult {
        analyze(GrayImage.from(page, sourceDPI: dpi), chroma: GrayImage.chroma(page, sourceDPI: dpi), options: options)
    }

    /// Checks a gray page. Pixel sizes follow `GrayImage.dpi`, so a page at another resolution
    /// than `GrayImage.analysisDPI` gives about the same result. A page whose area inside the
    /// margins is smaller than one background tile is not blank: it is too small to tell. `chroma`
    /// is the page's chroma at the same size as `gray`; without it only brightness counts.
    public static func analyze(_ gray: GrayImage, chroma: GrayImage? = nil,
                               options: BlankPageOptions = BlankPageOptions()) -> BlankPageResult {
        let notBlank = BlankPageResult(inkCoverage: 0, inkComponents: 0, hasLargeDarkArea: false, isBlank: false)
        let dpi = gray.dpi > 0 ? gray.dpi : Double(GrayImage.analysisDPI)
        let k = dpi / Double(GrayImage.analysisDPI)

        // 1. Leave out the edges.
        let shortSide = min(gray.width, gray.height)
        let marginPixels = Double(shortSide) / dpi < smallPageInches
            ? smallPageMarginFraction * Double(shortSide)
            : max(0, options.marginInches) * dpi
        let margin = min(Int((marginPixels + 0.5).rounded(.down)), (shortSide - 1) / 2)
        let width = gray.width - 2 * margin, height = gray.height - 2 * margin
        let tileSize = max(4, Int((tileInches * dpi + 0.5).rounded(.down)))
        guard width >= tileSize, height >= tileSize,
              let raw = BackgroundMap.estimate(gray, x: margin, y: margin, width: width, height: height,
                                               tileSize: tileSize, percentile: backgroundPercentile) else {
            return notBlank
        }

        // 2. The paper's brightness, never lower than the median paper minus the dark-area drop.
        let floor = max(0, Int(raw.medianTile()) - darkAreaDrop)
        let darkTiles = raw.tiles.filter { Int($0) < floor }.count
        let hasLargeDarkArea = Double(darkTiles) > darkTileFraction * Double(raw.tiles.count)
        let background = raw.maxSmoothed().clampedBelow(UInt8(floor))

        // 3. Ink: clearly darker than the paper around it, or clearly more colored than the page.
        var ink = background.inkMask(gray, contrast: inkContrast)
        if Double(shortSide) / dpi >= smallPageInches, options.marginInches > 0 {
            let band = Int((holeBandInches * dpi + 0.5).rounded(.down)) - margin
            dropHoles(&ink, width: width, height: height, band: band, dpi: dpi)
        }
        if let chroma {
            addColor(&ink, chroma, x: margin, y: margin, width: width, height: height)
        }

        // 4. Drop dust; 5. measure what is left.
        let minMark = max(1, Int((Double(minMarkPixels) * k * k + 0.5).rounded(.down)))
        var inkPixels = 0
        var marks = 0
        for area in MaskOps.componentAreas(mask: ink, width: background.width, height: background.height,
                                           eightConnected: true) where area >= minMark {
            inkPixels += area
            marks += 1
        }
        let coverage = Double(inkPixels) / Double(background.width * background.height)
        let isBlank = !hasLargeDarkArea && coverage < threshold(options.sensitivity)
        return BlankPageResult(inkCoverage: coverage, inkComponents: marks,
                               hasLargeDarkArea: hasLargeDarkArea, isBlank: isBlank)
    }

    /// Clears the ink within `band` pixels of the edges of the looked-at area that belongs to a
    /// mark a square of `holeRadiusInches` fits in: a punched hole shows the scanner's backing,
    /// writing is thinner. A margin of 0 asks for everything to be looked at, so the caller skips
    /// this then.
    private static func dropHoles(_ ink: inout [UInt8], width: Int, height: Int, band: Int, dpi: Double) {
        let r = max(1, Int((holeRadiusInches * dpi + 0.5).rounded(.down)))
        var inBand = 0
        for y in 0..<height {
            let rowInBand = y < band || y >= height - band
            for x in 0..<width where ink[y * width + x] == 1 && (rowInBand || x < band || x >= width - band) {
                inBand += 1
            }
        }
        if inBand < (2 * r + 1) * (2 * r + 1) { return }
        let eroded = MaskOps.erode(ink, width, height, radius: r, outsideSet: true)
        let solid = MaskOps.dilate(eroded, width, height, radius: r)
        for y in 0..<height {
            let rowInBand = y < band || y >= height - band
            for x in 0..<width where solid[y * width + x] == 1 && (rowInBand || x < band || x >= width - band) {
                ink[y * width + x] = 0
            }
        }
    }

    /// Sets the ink where the chroma of the area at (`x`, `y`) is more than `inkChroma` above the
    /// area's median chroma, so paper that is itself tinted stays paper.
    private static func addColor(_ ink: inout [UInt8], _ chroma: GrayImage, x: Int, y: Int, width: Int, height: Int) {
        var histogram = [Int](repeating: 0, count: 256)
        for ay in 0..<height {
            let row = (y + ay) * chroma.width + x
            for ax in 0..<width { histogram[Int(chroma.pixels[row + ax])] += 1 }
        }
        var median = 0
        var seen = histogram[0]
        while seen * 2 < width * height {
            median += 1
            seen += histogram[median]
        }
        let limit = median + inkChroma
        for ay in 0..<height {
            let row = (y + ay) * chroma.width + x
            for ax in 0..<width where Int(chroma.pixels[row + ax]) > limit { ink[ay * width + ax] = 1 }
        }
    }
}
