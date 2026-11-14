namespace LazyScan.Core;

// Twin of Sources/LazyScanKit/Pipeline/BlankPageDetector.swift: same constants, same
// steps, same arithmetic, so a page gives the same result on both platforms.

/// <summary>What <see cref="BlankPageDetector.Analyze"/> looks for.</summary>
public sealed record BlankPageOptions
{
    /// <summary>How much may be on the page for it to count as blank.</summary>
    public BlankSensitivity Sensitivity { get; init; } = BlankSensitivity.Medium;

    /// <summary>
    /// The band along every edge that is not looked at: edge shadows and staples live there.
    /// Punched holes reach past it and are dealt with by <see cref="BlankPageDetector.HoleBandInches"/>.
    /// Pages whose short side is under <see cref="BlankPageDetector.SmallPageInches"/>
    /// use <see cref="BlankPageDetector.SmallPageMarginFraction"/> of it instead.
    /// </summary>
    public double MarginInches { get; init; } = BlankPageDetector.MarginInches;
}

/// <summary>What the blank-page check found on a page.</summary>
/// <param name="InkCoverage">Share of the area looked at covered by marks larger than dust (0...1).</param>
/// <param name="InkComponents">Marks larger than dust.</param>
/// <param name="HasLargeDarkArea">
/// A photo, a dark block or a dark band covers part of the page: such a page is never blank.
/// </param>
/// <param name="IsBlank">The page counts as blank at the sensitivity it was checked with.</param>
public sealed record BlankPageResult(double InkCoverage, int InkComponents, bool HasLargeDarkArea, bool IsBlank)
{
    /// <summary>Whether the page counts as blank at <paramref name="sensitivity"/>.</summary>
    public bool IsBlankAt(BlankSensitivity sensitivity) =>
        !HasLargeDarkArea && InkCoverage < BlankPageDetector.Threshold(sensitivity);
}

/// <summary>
/// Tells blank pages (the empty back of a one-sided sheet in a two-sided scan, a separator
/// left in the stack) from pages with something on them, robust to what scanners add to an
/// empty page: noise, dust, tinted or uneven paper, edge shadows, punched holes and the other
/// side showing through. All at <see cref="GrayImage.AnalysisDpi"/>:
/// <list type="number">
/// <item>The edges are left out (<see cref="BlankPageOptions.MarginInches"/>).</item>
/// <item>The paper's brightness is mapped in tiles (<see cref="BackgroundMap"/>, 90th percentile),
/// each tile raised to the brightest of its neighbors, and to no less than the page's median
/// minus <see cref="DarkAreaDrop"/>, so a photo or a dark block is never taken for paper. When
/// more than <see cref="DarkTileFraction"/> of the tiles are that dark, the page has a large dark
/// area and is never blank.</item>
/// <item>A pixel is ink when it is darker than (1 − <see cref="InkContrast"/>) of the paper there:
/// print and pencil are, show-through and paper texture are not. Solid dark marks within
/// <see cref="HoleBandInches"/> of the edge are punched holes, not ink. When the page's chroma
/// is known, a pixel is also ink when its chroma is more than <see cref="InkChroma"/> above the
/// page's median chroma: a yellow highlighter line or a pale stamp is as light as paper but
/// colored.</item>
/// <item>Marks (8-connected, so a thin slanted pencil stroke stays one mark) smaller than
/// <see cref="MinMarkPixels"/> are dust and dropped.</item>
/// <item>The page is blank when the remaining ink covers less than <see cref="Threshold"/> of
/// the area.</item>
/// </list>
/// The decision only flags a page: the app leaves flagged pages out at save time, and the user
/// can keep any of them (<see cref="PageFilter"/>).
/// </summary>
public static class BlankPageDetector
{
    /// <summary>Edge band left out on normal pages, in inches.</summary>
    public const double MarginInches = 0.3;
    /// <summary>
    /// Punched holes sit between <see cref="MarginInches"/> and this distance from the edge. Inside
    /// it, dark marks too solid to be writing (<see cref="HoleRadiusInches"/>) are not ink.
    /// </summary>
    public const double HoleBandInches = 0.7;
    /// <summary>A mark counts as a punched hole when a square of this radius fits inside it, in inches.</summary>
    public const double HoleRadiusInches = 0.04;
    /// <summary>Pages with a shorter side than this (cards, receipts) use <see cref="SmallPageMarginFraction"/>.</summary>
    public const double SmallPageInches = 2.5;
    /// <summary>Edge band of small pages, as a share of their short side.</summary>
    public const double SmallPageMarginFraction = 0.15;
    /// <summary>Side of a background tile, in inches (25 pixels at the analysis resolution).</summary>
    public const double TileInches = 0.25;
    /// <summary>A tile's background is this percentile of its pixels.</summary>
    public const double BackgroundPercentile = 0.9;
    /// <summary>Tiles darker than the page's median tile by more than this (of 255) are a dark area, not paper.</summary>
    public const int DarkAreaDrop = 64;
    /// <summary>A page with more than this share of dark-area tiles is never blank.</summary>
    public const double DarkTileFraction = 0.01;
    /// <summary>A pixel is ink when darker than (1 − this) of the paper around it.</summary>
    public const double InkContrast = 0.30;
    /// <summary>
    /// A pixel is also ink when its chroma (max − min of R, G, B) is more than this above the
    /// page's median chroma.
    /// </summary>
    public const int InkChroma = ColorAnalysis.ChromaThreshold;
    /// <summary>Marks smaller than this many pixels at the analysis resolution are dust.</summary>
    public const int MinMarkPixels = 6;

