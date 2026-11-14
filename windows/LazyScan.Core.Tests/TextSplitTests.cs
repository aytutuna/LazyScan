using LazyScan.Core;
using Xunit;

namespace LazyScan.Core.Tests;

// Mirrors Tests/LazyScanTests/TextSplitTests.swift: the same page, the same numbers.

public class TextSplitTests
{
    private const int Width = 240, Height = 320;

    private static TextSplit Page(bool picture = false) =>
        TextSplit.Split(EnhancerPages.Shadowed(Width, Height, stamp: true, picture: picture), 300);

    [Fact]
    public void MaskHoldsThePrintAndTheStampAndNothingElse()
    {
        var split = Page();
        Assert.Equal(Width, split.Width);
        Assert.Equal(Height, split.Height);
        Assert.Equal(Bilevel.Stride(Width) * Height, split.Mask.Length);
        for (int y = 0; y < Height; y++)
        {
            for (int x = 0; x < Width; x++)
            {
                bool ink = EnhancerPages.IsInk(x, y, Width, Height) || EnhancerPages.IsStamp(x, y);
                Assert.Equal(ink, Bilevel.IsBlack(split.Mask, Width, x, y));
            }
        }
    }

    [Fact]
    public void BackgroundIsAHundredDpiAndFreeOfInk()
    {
        var split = Page();
        Assert.Equal(80, split.Background.Width);
        Assert.Equal(107, split.Background.Height);
        // The shadow darkens the paper toward the bottom right, so the background there is darker, but
        // never as dark as print (luma 40 of 255 under the same light) or the stamp.
        var px = split.Background.Pixels;
        for (int p = 0; p < px.Length; p += 4)
        {
            Assert.True(px[p] >= 80 && px[p + 1] >= 80 && px[p + 2] >= 70, $"pixel {p / 4} is {px[p]},{px[p + 1]},{px[p + 2]}");
            Assert.Equal(255, px[p + 3]);
        }
    }

    [Fact]
    public void ABlankPageHasNoInk()
    {
        var split = TextSplit.Split(RgbaImage.Filled(100, 60, 230, 226, 210), 200);
        Assert.All(split.Mask, b => Assert.Equal(0xFF, b));
        Assert.Equal(50, split.Background.Width);
        Assert.Equal(30, split.Background.Height);
        Assert.Equal(230, split.Background.Pixels[0]);
    }

    [Fact]
    public void BackgroundUnderAPictureIsFilledFromThePaperAround()
    {
        var split = Page(picture: true);
        // The dark picture is cut out with the ink, so it lands in the mask and is wiped from the background.
        // The picture (x 40-139, y 200-289) is at 100 dpi about 13-46, 67-96 in the background.
        int o = (80 * 80 + 30) * 4;
        Assert.True(split.Background.Pixels[o] > 100);
    }

    [Fact]
    public void FixturePins()
    {
        var split = Page();
        int black = 0;
        for (int y = 0; y < Height; y++)
            for (int x = 0; x < Width; x++)
                if (Bilevel.IsBlack(split.Mask, Width, x, y)) black++;
        var px = split.Background.Pixels;
        int mid = (50 * 80 + 40) * 4;
        int last = px.Length - 4;
        Assert.Equal(10292, black);
        Assert.Equal(new byte[] { 231, 225, 211 }, px[..3]);
        Assert.Equal(new byte[] { 159, 155, 145 }, px[mid..(mid + 3)]);
        Assert.Equal(new byte[] { 87, 85, 80 }, px[last..(last + 3)]);
    }
}
