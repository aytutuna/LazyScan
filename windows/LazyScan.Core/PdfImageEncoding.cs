namespace LazyScan.Core;

// Twin of Sources/LazyScanKit/Output/PDFImageEncoding.swift: the same table, the same
// rules and the same rounding. Windows encodes the planned JPEG with WIC
// (WpfImageCodec.EncodeJpeg), or black & white pages as CCITT G4 (PdfCcittImage), and embeds
// them through PdfBuilder; macOS encodes the JPEG with ImageIO and embeds it, like black & white
// pages as G4, through its port of this writer (PDFWriter).

/// <summary>How a page image is stored in the PDF.</summary>
public enum PdfImageKind
{
    /// <summary>A three-component (RGB) JPEG.</summary>
    JpegColor,
    /// <summary>A one-component JPEG, embedded as /DeviceGray.</summary>
    JpegGray,
    /// <summary>A 1-bit black &amp; white image in CCITT G4, embedded as /DeviceGray with /CCITTFaxDecode.</summary>
    BilevelG4,
}

/// <summary>What one PDF size does.</summary>
/// <param name="MaxDpi">Pages scanned finer than this (with <see cref="PdfImageEncoding.DownsampleSlack"/>) are downsampled to it; null keeps the scan resolution.</param>
/// <param name="ColorQuality">JPEG quality for color pages.</param>
/// <param name="GrayQuality">JPEG quality for gray and black &amp; white pages.</param>
/// <param name="AutoGray">Pages scanned in color that have no color are stored as gray.</param>
/// <param name="BilevelMaxDpi">
/// The limit for black &amp; white pages, stored as CCITT G4 (with the same slack); null keeps
/// the scan resolution. 1-bit pages need more pixels than gray ones to keep text smooth, and
/// cost far fewer bytes per pixel.
/// </param>
/// <param name="TextMask">
/// Color pages are stored as a text mask over a low-resolution background
/// (<see cref="PdfImageEncoding.SplitPage"/>), the mask at the black &amp; white limit.
/// </param>
public sealed record PdfSizeProfile(int? MaxDpi, double ColorQuality, double GrayQuality, bool AutoGray,
                                    int? BilevelMaxDpi = null, bool TextMask = false);

/// <summary>How to store one page image.</summary>
/// <param name="TargetDpi">The resolution of the stored image (the page's own when it is not downsampled).</param>
/// <param name="Kind">Color or gray JPEG, or black &amp; white G4.</param>
/// <param name="Quality">
/// JPEG quality, 0...1. For a G4 page, which is lossless, the size's gray quality: what a
/// writer without G4 would use for the page as a gray JPEG.
/// </param>
public sealed record PdfImagePlan(int TargetDpi, PdfImageKind Kind, double Quality)
{
    /// <summary>The stored image has one gray component: a gray JPEG or a G4 page.</summary>
    public bool IsGray => Kind != PdfImageKind.JpegColor;

    /// <summary>The page is stored black &amp; white, as CCITT G4.</summary>
    public bool IsBilevel => Kind == PdfImageKind.BilevelG4;
}

public static class PdfSizePresets
{
    /// <summary>The sizes as the inspector lists them: largest file first.</summary>
    public static IReadOnlyList<PdfSizePreset> DisplayOrder { get; } =
        [PdfSizePreset.Best, PdfSizePreset.Standard, PdfSizePreset.Compact, PdfSizePreset.Smallest];
}

/// <summary>
/// The size presets of saved PDFs and the per-page plan they lead to: downsampling, gray
/// storage and JPEG quality. The page size in the PDF never changes; only the stored image
/// gets fewer pixels. Black &amp; white pages are stored as CCITT G4 at every size.
/// </summary>
public static class PdfImageEncoding
{
    /// <summary>A page is downsampled only when it is finer than this many times the size's limit.</summary>
    public const double DownsampleSlack = 1.1;

    /// <summary>
    /// The size table. The size alone sets the JPEG quality of PDF pages; the JPEG quality
    /// setting is for JPEG files. Best stores what Windows PDFs held before sizes existed:
    /// the scan resolution at quality 0.9. Black &amp; white pages keep up to 600 dpi at Standard
    /// and 300 dpi at Compact and Smallest.
    /// </summary>
    public static PdfSizeProfile Profile(PdfSizePreset size) => size switch
    {
        PdfSizePreset.Best => new PdfSizeProfile(null, 0.90, 0.90, false, null),
        PdfSizePreset.Compact => new PdfSizeProfile(200, 0.65, 0.70, true, 300, true),
        PdfSizePreset.Smallest => new PdfSizeProfile(150, 0.50, 0.55, true, 300, true),
        _ => new PdfSizeProfile(300, 0.80, 0.80, true, 600), // Standard
    };

    /// <summary>
    /// How to store a page. <paramref name="imageDpi"/> is the resolution of the pixels at hand
    /// (see <see cref="EffectiveDpi"/>); <paramref name="mode"/> is the page's own color mode;
    /// <paramref name="looksGray"/> says whether a color page has no color
    /// (<see cref="ColorAnalysis.IsEffectivelyGray(RgbaImage)"/>), and only counts for sizes
    /// with <see cref="PdfSizeProfile.AutoGray"/>. Black &amp; white pages are G4 up to the size's
    /// <see cref="PdfSizeProfile.BilevelMaxDpi"/>.
    /// </summary>
    public static PdfImagePlan Plan(ColorMode mode, int imageDpi, PdfSizePreset size, bool looksGray)
    {
        var profile = Profile(size);
        int dpi = Math.Max(imageDpi, 1);
        if (mode == ColorMode.BlackWhite)
        {
            int bilevel = profile.BilevelMaxDpi is int limit && dpi > DownsampleSlack * limit ? limit : dpi;
            return new PdfImagePlan(bilevel, PdfImageKind.BilevelG4, profile.GrayQuality);
        }
        int target = profile.MaxDpi is int max && dpi > DownsampleSlack * max ? max : dpi;
        bool gray = mode != ColorMode.Color || (profile.AutoGray && looksGray);
        double quality = gray ? profile.GrayQuality : profile.ColorQuality;
        return new PdfImagePlan(target, gray ? PdfImageKind.JpegGray : PdfImageKind.JpegColor, quality);
    }

