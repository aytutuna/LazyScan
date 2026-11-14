using LazyScan.App.Services;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

// The mixed page of a color text page at Smallest against the plain JPEG page the old path wrote.
public class PdfMixedSizeTests
{
    private const int Width = 1275, Height = 1650;

    private static RgbaImage TextPage()
    {
        var pixels = new byte[Width * Height * 4];
        for (int y = 0; y < Height; y++)
        {
            for (int x = 0; x < Width; x++)
            {
                bool ink = x >= 100 && x < Width - 100 && y >= 150 && y < Height - 150 && (y - 150) % 24 < 5 && (x - 100) / 14 % 6 != 5;
                int light = 255 - 40 * x / (Width - 1) - 30 * y / (Height - 1);
                int o = (y * Width + x) * 4;
                pixels[o] = (byte)((ink ? 40 : 238) * light / 255);
                pixels[o + 1] = (byte)((ink ? 38 : 232) * light / 255);
                pixels[o + 2] = (byte)((ink ? 44 : 214) * light / 255);
                pixels[o + 3] = 255;
            }
        }
        return new RgbaImage(Width, Height, pixels);
    }

    [Fact]
    public void AMixedPageIsNoLargerThanThePlainJpegPage()
    {
        var image = TextPage();
        var split = PdfImageEncoding.SplitPage(image, 150, ColorMode.Color, PdfSizePreset.Smallest)!.Value;
        int mixed = WpfImageCodec.EncodeBackground(split.Split.Background, PdfSizePreset.Smallest).Length + split.G4.Length;

        var plan = PdfImageEncoding.Plan(ColorMode.Color, 150, PdfSizePreset.Smallest, image);
        var pixels = PdfImageEncoding.Downsample(image, 150, plan);
        int plain = WpfImageCodec.EncodeJpeg(pixels, plan.TargetDpi, plan.Quality, plan.IsGray).Length;

        Assert.True(mixed <= plain, $"mixed {mixed} bytes, plain {plain} bytes");
    }
}