    /// <summary>
    /// The largest ink coverage a blank page may have: Low 0.008 %, Medium 0.024 %, High 0.08 %. A
    /// lone page number (about 0.01 %) is blank at Medium; one line of text or a signature (about
    /// 0.12 % and more) is never blank.
    /// </summary>
    public static double Threshold(BlankSensitivity sensitivity) => sensitivity switch
    {
        BlankSensitivity.Low => 0.00008,
        BlankSensitivity.High => 0.0008,
        _ => 0.00024,
    };

    /// <summary>
    /// Checks <paramref name="page"/>, scanned at <paramref name="dpi"/>: converted to gray at the
    /// analysis resolution first (<see cref="GrayImage.From(RgbaImage, int, int)"/>), with its chroma
    /// at the same resolution (<see cref="GrayImage.Chroma(RgbaImage, int, int)"/>).
    /// </summary>
    public static BlankPageResult Analyze(RgbaImage page, int dpi, BlankPageOptions? options = null) =>
        Analyze(GrayImage.From(page, dpi), GrayImage.Chroma(page, dpi), options);

    /// <summary>
    /// Checks a gray page. Pixel sizes follow <see cref="GrayImage.Dpi"/>, so a page at another
    /// resolution than <see cref="GrayImage.AnalysisDpi"/> gives about the same result. A page whose
    /// area inside the margins is smaller than one background tile is not blank: it is too small to
    /// tell.
    /// </summary>
    public static BlankPageResult Analyze(GrayImage gray, BlankPageOptions? options = null) =>
        Analyze(gray, null, options);

