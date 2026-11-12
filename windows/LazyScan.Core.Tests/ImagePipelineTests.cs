using LazyScan.Core;
using Xunit;

namespace LazyScan.Core.Tests;

// Port of Tests/LazyScanTests/ImagePipelineTests.swift.

public class ImagePipelineTests
{
    // MARK: - Helpers

    /// <summary>Deterministic RGB gradient: r ramps with x, g with y, b with x+y.</summary>
    private static RgbaImage MakeGradientImage(int width = 64, int height = 64)
    {
        var pixels = new byte[width * height * 4];
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                int i = (y * width + x) * 4;
                pixels[i] = (byte)(x * 255 / (width - 1));
                pixels[i + 1] = (byte)(y * 255 / (height - 1));
                pixels[i + 2] = (byte)((x + y) * 255 / (width + height - 2));
                pixels[i + 3] = 255;
            }
        }
        return new RgbaImage(width, height, pixels);
    }

    /// <summary>Mid-gray image with a 3x3 red marker in the top-left corner (pixel coordinates).</summary>
    private static RgbaImage MakeMarkerImage(int width, int height)
    {
        var image = RgbaImage.Filled(width, height, 128, 128, 128);
        for (int y = 0; y < 3; y++)
        {
            for (int x = 0; x < 3; x++)
            {
                int i = (y * width + x) * 4;
                image.Pixels[i] = 255;
                image.Pixels[i + 1] = 0;
                image.Pixels[i + 2] = 0;
            }
        }
        return image;
    }

    private static (int R, int G, int B) Pixel(RgbaImage image, int x, int y)
    {
        int i = (y * image.Width + x) * 4;
        return (image.Pixels[i], image.Pixels[i + 1], image.Pixels[i + 2]);
    }

    /// <summary>Mean and standard deviation of Rec.601 luminance over all pixels (0...255 scale).</summary>
    private static (double Mean, double StdDev) LuminanceStats(RgbaImage image)
    {
        int count = image.Width * image.Height;
        var values = new double[count];
        for (int i = 0; i < count; i++)
        {
            values[i] = 0.299 * image.Pixels[i * 4] + 0.587 * image.Pixels[i * 4 + 1]
                      + 0.114 * image.Pixels[i * 4 + 2];
        }
        double mean = values.Average();
        double variance = values.Sum(v => (v - mean) * (v - mean)) / count;
        return (mean, Math.Sqrt(variance));
    }

    // MARK: - Tests

    [Fact]
    public void BrightnessRaisesMeanLuminance()
    {
        var input = MakeGradientImage();
        var settings = new AdjustmentSettings { Brightness = 0.5 };
        var output = ImagePipeline.Apply(settings, input, ColorMode.Color);
        Assert.Equal(input.Width, output.Width);
        Assert.Equal(input.Height, output.Height);
        Assert.True(LuminanceStats(output).Mean > LuminanceStats(input).Mean + 10,
                    "brightness +0.5 must raise mean luminance");
    }

    [Fact]
    public void ContrastRaisesStdDev()
    {
        var input = MakeGradientImage();
        var settings = new AdjustmentSettings { Contrast = 2.0 };
        var output = ImagePipeline.Apply(settings, input, ColorMode.Color);
        Assert.True(LuminanceStats(output).StdDev > LuminanceStats(input).StdDev * 1.2,
                    "contrast 2.0 must widen the luminance distribution");
    }

    [Fact]
    public void IdentityReturnsUnchangedPixels()
    {
        var input = MakeGradientImage();
        var output = ImagePipeline.Apply(new AdjustmentSettings(), input, ColorMode.Color);
        if (ReferenceEquals(output, input)) return; // returning the same instance is explicitly allowed
        Assert.Equal(input.Width, output.Width);
        Assert.Equal(input.Height, output.Height);
        Assert.Equal(input.Pixels, output.Pixels);
    }

    [Fact]
    public void GrayscaleMakesChannelsEqual()
    {
        var input = MakeGradientImage();
        var output = ImagePipeline.Apply(new AdjustmentSettings(), input, ColorMode.Grayscale);
        int maxDelta = 0;
        for (int i = 0; i < output.Pixels.Length; i += 4)
        {
            int r = output.Pixels[i], g = output.Pixels[i + 1], b = output.Pixels[i + 2];
            maxDelta = Math.Max(maxDelta, Math.Max(Math.Abs(r - g), Math.Max(Math.Abs(g - b), Math.Abs(r - b))));
        }
        Assert.True(maxDelta <= 2, $"grayscale output must have r==g==b (±2), max delta {maxDelta}");
    }

    [Fact]
    public void BlackWhiteBinarizes()
    {
        var input = MakeGradientImage();
        var output = ImagePipeline.Apply(new AdjustmentSettings(), input, ColorMode.BlackWhite);
        int maxMidDistance = 0;
        for (int i = 0; i < output.Pixels.Length; i += 4)
        {
            for (int c = 0; c < 3; c++)
            {
                int v = output.Pixels[i + c];
                maxMidDistance = Math.Max(maxMidDistance, Math.Min(v, 255 - v));
            }
        }
        Assert.True(maxMidDistance <= 6, $"blackWhite output must be ~0 or ~255 everywhere, got {maxMidDistance}");
    }

    [Fact]
    public void RotateOneQuarterTurnClockwise()
    {
        var input = MakeMarkerImage(64, 32);
        var output = ImagePipeline.Rotate(input, 1);
        Assert.Equal(32, output.Width);
        Assert.Equal(64, output.Height);

        // Clockwise: source top-left lands at the destination's top-right.
        // Probe (width-2, 1), which maps back to source (1, 1) inside the red marker.
        var probe = Pixel(output, output.Width - 2, 1);
        Assert.True(probe.R > 200, $"expected the red marker at the top-right; got {probe}");
        Assert.True(probe.G < 80, $"expected the red marker at the top-right; got {probe}");
        Assert.True(probe.B < 80, $"expected the red marker at the top-right; got {probe}");
    }

    [Fact]
    public void RotateZeroKeepsDimensions()
    {
        var input = MakeGradientImage(64, 32);
        var output = ImagePipeline.Rotate(input, 0);
        Assert.Equal(64, output.Width);
        Assert.Equal(32, output.Height);
    }

    // MARK: - Negative sharpness = soften (Windows-side; the Swift suite has no soften test)

    /// <summary>8x8-pixel black/white checkerboard: maximal local contrast.</summary>
    private static RgbaImage MakeCheckerboard(int width = 64, int height = 64)
    {
        var image = RgbaImage.Filled(width, height, 0, 0, 0);
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                if (((x / 8) + (y / 8)) % 2 == 0) continue;
                int i = (y * width + x) * 4;
                image.Pixels[i] = 255;
                image.Pixels[i + 1] = 255;
                image.Pixels[i + 2] = 255;
            }
        }
        return image;
    }

    private static RgbaImage Soften(RgbaImage input, double sharpness) =>
        ImagePipeline.Apply(new AdjustmentSettings { Sharpness = sharpness }, input, ColorMode.Color);

    [Fact]
    public void SoftenReducesEdgeContrast()
    {
        var input = MakeCheckerboard();
        var output = Soften(input, -1);
        Assert.Equal(input.Width, output.Width);
        Assert.Equal(input.Height, output.Height);
        double before = LuminanceStats(input).StdDev;
        double after = LuminanceStats(output).StdDev;
        Assert.True(after < before * 0.8, $"softening must reduce contrast: stddev {before:F1} -> {after:F1}");
        // Pixels at a block edge move toward the middle.
        var edge = Pixel(output, 7, 3);   // white/black boundary at x = 8
        Assert.InRange(edge.R, 20, 235);
    }

    [Fact]
    public void SoftenZeroIsIdentity()
    {
        var input = MakeCheckerboard();
        var output = Soften(input, 0);
        Assert.Equal(input.Pixels, output.Pixels);
    }

    [Fact]
    public void SoftenIsMonotonicInMagnitudeAndClampsAtTwo()
    {
        var input = MakeCheckerboard();
        double[] stdDevs = [.. new[] { -0.25, -0.5, -1.0, -2.0 }.Select(s => LuminanceStats(Soften(input, s)).StdDev)];
        for (int i = 1; i < stdDevs.Length; i++)
        {
            Assert.True(stdDevs[i] < stdDevs[i - 1],
                        $"stronger softening must blur more: {string.Join(", ", stdDevs.Select(v => v.ToString("F2")))}");
        }
        // The blur radius is min(-s, 2) * 2, so anything below -2 equals -2.
        Assert.Equal(Soften(input, -2).Pixels, Soften(input, -3).Pixels);
    }

    [Fact]
    public void SoftenClampsAtEdgesWithoutDarkening()
    {
        // Edge-clamped blur of a flat image is the image itself — no dark/transparent border.
        var input = RgbaImage.Filled(40, 30, 200, 120, 40);
        var output = Soften(input, -2);
        int maxDelta = 0;
        for (int i = 0; i < output.Pixels.Length; i++)
            maxDelta = Math.Max(maxDelta, Math.Abs(output.Pixels[i] - input.Pixels[i]));
        Assert.True(maxDelta <= 1, $"flat image must stay flat under the blur, max delta {maxDelta}");
    }

    [Fact]
    public void NegativeSharpnessIsNotIdentity()
    {
        Assert.False(new AdjustmentSettings { Sharpness = -0.5 }.IsIdentity);
    }

    [Fact]
    public void VanishinglySmallSofteningLeavesImageUnchanged()
    {
        // A hand-edited settings file can hold a sharpness so close to zero that 2σ²
        // underflows; that must not turn the kernel into NaN (a black page).
        var input = MakeCheckerboard();
        var output = Soften(input, -1e-170);
        Assert.Equal(input.Pixels, output.Pixels);
    }

    // MARK: - Restore faded colors

    /// <summary>A ramp from black to white seen through a yellow cast: blue falls short, red runs high.</summary>
    private static RgbaImage MakeYellowedRamp(int width = 64, int height = 64)
    {
        var pixels = new byte[width * height * 4];
        for (int y = 0; y < height; y++)
        {
            for (int x = 0; x < width; x++)
            {
                int i = (y * width + x) * 4;
                double ramp = x * 255.0 / (width - 1);
                pixels[i] = (byte)(30 + ramp * 0.85);
                pixels[i + 1] = (byte)(20 + ramp * 0.8);
                pixels[i + 2] = (byte)(ramp * 0.45);
                pixels[i + 3] = 255;
            }
        }
        return new RgbaImage(width, height, pixels);
    }

    private static int Spread((int R, int G, int B) p) =>
        Math.Max(p.R, Math.Max(p.G, p.B)) - Math.Min(p.R, Math.Min(p.G, p.B));

    [Fact]
    public void RestoreFadedColorsNeutralizesWhitesAndBlacks()
    {
        var input = MakeYellowedRamp();
        Assert.True(Spread(Pixel(input, 63, 10)) > 100);
        Assert.True(Spread(Pixel(input, 0, 10)) > 20);
        var output = ImagePipeline.Apply(new AdjustmentSettings { RestoreFadedColors = true }, input, ColorMode.Color);
        var white = Pixel(output, 63, 10);
        var black = Pixel(output, 0, 10);
        Assert.True(Spread(white) <= 12, $"white end must be near neutral, got {white}");
        Assert.True(Spread(black) <= 12, $"black end must be near neutral, got {black}");
        Assert.True(white.R > 240 && black.R < 15, $"expected the full range, got {black} to {white}");
    }

    [Fact]
    public void RestoreFadedColorsLeavesGrayscaleToTheModeOnly()
    {
        var input = MakeYellowedRamp();
        var restored = ImagePipeline.Apply(new AdjustmentSettings { RestoreFadedColors = true }, input, ColorMode.Grayscale);
        var plain = ImagePipeline.Apply(new AdjustmentSettings(), input, ColorMode.Grayscale);
        Assert.True(Pixel(restored, 63, 10).R < Pixel(plain, 63, 10).R + 20,
                    "grayscale keeps the original white level");
    }

    [Fact]
    public void FadedColorTablesStretchBetweenPercentiles()
    {
        var uniform = Enumerable.Repeat(100, 256).ToArray();
        var tables = ImagePipeline.FadedColorTables([uniform, uniform, uniform]);
        foreach (var table in tables)
        {
            Assert.Equal(0, table[0]);
            Assert.Equal(0, table[1]);
            Assert.Equal(128, table[128]);
            Assert.Equal(255, table[254]);
            Assert.Equal(255, table[255]);
        }
    }

    [Fact]
    public void FadedColorTablesLeaveNarrowChannelsAlone()
    {
        var narrow = new int[256];
        for (int v = 100; v <= 140; v++) narrow[v] = 50;
        var tables = ImagePipeline.FadedColorTables([narrow, narrow, narrow]);
        for (int v = 0; v < 256; v++) Assert.Equal(v, tables[0][v]);
    }

    public static IEnumerable<object[]> BandedSettings() => new[]
    {
        new object[] { new AdjustmentSettings { AutoEnhance = true, Brightness = 0.2, Contrast = 1.2 }, ColorMode.Color },
        new object[] { new AdjustmentSettings { Sharpness = 0.8 }, ColorMode.Color },
        new object[] { new AdjustmentSettings { Sharpness = -1.5 }, ColorMode.Grayscale },
        new object[] { new AdjustmentSettings { Descreen = true, RestoreFadedColors = true }, ColorMode.Color },
        new object[] { new AdjustmentSettings { AutoEnhance = true, Sharpness = 1, Descreen = true }, ColorMode.BlackWhite },
        new object[] { new AdjustmentSettings(), ColorMode.BlackWhite },
    };

    [Theory]
    [MemberData(nameof(BandedSettings))]
    public void BandsGiveTheSameBytesAsOnePass(AdjustmentSettings settings, ColorMode mode)
    {
        var input = MakeGradientImage(41, 97);
        for (int i = 0; i < input.Pixels.Length; i += 4) input.Pixels[i + 1] ^= (byte)(i * 7);
        var whole = ImagePipeline.Apply(settings, input, mode, input.Height);
        foreach (int rows in new[] { 1, 5, 32 })
            Assert.Equal(whole.Pixels, ImagePipeline.Apply(settings, input, mode, rows).Pixels);
    }

    [Fact]
    public void AutoEnhanceMatchesTheSortedPercentiles()
    {
        var input = MakeGradientImage(41, 97);
        for (int i = 0; i < input.Pixels.Length; i += 4) input.Pixels[i + 1] ^= (byte)(i * 7);
        int n = input.Width * input.Height;
        var luma = new double[n];
        for (int i = 0; i < n; i++)
            luma[i] = 0.299 * input.Pixels[i * 4] / 255 + 0.587 * input.Pixels[i * 4 + 1] / 255 + 0.114 * input.Pixels[i * 4 + 2] / 255;
        Array.Sort(luma);
        double lo = luma[(int)(n * 0.01)];
        double hi = luma[Math.Min(n - 1, (int)(n * 0.99))];
        Assert.True(hi - lo >= 0.05);

        var output = ImagePipeline.Apply(new AdjustmentSettings { AutoEnhance = true }, input, ColorMode.Color);
        for (int i = 0; i < n * 4; i++)
        {
            if (i % 4 == 3) continue;
            double v = (input.Pixels[i] / 255.0 - lo) / (hi - lo);
            Assert.Equal((byte)Math.Clamp(Math.Round(v * 255), 0, 255), output.Pixels[i]);
        }
    }

    [Fact]
    public void AutoEnhanceStretchesTheMiddleOfTheRange()
    {
        var input = RgbaImage.Filled(100, 100, 100, 100, 100);
        for (int i = 0; i < 100 * 100; i++)
        {
            byte v = (byte)(80 + i % 100 / 2);
            input.Pixels[i * 4] = input.Pixels[i * 4 + 1] = input.Pixels[i * 4 + 2] = v;
        }
        var output = ImagePipeline.Apply(new AdjustmentSettings { AutoEnhance = true }, input, ColorMode.Color);
        // 80...129 with the 1st/99th percentiles at 80 and 129: the ends map to 0 and 255.
        Assert.Equal(0, Pixel(output, 0, 0).R);
        Assert.Equal(255, Pixel(output, 98, 0).R);
    }
}