    /// <summary>
    /// <see cref="Plan(ColorMode, int, PdfSizePreset, bool)"/> for a page image; the
    /// color check runs only for color pages with a size that stores gray pages as gray.
    /// </summary>
    public static PdfImagePlan Plan(ColorMode mode, int imageDpi, PdfSizePreset size, RgbaImage image)
    {
        bool looksGray = mode == ColorMode.Color && Profile(size).AutoGray && ColorAnalysis.IsEffectivelyGray(image);
        return Plan(mode, imageDpi, size, looksGray);
    }

    /// <summary>
    /// A mask denser than this (G4 bytes against the 1-bit page's size) means the page is not text, and
    /// is stored as a plain page.
    /// </summary>
    public const double MaxMaskShare = 0.1;

    /// <summary>
    /// A color page of a size with <see cref="PdfSizeProfile.TextMask"/> cut into a text mask at the
    /// black &amp; white limit and a background at <see cref="TextSplit.BackgroundDpi"/>; the mask as G4
    /// data. Null for any other page, or when the mask is too dense to be text
    /// (<see cref="MaxMaskShare"/>) or its ink is colored. <paramref name="image"/> is at <paramref name="imageDpi"/>.
    /// </summary>
    public static (TextSplit Split, byte[] G4)? SplitPage(RgbaImage image, int imageDpi, ColorMode mode, PdfSizePreset size)
    {
        if (mode != ColorMode.Color || !Profile(size).TextMask) return null;
        var maskPlan = Plan(ColorMode.BlackWhite, imageDpi, size, false);
        var page = Downsample(image, imageDpi, maskPlan);
        var split = TextSplit.Split(page, maskPlan.TargetDpi);
        if (HasColoredInk(split, page)) return null;
        byte[] g4 = CcittG4Encoder.Encode(split.Mask, split.Width, split.Height);
        return g4.Length <= MaxMaskShare * split.Mask.Length ? (split, g4) : null;
    }

    /// <summary>
    /// True when more than <see cref="ColorAnalysis.MaxColoredFraction"/> of the ink pixels are colored
    /// (chroma above <see cref="ColorAnalysis.ChromaThreshold"/>): the mask paints in black, so such a
    /// page stays a plain page.
    /// </summary>
    private static bool HasColoredInk(TextSplit split, RgbaImage page)
    {
        long ink = 0, colored = 0;
        for (int y = 0; y < split.Height; y++)
        {
            for (int x = 0; x < split.Width; x++)
            {
                if (!Bilevel.IsBlack(split.Mask, split.Width, x, y)) continue;
                int i = (y * split.Width + x) * 4;
                int r = page.Pixels[i], g = page.Pixels[i + 1], b = page.Pixels[i + 2];
                ink++;
                if (Math.Max(r, Math.Max(g, b)) - Math.Min(r, Math.Min(g, b)) > ColorAnalysis.ChromaThreshold) colored++;
            }
        }
        return colored > ColorAnalysis.MaxColoredFraction * ink;
    }

    /// <summary>
    /// The resolution of the pixels at hand: the page's own, or less when only a preview of
    /// the page is left (its spool file is missing).
    /// </summary>
    public static int EffectiveDpi(int imageWidth, int pagePixelWidth, int pageDpi)
    {
        if (pagePixelWidth <= 0 || imageWidth == pagePixelWidth) return pageDpi;
        return Math.Max(1, (int)Math.Round((double)pageDpi * imageWidth / pagePixelWidth, MidpointRounding.AwayFromZero));
    }

    /// <summary>The pixel size of an image of <paramref name="width"/> × <paramref name="height"/> at <paramref name="imageDpi"/> stored at <paramref name="targetDpi"/>.</summary>
    public static (int Width, int Height) TargetSize(int width, int height, int imageDpi, int targetDpi)
    {
        if (targetDpi >= imageDpi || imageDpi <= 0) return (width, height);
        double scale = (double)targetDpi / imageDpi;
        return (Math.Max(1, (int)Math.Round(width * scale, MidpointRounding.AwayFromZero)),
                Math.Max(1, (int)Math.Round(height * scale, MidpointRounding.AwayFromZero)));
    }

    /// <summary>
    /// The image at the plan's resolution (box filter, <see cref="RgbaImage.Resized"/>); the
    /// image itself when the plan keeps its resolution. A black &amp; white page comes back gray
    /// where it was averaged; <see cref="Bilevel.Pack(RgbaImage)"/> thresholds it again.
    /// </summary>
    public static RgbaImage Downsample(RgbaImage image, int imageDpi, PdfImagePlan plan)
    {
        var (width, height) = TargetSize(image.Width, image.Height, imageDpi, plan.TargetDpi);
        return width == image.Width && height == image.Height ? image : image.Resized(width, height);
    }
}
