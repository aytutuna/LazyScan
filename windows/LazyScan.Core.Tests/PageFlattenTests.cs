using LazyScan.Core;
using Xunit;

namespace LazyScan.Core.Tests;

// Twin of Tests/LazyScanTests/PageFlattenTests.swift: the same fixtures, and the bytes they give are pinned.

public class PageFlattenTests
{
    private const int Width = 600;
    private const int Height = 400;
    private static readonly byte[] Paper = [238, 234, 224];
    private static readonly double[] LineShares = [0.15, 0.3, 0.45, 0.6, 0.75, 0.9];

    /// <summary>0 at the ends of the page, 1 at its middle (the spine).</summary>
    private static double Bump(int x)
    {
        double u = (double)x / (Width - 1);
        return 4 * u * (1 - u);
    }

    /// <summary>
    /// A page on a dark table whose top and bottom edges dip <paramref name="bend"/> pixels towards each other
    /// at the spine, with a line of text at every share of the way between its edges.
    /// </summary>
    private static RgbaImage CurvedPage(double bend)
    {
        var pixels = new byte[Width * Height * 4];
        Array.Fill(pixels, (byte)255);
        for (int y = 0; y < Height; y++)
        {
            for (int x = 0; x < Width; x++)
            {
                double top = bend * Bump(x);
                double bottom = (Height - 1) - bend * Bump(x);
                byte[] color = [50, 45, 40];
                if (y >= top && y <= bottom)
                {
                    color = Paper;
                    foreach (double share in LineShares)
                    {
                        if (Math.Abs(y - (top + share * (bottom - top))) < 1.5) color = [30, 30, 30];
                    }
                }
                int i = (y * Width + x) * 4;
                pixels[i] = color[0];
                pixels[i + 1] = color[1];
                pixels[i + 2] = color[2];
            }
        }
        return new RgbaImage(Width, Height, pixels);
    }

    /// <summary>The row of the dark line near <paramref name="expected"/> in column x, to a tenth of a pixel; null when there is none.</summary>
    private static double? LineRow(RgbaImage image, int x, double expected)
    {
        double sum = 0, weight = 0;
        int from = Math.Max(0, (int)expected - 12), to = Math.Min(image.Height - 1, (int)expected + 12);
        for (int y = from; y <= to; y++)
        {
            double dark = 128 - image.Pixels[(y * image.Width + x) * 4];
            if (dark > 0)
            {
                sum += dark * y;
                weight += dark;
            }
        }
        return weight > 0 ? sum / weight : null;
    }

    private static uint Checksum(RgbaImage image)
    {
        uint hash = 0x811C9DC5;
        foreach (byte value in image.Pixels)
        {
            hash ^= value;
            hash *= 0x01000193;
        }
        return hash;
    }

    private static void Paint(RgbaImage page, byte[] color, Func<int, int, bool> inside)
    {
        for (int y = 0; y < page.Height; y++)
        {
            for (int x = 0; x < page.Width; x++)
            {
                if (!inside(x, y)) continue;
                int i = (y * page.Width + x) * 4;
                page.Pixels[i] = color[0];
                page.Pixels[i + 1] = color[1];
                page.Pixels[i + 2] = color[2];
            }
        }
    }

    private static int[] Pixel(RgbaImage image, int x, int y)
    {
        int i = (y * image.Width + x) * 4;
        return [image.Pixels[i], image.Pixels[i + 1], image.Pixels[i + 2]];
    }

    [Fact]
    public void Flatten_DrawsCurvedTextLinesStraight()
    {
        var page = CurvedPage(30);
        // The fixture is bent: the first line sits well off its straight place at the spine.
        double straight = 0.15 * (Height - 1);
        double bent = LineRow(page, Width / 2, straight + 20)!.Value;
        Assert.True(Math.Abs(bent - straight) > 0.01 * Height);

        var flat = PageFlatten.Flatten(page)!;
        Assert.Equal((Width, Height), (flat.Width, flat.Height));
        foreach (double share in LineShares)
        {
            double expected = share * (Height - 1);
            for (int x = 20; x < Width - 20; x += 10)
            {
                double row = LineRow(flat, x, expected) ?? double.NaN;
                Assert.True(Math.Abs(row - expected) <= 0.01 * Height, $"x {x}, line {share}: {row}");
            }
        }
        Assert.Equal(0x706484C5u, Checksum(flat));
    }

    [Fact]
    public void Flatten_LeavesAPageWithADarkBannerAlongItsTopAlone()
    {
        var page = CurvedPage(30);
        Paint(page, [50, 45, 40], (x, y) => y < 80 && x < Width / 2);
        Assert.Null(PageFlatten.Flatten(page));
    }

    [Fact]
    public void Flatten_IsRepeatable()
    {
        var page = CurvedPage(24);
        Assert.NotNull(PageFlatten.Flatten(page));
        Assert.Equal(PageFlatten.Flatten(page)!.Pixels, PageFlatten.Flatten(page)!.Pixels);
    }

    [Fact]
    public void Flatten_LeavesStraightAndEdgelessPagesAlone()
    {
        Assert.Null(PageFlatten.Flatten(CurvedPage(0)));
        Assert.Null(PageFlatten.Flatten(CurvedPage(1)));
        Assert.Null(PageFlatten.Flatten(RgbaImage.Filled(Width, Height, Paper[0], Paper[1], Paper[2])));
        Assert.Null(PageFlatten.Flatten(RgbaImage.Filled(Width, Height, 40, 40, 40)));
    }