    /// <summary>
    /// <see cref="Analyze(GrayImage, BlankPageOptions?)"/> with the page's chroma at the same size as
    /// <paramref name="gray"/>; without it (null) only brightness counts.
    /// </summary>
    public static BlankPageResult Analyze(GrayImage gray, GrayImage? chroma, BlankPageOptions? options = null)
    {
        options ??= new BlankPageOptions();
        double dpi = gray.Dpi > 0 ? gray.Dpi : GrayImage.AnalysisDpi;
        double k = dpi / GrayImage.AnalysisDpi;

        // 1. Leave out the edges.
        int shortSide = Math.Min(gray.Width, gray.Height);
        double marginPixels = shortSide / dpi < SmallPageInches
            ? SmallPageMarginFraction * shortSide
            : Math.Max(0, options.MarginInches) * dpi;
        int margin = Math.Min((int)Math.Floor(marginPixels + 0.5), (shortSide - 1) / 2);
        int width = gray.Width - 2 * margin, height = gray.Height - 2 * margin;
        int tileSize = Math.Max(4, (int)Math.Floor(TileInches * dpi + 0.5));
        if (width < tileSize || height < tileSize) return new BlankPageResult(0, 0, false, false);
        var raw = BackgroundMap.Estimate(gray, margin, margin, width, height, tileSize, BackgroundPercentile);
        if (raw is null) return new BlankPageResult(0, 0, false, false);

        // 2. The paper's brightness, never lower than the median paper minus the dark-area drop.
        int floor = Math.Max(0, raw.MedianTile() - DarkAreaDrop);
        int darkTiles = 0;
        foreach (byte tile in raw.Tiles) if (tile < floor) darkTiles++;
        bool hasLargeDarkArea = darkTiles > DarkTileFraction * raw.Tiles.Length;
        var background = raw.MaxSmoothed().ClampedBelow((byte)floor);

        // 3. Ink: clearly darker than the paper around it, or clearly more colored than the page.
        var ink = background.InkMask(gray, InkContrast);
        if (shortSide / dpi >= SmallPageInches && options.MarginInches > 0)
        {
            int band = (int)Math.Floor(HoleBandInches * dpi + 0.5) - margin;
            DropHoles(ink, width, height, band, dpi);
        }
        if (chroma is not null) AddColor(ink, chroma, margin, margin, width, height);

        // 4. Drop dust; 5. measure what is left.
        int minMark = Math.Max(1, (int)Math.Floor(MinMarkPixels * k * k + 0.5));
        long inkPixels = 0;
        int marks = 0;
        foreach (int area in MaskOps.ComponentAreas(ink, background.Width, background.Height, eightConnected: true))
        {
            if (area < minMark) continue;
            inkPixels += area;
            marks++;
        }
        double coverage = (double)inkPixels / ((long)background.Width * background.Height);
        bool isBlank = !hasLargeDarkArea && coverage < Threshold(options.Sensitivity);
        return new BlankPageResult(coverage, marks, hasLargeDarkArea, isBlank);
    }

    // Clears the ink within `band` pixels of the edges of the looked-at area that belongs to a
    // mark a square of HoleRadiusInches fits in: a punched hole shows the scanner's backing,
    // writing is thinner. A margin of 0 asks for everything to be looked at, so the caller skips
    // this then.
    private static void DropHoles(byte[] ink, int width, int height, int band, double dpi)
    {
        int r = Math.Max(1, (int)Math.Floor(HoleRadiusInches * dpi + 0.5));
        int inBand = 0;
        for (int y = 0; y < height; y++)
        {
            bool rowInBand = y < band || y >= height - band;
            for (int x = 0; x < width; x++)
            {
                if (ink[y * width + x] == 1 && (rowInBand || x < band || x >= width - band)) inBand++;
            }
        }
        if (inBand < (2 * r + 1) * (2 * r + 1)) return;
        var solid = MaskOps.Dilate(MaskOps.Erode(ink, width, height, r, outsideSet: true), width, height, r);
        for (int y = 0; y < height; y++)
        {
            bool rowInBand = y < band || y >= height - band;
            for (int x = 0; x < width; x++)
            {
                if (solid[y * width + x] == 1 && (rowInBand || x < band || x >= width - band)) ink[y * width + x] = 0;
            }
        }
    }

    // Sets the ink where the chroma of the area at (x, y) is more than InkChroma above the area's
    // median chroma, so paper that is itself tinted stays paper.
    private static void AddColor(byte[] ink, GrayImage chroma, int x, int y, int width, int height)
    {
        var histogram = new int[256];
        for (int ay = 0; ay < height; ay++)
        {
            int row = (y + ay) * chroma.Width + x;
            for (int ax = 0; ax < width; ax++) histogram[chroma.Pixels[row + ax]]++;
        }
        int median = 0;
        int seen = histogram[0];
        while (seen * 2 < width * height)
        {
            median++;
            seen += histogram[median];
        }
        int limit = median + InkChroma;
        for (int ay = 0; ay < height; ay++)
        {
            int row = (y + ay) * chroma.Width + x;
            for (int ax = 0; ax < width; ax++)
            {
                if (chroma.Pixels[row + ax] > limit) ink[ay * width + ax] = 1;
            }
        }
    }
}
