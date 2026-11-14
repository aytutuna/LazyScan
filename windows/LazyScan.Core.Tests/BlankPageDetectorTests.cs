using LazyScan.Core;
using Xunit;

namespace LazyScan.Core.Tests;

// Twin of Tests/LazyScanTests/BlankPageDetectorTests.swift: same pages, same expectations.

public class BlankPageDetectorTests
{
    private static readonly BlankSensitivity[] Levels = [BlankSensitivity.Low, BlankSensitivity.Medium, BlankSensitivity.High];

    private static BlankPageResult Check(GrayImage page, BlankSensitivity sensitivity = BlankSensitivity.Medium) =>
        BlankPageDetector.Analyze(page, new BlankPageOptions { Sensitivity = sensitivity });

    [Fact]
    public void Fixtures_AreTheSameBytesOnBothPlatforms()
    {
        // FNV-1a of each page; TestPages.swift must produce the same numbers.
        Assert.Equal(
            [Expected.CleanBlank, Expected.NoisyBlank, Expected.ShowThrough, Expected.OneTextLine,
             Expected.Signature, Expected.PageNumber, Expected.Photo, Expected.TintedWithText],
            TestPages.All().Select(p => TestPages.Checksum(p.Page)));
    }

    [Fact]
    public void BlankPagesAsScannersDeliverThem_AreBlankAtEveryLevel()
    {
        foreach (var page in new[] { TestPages.CleanBlank(), TestPages.NoisyBlank(), TestPages.ShowThrough() })
        {
            foreach (var level in Levels)
            {
                var result = Check(page, level);
                Assert.True(result.IsBlank, $"{level}: coverage {result.InkCoverage}");
                Assert.False(result.HasLargeDarkArea);
            }
        }
    }

    [Fact]
    public void CleanPaper_HasNoInkAtAll()
    {
        var result = Check(TestPages.CleanBlank());
        Assert.Equal(0, result.InkCoverage);
        Assert.Equal(0, result.InkComponents);
    }

    [Fact]
    public void DustNoiseShadowsHolesAndShowThrough_AddNoInk()
    {
        // Specks are smaller than a mark, the shadow and holes are in the margin, show-through
        // and the gradient are lighter than ink.
        Assert.True(Check(TestPages.NoisyBlank()).InkCoverage < 0.00002);
        Assert.Equal(0, Check(TestPages.ShowThrough()).InkCoverage);
    }

    [Fact]
    public void PagesWithLittleOnThem_AreNeverBlank()
    {
        foreach (var page in new[] { TestPages.OneTextLine(), TestPages.Signature(), TestPages.Photo(), TestPages.TintedWithText() })
        {
            foreach (var level in Levels)
            {
                var result = Check(page, level);
                Assert.False(result.IsBlank, $"{level}: coverage {result.InkCoverage}");
            }
        }
    }

    [Fact]
    public void OneTextLineAndASignature_CoverMoreThanTheHighestThreshold()
    {
        Assert.InRange(Check(TestPages.OneTextLine()).InkCoverage, 0.0015, 0.004);
        Assert.InRange(Check(TestPages.Signature()).InkCoverage, 0.0015, 0.004);
        Assert.True(Check(TestPages.OneTextLine()).InkComponents > 50);
    }

    [Fact]
    public void ALonePageNumber_IsBlankAtMediumAndHigh_ButNotAtLow()
    {
        var page = TestPages.PageNumber();
        var medium = Check(page);
        Assert.True(medium.IsBlank);
        Assert.InRange(medium.InkCoverage, 0.00008, 0.00024);
        Assert.Equal(2, medium.InkComponents);
        Assert.False(Check(page, BlankSensitivity.Low).IsBlank);
        Assert.True(Check(page, BlankSensitivity.High).IsBlank);
    }