    // MARK: Fingers

    private const double Dpi = 150;

    private static RgbaImage PaperPage()
    {
        var page = RgbaImage.Filled(900, 600, Paper[0], Paper[1], Paper[2]);
        Paint(page, [40, 40, 40], (x, y) => y >= 150 && y < 450 && (y - 150) % 30 < 3 && x >= 250 && x < 650);
        return page;
    }

    [Fact]
    public void FillFingers_PaintsAThumbAtTheMarginWithPaper()
    {
        var page = PaperPage();
        Paint(page, [214, 160, 130], (x, y) =>
        {
            double dx = x / 90.0, dy = (y - 300) / 70.0;
            return dx * dx + dy * dy <= 1;
        });
        Assert.Equal([214, 160, 130], Pixel(page, 20, 300));
        var filled = PageFlatten.FillFingers(page, Dpi)!;
        foreach (var (x, y) in new[] { (0, 300), (20, 300), (60, 280), (85, 300), (40, 340) })
        {
            var p = Pixel(filled, x, y);
            for (int c = 0; c < 3; c++) Assert.True(Math.Abs(p[c] - Paper[c]) <= 4, $"{x}, {y}");
        }
        // The text and the rest of the page are as they were.
        Assert.Equal([40, 40, 40], Pixel(filled, 300, 151));
        Assert.Equal(Pixel(page, 800, 100), Pixel(filled, 800, 100));
        Assert.Equal(Pixel(page, 450, 20), Pixel(filled, 450, 20));
        Assert.Equal(0x324D5BC5u, Checksum(filled));
    }

    [Fact]
    public void FillFingers_LeavesPicturesThatRunPastTheBandAndPlainPagesAlone()
    {
        Assert.Null(PageFlatten.FillFingers(PaperPage(), Dpi));
        var page = PaperPage();
        Paint(page, [214, 160, 130], (x, y) => x < 220 && y >= 100 && y < 220);
        Assert.Null(PageFlatten.FillFingers(page, Dpi));
        // A patch that does not touch the border is no finger.
        var island = PaperPage();
        Paint(island, [214, 160, 130], (x, y) => x >= 30 && x < 90 && y >= 270 && y < 330);
        Assert.Null(PageFlatten.FillFingers(island, Dpi));
    }

    [Fact]
    public void FillFingers_IgnoresPaperThatIsWarmAllOver()
    {
        var page = RgbaImage.Filled(900, 600, 225, 205, 160);
        Paint(page, [40, 40, 40], (x, y) => x >= 300 && x < 600 && y >= 200 && y < 203);
        Assert.Null(PageFlatten.FillFingers(page, Dpi));
    }

    // MARK: The book task's steps

    [Fact]
    public void FlattenStep_DrawsACameraPageFlatOnce_AndKeepsThePhoto()
    {
        var photo = CurvedPage(30);
        var corners = new[] { new PointD(0, 0), new PointD(Width - 1, 0), new PointD(Width - 1, Height - 1), new PointD(0, Height - 1) };
        var page = new ScannedPage(photo, CaptureScale.NominalDpi, ColorMode.Color) { Source = PageSource.Photo }
            .WithCapture(new CaptureFacts(Quad.FromCorners(corners), Width, Height));
        var step = new FlattenStep();
        Assert.Equal("flatten", step.Name);
        var cut = new PerspectiveStep().Apply(page);
        var flat = step.Apply(cut);
        Assert.True(flat.Capture!.Flattened);
        Assert.Same(photo, flat.Alternate!.Image);
        Assert.Equal(PageFlatten.Flatten(cut.Image)!.Pixels, flat.Image.Pixels);
        // Not for a page cleaned up already, nor for one that was not cut out of a photo.
        var cleaned = new EnhanceStep(null).Apply(cut);
        Assert.Same(cleaned, step.Apply(cleaned));
        var scanned = new ScannedPage(photo, 300, ColorMode.Color);
        Assert.Same(scanned, step.Apply(scanned));
        Assert.Same(scanned, new FingerFillStep().Apply(scanned));
        Assert.Equal("fingers", new FingerFillStep().Name);
    }

    [Fact]
    public void ForCapture_AddsTheFlatteningStepsOnlyWhenAskedFor()
    {
        var s = TaskCatalog.Apply(ScanTask.Book, new ScanSettings());
        Assert.Equal(["perspective", "enhance"], PageProcessor.ForCapture(s).Prepare.Select(step => step.Name));
        s.TaskOptions.BookFlattenCurves = true;
        Assert.True(PageProcessor.FlattensCurvedPages(s));
        Assert.Equal(["perspective", "flatten", "enhance"], PageProcessor.ForCapture(s).Prepare.Select(step => step.Name));
        s.TaskOptions.BookFillFingers = true;
        s.TaskOptions.CameraSpreads = true;
        Assert.Equal(["perspective", "flatten", "fingers", "enhance"], PageProcessor.ForCapture(s).Prepare.Select(step => step.Name));
        // Not for another task.
        var document = TaskCatalog.Apply(ScanTask.Document, new ScanSettings());
        document.TaskOptions.BookFlattenCurves = true;
        document.TaskOptions.BookFillFingers = true;
        Assert.False(PageProcessor.FlattensCurvedPages(document));
        Assert.False(PageProcessor.FillsFingers(document));
        Assert.Equal(["perspective", "enhance"], PageProcessor.ForCapture(document).Prepare.Select(step => step.Name));
    }
}
