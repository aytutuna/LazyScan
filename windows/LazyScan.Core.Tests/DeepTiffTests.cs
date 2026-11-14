using LazyScan.Core;
using Xunit;

namespace LazyScan.Core.Tests;

// 16-bit TIFF files and the pages that carry deep pixels. The Mac's twin is Tests/LazyScanTests/DeepTIFFTests.swift
// with the same golden files (see CONTRACTS.md, "16-bit TIFF"); WIC reads the files back in
// LazyScan.App.Tests/DeepTiffOutputTests.cs.
public class DeepTiffTests
{
    private const string GrayGolden =
        "49492a0010000000000001000001ffff0c000001040001000000020000000101040001000000020000000201030001000000100000000301030001000000010000000601030001000000010000001101040001000000080000001501030001000000010000001601040001000000020000001701040001000000080000001a01050001000000a60000001b01050001000000ae000000280103000100000002000000000000002c010000010000002c01000001000000";

    private const string ColorGolden =
        "49492a000e000000ffff008001000e000001040001000000010000000101040001000000010000000201030003000000cc0000000301030001000000010000000601030001000000020000000e01020005000000d20000001101040001000000080000001501030001000000030000001601040001000000010000001701040001000000060000001a01050001000000bc0000001b01050001000000c40000002801030001000000020000006987040001000000ec0000000000000096000000010000009600000001000000100010001000486900000000313938353a30373a32332030303a30303a30300001000390020014000000d800000000000000";

    [Fact]
    public void Gray_IsOneUncompressedBlackIsZeroStripOf16BitSamples()
    {
        var pixels = new DeepPixels(2, 2, 1, [0, 1, 256, 65535]);
        Assert.Equal(GrayGolden, Convert.ToHexString(DeepTiff.Make(pixels, 300)).ToLowerInvariant());
    }

    [Fact]
    public void Color_HasThreeSamplesAndTheDetails()
    {
        var pixels = new DeepPixels(1, 1, 3, [65535, 32768, 1]);
        byte[] tiff = DeepTiff.Make(pixels, 150, new PhotoDetails(1985, 7, 23, "Hi"));
        Assert.Equal(ColorGolden, Convert.ToHexString(tiff).ToLowerInvariant());
    }

    [Fact]
    public void Details_AreLeftOutWhenThereAreNone()
    {
        var pixels = new DeepPixels(2, 2, 1, [0, 1, 256, 65535]);
        Assert.Equal(DeepTiff.Make(pixels, 300), DeepTiff.Make(pixels, 300, new PhotoDetails()));
    }

    [Fact]
    public void OnlyASinglePageTiffIsWrittenHere()
    {
        Assert.True(DeepTiff.Applies(OutputFormat.Tiff));
        Assert.False(DeepTiff.Applies(OutputFormat.TiffPages));
        Assert.False(DeepTiff.Applies(OutputFormat.Png));
    }

    [Fact]
    public void Pixels_MustFillThePage()
    {
        Assert.Throws<ArgumentException>(() => new DeepPixels(2, 2, 1, [0, 1, 2]));
        Assert.Throws<ArgumentOutOfRangeException>(() => new DeepPixels(1, 1, 2, [0, 1]));
        Assert.Throws<ArgumentOutOfRangeException>(() => new DeepPixels(0, 1, 1, []));
    }

    private sealed class MarkStep : IPageStep
    {
        public string Name => "mark";
        public ScannedPage Apply(ScannedPage page) => page.WithDocumentLabel("marked");
    }

    private static ScannedPage Page() => new(new RgbaImage(1, 1, [255, 255, 255, 255]), 300, ColorMode.Color);

    [Fact]
    public void Cropped_KeepsTheRowsAndColumnsInsideTheRect()
    {
        var pixels = new DeepPixels(2, 2, 3, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
        var part = pixels.Cropped(new RectD(1, 0, 5, 1))!;
        Assert.Equal((1, 1, 3), (part.Width, part.Height, part.Channels));
        Assert.Equal([3, 4, 5], part.Samples);
        Assert.Null(pixels.Cropped(new RectD(2, 0, 1, 1)));
    }

    [Fact]
    public void Rotated_TurnsTheSamplesByQuarterTurns()
    {
        var pixels = new DeepPixels(2, 1, 3, [1, 2, 3, 4, 5, 6]);
        Assert.Same(pixels, pixels.Rotated(0));
        AssertTurned(pixels.Rotated(1), 1, 2, [1, 2, 3, 4, 5, 6]);
        AssertTurned(pixels.Rotated(2), 2, 1, [4, 5, 6, 1, 2, 3]);
        AssertTurned(pixels.Rotated(3), 1, 2, [4, 5, 6, 1, 2, 3]);
        Assert.Equal(pixels.Rotated(3).Samples, pixels.Rotated(-1).Samples);
    }

    private static void AssertTurned(DeepPixels turned, int width, int height, ushort[] samples)
    {
        Assert.Equal((width, height), (turned.Width, turned.Height));
        Assert.Equal(samples, turned.Samples);
    }

    [Fact]
    public void PhotoFlow_AsksForSixteenBitsOnlyForATiffInColorOrGray()
    {
        var s = new ScanSettings { Intent = ScanIntent.Photo, Format = OutputFormat.Tiff };
        Assert.False(s.WantsHighBitDepth);
        s.PhotoHighBitDepth = true;
        Assert.True(s.WantsHighBitDepth);
        s.ColorMode = ColorMode.Grayscale;
        Assert.True(s.WantsHighBitDepth);
        s.ColorMode = ColorMode.BlackWhite;
        Assert.False(s.WantsHighBitDepth);
        s.ColorMode = ColorMode.Color;
        s.Source = ScanSource.Negatives;
        Assert.False(s.WantsHighBitDepth);
        s.Source = ScanSource.Flatbed;
        s.Adjustments.RestoreFadedColors = true;
        Assert.False(s.WantsHighBitDepth);
        s.Adjustments.RestoreFadedColors = false;
        s.Format = OutputFormat.Png;
        Assert.False(s.WantsHighBitDepth);
        s.Format = OutputFormat.Tiff;
        s.Intent = ScanIntent.Document;
        Assert.False(s.WantsHighBitDepth);
    }

    [Fact]
    public void PageSteps_LeaveAPageWithDeepPixelsAlone()
    {
        var deep = new DeepPixels(1, 1, 3, [65535, 65535, 65535]);
        var processor = new PageProcessor([new MarkStep()]);
        var plain = processor.Process([Page()]).Pages.Single();
        var kept = processor.Process([new ScannedPage(Page().Image, 300, ColorMode.Color) { DeepPixels = deep }]).Pages.Single();
        Assert.Equal("marked", plain.DocumentLabel);
        Assert.Null(kept.DocumentLabel);
        Assert.Same(deep, kept.DeepPixels);
    }

    [Fact]
    public void DeepPixels_SurviveFactsAboutThePage_ButNotOtherPixels()
    {
        var deep = new DeepPixels(1, 1, 1, [1000]);
        var page = new ScannedPage(Page().Image, 300, ColorMode.Color) { DeepPixels = deep };
        Assert.Same(deep, page.WithInclusion(PageInclusion.Keep).DeepPixels);
        Assert.Same(deep, page.WithBlank(null).DeepPixels);
        Assert.Null(page.WithImage(Page().Image).DeepPixels);
    }
}