    [Fact]
    public void AThinSlantedPencilNote_IsOneMarkPerStroke_NotDust()
    {
        // Four zigzag lines one pixel wide at 55 % of the paper: each step is diagonal, so the
        // strokes only hold together 8-connected.
        var page = TestPages.Noisy(0x9E9C11, 245, p =>
        {
            for (int line = 0; line < 4; line++)
            {
                for (int x = 0; x < 250; x++)
                {
                    int y = 300 + line * 30 + (x / 6 % 2 == 0 ? x % 6 : 6 - x % 6);
                    p[y * TestPages.Width + 200 + x] = 245 * 55 / 100;
                }
            }
        });
        foreach (var level in Levels)
        {
            var result = Check(page, level);
            Assert.False(result.IsBlank, $"{level}: coverage {result.InkCoverage}");
            Assert.Equal(4, result.InkComponents);
        }
    }

    [Fact]
    public void APhoto_IsALargeDarkArea()
    {
        var result = Check(TestPages.Photo(), BlankSensitivity.High);
        Assert.True(result.HasLargeDarkArea);
        Assert.False(result.IsBlank);
        Assert.False(result.IsBlankAt(BlankSensitivity.High));
    }

    [Fact]
    public void TintedPaper_IsPaper_AndItsTextIsInk()
    {
        var result = Check(TestPages.TintedWithText());
        Assert.False(result.HasLargeDarkArea);
        Assert.True(result.InkCoverage > 0.005);
        // Tinted paper alone is blank.
        Assert.True(Check(TestPages.Noisy(0x8181818A, 217, _ => { })).IsBlank);
    }

    [Fact]
    public void IsBlankAt_AgreesWithTheThresholds()
    {
        Assert.True(BlankPageDetector.Threshold(BlankSensitivity.Low) < BlankPageDetector.Threshold(BlankSensitivity.Medium));
        Assert.True(BlankPageDetector.Threshold(BlankSensitivity.Medium) < BlankPageDetector.Threshold(BlankSensitivity.High));
        Assert.Equal(0.00008, BlankPageDetector.Threshold(BlankSensitivity.Low));
        Assert.Equal(0.00024, BlankPageDetector.Threshold(BlankSensitivity.Medium));
        Assert.Equal(0.0008, BlankPageDetector.Threshold(BlankSensitivity.High));
        foreach (var (_, page) in TestPages.All())
        {
            foreach (var level in Levels)
            {
                var result = Check(page, level);
                Assert.Equal(result.IsBlank, result.IsBlankAt(level));
            }
        }
    }

    private static RgbaImage Colored(GrayImage page, int x, int y, int w, int h, byte r, byte g, byte b)
    {
        var scan = TestPages.Enlarged(page, 1);
        for (int py = y; py < y + h; py++)
        {
            for (int px = x; px < x + w; px++)
            {
                int i = (py * scan.Width + px) * 4;
                scan.Pixels[i] = r;
                scan.Pixels[i + 1] = g;
                scan.Pixels[i + 2] = b;
            }
        }
        return scan;
    }

    [Fact]
    public void AYellowHighlighterLine_IsInk_ThoughAsLightAsPaper()
    {
        var scan = Colored(TestPages.NoisyBlank(), 200, 500, 450, 15, 255, 245, 100);
        foreach (var level in Levels)
        {
            var result = BlankPageDetector.Analyze(scan, 100, new BlankPageOptions { Sensitivity = level });
            Assert.False(result.IsBlank, $"{level}: coverage {result.InkCoverage}");
        }
        Assert.True(Check(GrayImage.From(scan, 100)).IsBlank);
    }

    [Fact]
    public void APalePrintedStamp_IsInk_ThoughAsLightAsPaper()
    {
        var scan = Colored(TestPages.CleanBlank(), 300, 600, 150, 60, 200, 215, 245);
        foreach (var level in Levels)
        {
            var result = BlankPageDetector.Analyze(scan, 100, new BlankPageOptions { Sensitivity = level });
            Assert.False(result.IsBlank, $"{level}: coverage {result.InkCoverage}");
        }
        Assert.True(Check(GrayImage.From(scan, 100)).IsBlank);
    }

    [Fact]
    public void PaperThatIsColoredAllOver_IsStillPaper()
    {
        var scan = Colored(TestPages.NoisyBlank(), 0, 0, TestPages.Width, TestPages.Height, 250, 245, 150);
        Assert.True(BlankPageDetector.Analyze(scan, 100).IsBlank);
    }

    [Fact]
    public void ANoteAlongTheBottomEdge_040InchesIn_IsNotBlank()
    {
        var page = TestPages.Noisy(0x0B07E5E5, 245, p => TestPages.TextLine(p, 100, 1050, 650, 50, new TestPages.Rng(0x7E7E0004)));
        foreach (var level in Levels)
        {
            var result = Check(page, level);
            Assert.False(result.IsBlank, $"{level}: coverage {result.InkCoverage}");
        }
    }

    [Fact]
    public void TheMargin_KeepsEdgeShadowsAndHolesOut()
    {
        var noMargin = BlankPageDetector.Analyze(TestPages.NoisyBlank(), new BlankPageOptions { MarginInches = 0 });
        Assert.False(noMargin.IsBlank);
        Assert.True(noMargin.InkCoverage > 0.01);
    }

    [Fact]
    public void AHigherResolutionScan_GivesTheSameResult()
    {
        foreach (var (name, page) in new[] { ("blank", TestPages.NoisyBlank()), ("number", TestPages.PageNumber()), ("line", TestPages.OneTextLine()) })
        {
            var scan = TestPages.Enlarged(page, 3);
            var gray = GrayImage.From(scan, 300);
            Assert.Equal((100.0, page.Width, page.Height), (gray.Dpi, gray.Width, gray.Height));
            Assert.Equal(page.Pixels, gray.Pixels);
            Assert.Equal(Check(page), BlankPageDetector.Analyze(scan, 300));
            Assert.True(name.Length > 0);
        }
    }

    [Fact]
    public void ALowResolutionScan_IsAnalyzedAtItsOwnResolution()
    {
        // 50 dpi: half the pixels; marks and tiles scale with it.
        var blank = GrayImage.Filled(425, 550, 240, dpi: 50);
        Assert.True(BlankPageDetector.Analyze(blank).IsBlank);
        var text = TestPages.OneTextLine().Downsampled(425, 550);
        Assert.Equal(50, text.Dpi);
        Assert.False(BlankPageDetector.Analyze(text).IsBlank);
    }

    [Fact]
    public void ASmallCard_UsesAShareOfItsShortSideAsMargin()
    {
        // A 3.5 × 2 in card: the edge band and hole band of a full page would leave almost nothing.
        var card = GrayImage.Filled(350, 200, 245);
        Assert.True(BlankPageDetector.Analyze(card).IsBlank);
        var pixels = (byte[])card.Pixels.Clone();
        for (int x = 60; x < 290; x++)
        {
            for (int y = 95; y < 105; y++) pixels[y * 350 + x] = (byte)((x / 4) % 2 == 0 ? 40 : 245);
        }
        Assert.False(BlankPageDetector.Analyze(new GrayImage(350, 200, pixels)).IsBlank);
    }

    [Fact]
    public void ATinyImage_IsNotBlank()
    {
        var result = BlankPageDetector.Analyze(GrayImage.Filled(3, 3, 255));
        Assert.False(result.IsBlank);
        Assert.False(BlankPageDetector.Analyze(GrayImage.Filled(1, 1, 255)).IsBlank);
    }

    [Fact]
    public void ADarkBandAcrossThePage_IsNeverBlank()
    {
        // A scanner's black backing showing past a short sheet.
        var page = TestPages.Noisy(0xBADBAD, 245, p => TestPages.Fill(p, 0, 900, TestPages.Width, 200, 20));
        var result = Check(page, BlankSensitivity.High);
        Assert.True(result.HasLargeDarkArea);
        Assert.False(result.IsBlank);
    }

    /// <summary>The FNV-1a checksums of the TestPages fixtures.</summary>
    internal static class Expected
    {
        public const uint CleanBlank = 0xB28D863D;
        public const uint NoisyBlank = 0xC7901B30;
        public const uint ShowThrough = 0x41EC9527;
        public const uint OneTextLine = 0x7F42A318;
        public const uint Signature = 0xD7C4DB8C;
        public const uint PageNumber = 0xC37B1A14;
        public const uint Photo = 0x0E42C008;
        public const uint TintedWithText = 0xC739A64F;
    }
}
