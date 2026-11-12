using System.Numerics;

namespace LazyScan.Core;

/// <summary>
/// Adjustments + color-mode conversion, ported from
/// Sources/LazyScanKit/Pipeline/ImagePipeline.swift.
///
/// The macOS original composes Core Image filters; this port re-implements each step as
/// per-pixel math so the Core stays dependency-free. Semantics per step match the CI filter
/// parameters used by the Swift version; visual output is close but not bit-identical
/// (documented divergences: AutoEnhance is a histogram auto-level rather than Apple's
/// proprietary suggestion list, and grayscale/B&W stay RGBA rather than 8-bit gray).
/// </summary>
public static class ImagePipeline
{
    /// <summary>
    /// Apply adjustments + color-mode conversion. Returns the input instance unchanged when
    /// <c>settings.IsIdentity &amp;&amp; colorMode == Color</c>.
    /// </summary>
    public static RgbaImage Apply(AdjustmentSettings settings, RgbaImage image, ColorMode colorMode) =>
        Apply(settings, image, colorMode, 0);

    /// <summary><paramref name="bandRows"/> is the rows per band; 0 sizes bands to about two million pixels.</summary>
    internal static RgbaImage Apply(AdjustmentSettings settings, RgbaImage image, ColorMode colorMode, int bandRows)
    {
        if (settings.IsIdentity && colorMode == ColorMode.Color) return image;

        int w = image.Width, h = image.Height;
        var src = image.Pixels;
        var output = new byte[w * h * 4];
        var levels = settings.AutoEnhance ? FindLevels(src, w * h) : null;

        // The page goes through in bands of rows plus a halo of the rows the blurs reach into,
        // so a band of doubles is alive at a time instead of three per pixel of the page.
        int halo = HaloRows(settings);
        int coreRows = bandRows > 0 ? bandRows : Math.Max(32, (1 << 21) / Math.Max(w, 1));
        int capacity = Math.Min(h, coreRows + 2 * halo) * w;
        var r = new double[capacity];
        var g = new double[capacity];
        var b = new double[capacity];
        var scratch = settings.Sharpness != 0 || settings.Descreen ? new double[capacity] : null;
        var blurred = settings.Sharpness > 0 || settings.Descreen
            ? new[] { new double[capacity], new double[capacity], new double[capacity] }
            : null;
        // Restore faded colors levels the whole page, so the first sweep only counts the
        // histograms of the values that step 5 sees and the second one writes the output.
        byte[][]? tables = null;
        if (settings.RestoreFadedColors && colorMode == ColorMode.Color)
        {
            var histograms = new[] { new int[256], new int[256], new int[256] };
            Sweep(histograms);
            tables = FadedColorTables(histograms);
        }
        Sweep(null);
        return new RgbaImage(w, h, output);

        void Sweep(int[][]? histograms)
        {
            for (int y0 = 0; y0 < h; y0 += coreRows)
            {
                int y1 = Math.Min(h, y0 + coreRows);
                int e0 = Math.Max(0, y0 - halo);
                int e1 = Math.Min(h, y1 + halo);
                int first = e0 * w * 4;
                int count = (e1 - e0) * w;
                for (int i = 0; i < count; i++)
                {
                    r[i] = src[first + i * 4] / 255.0;
                    g[i] = src[first + i * 4 + 1] / 255.0;
                    b[i] = src[first + i * 4 + 2] / 255.0;
                }
                int from = (y0 - e0) * w;
                ApplyBand(settings, colorMode, levels, tables, histograms, from, (y1 - y0) * w,
                          r, g, b, w, e1 - e0, scratch, blurred);
                if (histograms is not null) continue;

                int target = y0 * w * 4;
                int pixels = (y1 - y0) * w;
                for (int i = 0; i < pixels; i++)
                {
                    output[target + i * 4] = ToByte(r[from + i]);
                    output[target + i * 4 + 1] = ToByte(g[from + i]);
                    output[target + i * 4 + 2] = ToByte(b[from + i]);
                    output[target + i * 4 + 3] = src[target + i * 4 + 3];
                }
            }
        }
    }

    /// <summary>Rows above and below a band that the spatial steps of <paramref name="settings"/> read.</summary>
    private static int HaloRows(AdjustmentSettings settings)
    {
        int halo = 0;
        if (settings.Sharpness > 0) halo += 1;
        else if (settings.Sharpness < 0) halo += BlurReach(settings.Sharpness);
        if (settings.Descreen) halo += 2;
        return halo;
    }

    private static double SoftenSigma(double sharpness) => Math.Min(-sharpness, 2) * 2;

    private static int BlurReach(double sharpness)
    {
        double sigma = SoftenSigma(sharpness);
        return sigma >= MinBlurSigma ? Math.Max(1, (int)Math.Ceiling(3 * sigma)) : 0;
    }

    /// <summary>
    /// Steps 1 to 6 on one band: the first <paramref name="h"/> rows of the arrays. With
    /// <paramref name="histograms"/> it stops before step 5 after counting the band's own pixels
    /// (<paramref name="corePixels"/> from <paramref name="coreFrom"/>); otherwise
    /// <paramref name="tables"/> holds the step 5 tables of a color scan.
    /// </summary>
    private static void ApplyBand(AdjustmentSettings settings, ColorMode colorMode, (double Lo, double Gain)? levels,
                                  byte[][]? tables, int[][]? histograms, int coreFrom, int corePixels,
                                  double[] r, double[] g, double[] b, int w, int h,
                                  double[]? scratch, double[][]? blurred)
    {
        int count = w * h;

        // 1. Auto enhance — histogram auto-levels: stretch each channel so the 1st/99th
        //    luminance percentiles reach toward black/white (stand-in for CI's suggested filters).
        if (levels is { } stretch) ApplyLevels(r, g, b, count, stretch.Lo, stretch.Gain);

        // 2. Brightness (-1...1) split across exposure (±1.5 EV) and a small additive lift,
        //    plus contrast and saturation (CIExposureAdjust + CIColorControls semantics).
        if (settings.Brightness != 0)
        {
            double gain = Math.Pow(2, settings.Brightness * 1.5);
            for (int i = 0; i < count; i++)
            {
                r[i] *= gain; g[i] *= gain; b[i] *= gain;
            }
        }
        double additive = settings.Brightness * 0.15;
        if (additive != 0 || settings.Contrast != 1 || settings.Saturation != 1)
            ColorControls(r, g, b, count, additive, settings.Contrast, settings.Saturation);

        // 3. Sharpen (CISharpenLuminance approximation: unsharp mask) — or, for negative
        //    values, soften with a small Gaussian blur (CIGaussianBlur semantics: the radius
        //    is the standard deviation; edges are clamped, so the extent is unchanged).
        if (settings.Sharpness > 0)
        {
            Sharpen(r, g, b, w, h, settings.Sharpness, blurred!, scratch!);
        }
        else if (settings.Sharpness < 0)
        {
            double radius = SoftenSigma(settings.Sharpness);
            GaussianBlur(r, w, h, radius, scratch);
            GaussianBlur(g, w, h, radius, scratch);
            GaussianBlur(b, w, h, radius, scratch);
        }

        // 4. Descreen: tiny blur to break up halftone moiré, then a mild re-sharpen.
        if (settings.Descreen)
        {
            GaussianBlur3x3(r, g, b, w, h, scratch!);
            Sharpen(r, g, b, w, h, 0.4, blurred!, scratch!);
        }

        // 5. Restore faded colors: each channel stretched between its own percentiles with the
        //    midtone cast neutralized (color scans only), then a vibrance boost and slight contrast.
        if (settings.RestoreFadedColors)
        {
            if (colorMode == ColorMode.Color)
            {
                if (histograms is not null)
                {
                    CountChannels(histograms, r, g, b, coreFrom, corePixels);
                    return;
                }
                LevelChannels(r, g, b, count, tables!);
            }
            Vibrance(r, g, b, count, 0.5);
            ColorControls(r, g, b, count, 0, 1.05, 1);
        }

        // 6. Color-mode conversion.
        switch (colorMode)
        {
            case ColorMode.Color:
                break;
            case ColorMode.Grayscale:
                ColorControls(r, g, b, count, 0, 1, 0);
                break;
            case ColorMode.BlackWhite:
                // Desaturate first so the threshold applies to luminance.
                ColorControls(r, g, b, count, 0, 1, 0);
                for (int i = 0; i < count; i++)
                {
                    double v = r[i] > settings.BlackWhiteThreshold ? 1 : 0;
                    r[i] = v; g[i] = v; b[i] = v;
                }
                break;
        }
    }

    /// <summary>Lossless 90° steps, clockwise. quarterTurns 0...3.</summary>
    public static RgbaImage Rotate(RgbaImage image, int quarterTurns) =>
        image.RotatedQuarterTurns(quarterTurns);

    // MARK: - Steps

    private static byte ToByte(double v) => (byte)Math.Clamp(Math.Round(v * 255), 0, 255);

    private static double Luma(double r, double g, double b) =>
        0.299 * r + 0.587 * g + 0.114 * b;

    /// <summary>
    /// CIColorControls: additive brightness, contrast about mid-gray, saturation as a
    /// lerp between the pixel and its luminance.
    /// </summary>
    private static void ColorControls(double[] r, double[] g, double[] b, int count,
                                      double brightness, double contrast, double saturation)
    {
        for (int i = 0; i < count; i++)
        {
            double pr = r[i] + brightness;
            double pg = g[i] + brightness;
            double pb = b[i] + brightness;
            if (contrast != 1)
            {
                pr = (pr - 0.5) * contrast + 0.5;
                pg = (pg - 0.5) * contrast + 0.5;
                pb = (pb - 0.5) * contrast + 0.5;
            }
            if (saturation != 1)
            {
                double y = Luma(pr, pg, pb);
                pr = y + (pr - y) * saturation;
                pg = y + (pg - y) * saturation;
                pb = y + (pb - y) * saturation;
            }
            r[i] = pr; g[i] = pg; b[i] = pb;
        }
    }

    /// <summary>Unsharp mask: out = px + amount * (px - blur3x3(px)).</summary>
    private static void Sharpen(double[] r, double[] g, double[] b, int w, int h, double amount,
                                double[][] blurred, double[] scratch)
    {
        int count = w * h;
        var br = blurred[0];
        var bg = blurred[1];
        var bb = blurred[2];
        Array.Copy(r, br, count);
        Array.Copy(g, bg, count);
        Array.Copy(b, bb, count);
        GaussianBlur3x3(br, bg, bb, w, h, scratch);
        for (int i = 0; i < count; i++)
        {
            r[i] += amount * (r[i] - br[i]);
            g[i] += amount * (g[i] - bg[i]);
            b[i] += amount * (b[i] - bb[i]);
        }
    }

    /// <summary>Separable [1 2 1]/4 Gaussian, edge-clamped — the radius-1 blur used by descreen.</summary>
    private static void GaussianBlur3x3(double[] r, double[] g, double[] b, int w, int h, double[] scratch)
    {
        BlurPass(r, w, h, scratch);
        BlurPass(g, w, h, scratch);
        BlurPass(b, w, h, scratch);
    }

    /// <summary>
    /// One edge-clamped [1 2 1]/4 pass in each direction, in place. <paramref name="scratch"/>
    /// (at least <c>w * h</c> long, contents ignored) is reused when given so several
    /// channels share one temporary buffer.
    /// </summary>
    internal static void BlurPass(double[] channel, int w, int h, double[]? scratch = null)
    {
        var tmp = scratch is not null && scratch.Length >= w * h ? scratch : new double[w * h];
        // Horizontal: only the first and last column clamp; the interior reads its neighbors directly.
        ForEachRow(h, (long)w * 3, y =>
        {
            int row = y * w;
            BlurPassBorder(channel, tmp, row, w, 0);
            if (w > 1) BlurPassBorder(channel, tmp, row, w, w - 1);
            int x = 1;
            int end = w - 1;
            if (Vector.IsHardwareAccelerated)
            {
                var two = new Vector<double>(2);
                var four = new Vector<double>(4);
                for (; x <= end - Vector<double>.Count; x += Vector<double>.Count)
                {
                    var left = new Vector<double>(channel, row + x - 1);
                    var mid = new Vector<double>(channel, row + x);
                    var right = new Vector<double>(channel, row + x + 1);
                    ((left + two * mid + right) / four).CopyTo(tmp, row + x);
                }
            }
            for (; x < end; x++)
            {
                tmp[row + x] = (channel[row + x - 1] + 2 * channel[row + x] + channel[row + x + 1]) / 4;
            }
        });
        // Vertical: clamping picks whole rows, so every column of a row shares the same sources.
        ForEachRow(h, (long)w * 3, y =>
        {
            int row = y * w;
            int up = Math.Max(0, y - 1) * w;
            int down = Math.Min(h - 1, y + 1) * w;
            int x = 0;
            if (Vector.IsHardwareAccelerated)
            {
                var two = new Vector<double>(2);
                var four = new Vector<double>(4);
                for (; x <= w - Vector<double>.Count; x += Vector<double>.Count)
                {
                    var a = new Vector<double>(tmp, up + x);
                    var mid = new Vector<double>(tmp, row + x);
                    var c = new Vector<double>(tmp, down + x);
                    ((a + two * mid + c) / four).CopyTo(channel, row + x);
                }
            }
            for (; x < w; x++)
            {
                channel[row + x] = (tmp[up + x] + 2 * tmp[row + x] + tmp[down + x]) / 4;
            }
        });
    }

    private static void BlurPassBorder(double[] channel, double[] tmp, int row, int w, int x)
    {
        double left = channel[row + Math.Max(0, x - 1)];
        double mid = channel[row + x];
        double right = channel[row + Math.Min(w - 1, x + 1)];
        tmp[row + x] = (left + 2 * mid + right) / 4;
    }

    /// <summary>
    /// Below this standard deviation the kernel is numerically [0 1 0] (the outer taps
    /// underflow to zero), so the blur is the identity — and for absurdly small values
    /// (hand-edited settings) 2σ² itself underflows to zero and the kernel turns into NaN.
    /// </summary>
    private const double MinBlurSigma = 1e-3;

    /// <summary>
    /// Separable Gaussian with standard deviation <paramref name="sigma"/>, sampled over
    /// ±3σ and clamped to the edge — CIGaussianBlur on a clamped-to-extent image, cropped
    /// back to the original extent. <paramref name="scratch"/> (at least <c>w * h</c> long,
    /// contents ignored) is reused when given so several channels share one temporary buffer.
    ///
    /// Each output pixel accumulates its taps in the same order as the plain clamp-per-tap
    /// loop, so the result is bit-identical to it; the speed comes from clamping only at the
    /// borders, vectorizing across pixels, and processing rows in parallel.
    /// </summary>
    internal static void GaussianBlur(double[] channel, int w, int h, double sigma, double[]? scratch = null)
    {
        if (!(sigma >= MinBlurSigma)) return; // also rejects NaN
        int k = Math.Max(1, (int)Math.Ceiling(3 * sigma));
        var kernel = new double[2 * k + 1];
        double sum = 0;
        for (int i = -k; i <= k; i++)
        {
            kernel[i + k] = Math.Exp(-(i * i) / (2 * sigma * sigma));
            sum += kernel[i + k];
        }
        for (int i = 0; i < kernel.Length; i++) kernel[i] /= sum;

        var tmp = scratch is not null && scratch.Length >= w * h ? scratch : new double[w * h];
        long workPerRow = (long)w * kernel.Length;
        // Horizontal: clamp only where the kernel overhangs the left/right edge.
        ForEachRow(h, workPerRow, y =>
        {
            int row = y * w;
            int interiorStart = Math.Min(k, w);
            int interiorEnd = Math.Max(interiorStart, w - k);
            for (int x = 0; x < interiorStart; x++) tmp[row + x] = ClampedTaps(channel, row, w, x, kernel, k);
            for (int x = interiorEnd; x < w; x++) tmp[row + x] = ClampedTaps(channel, row, w, x, kernel, k);

            int ix = interiorStart;
            if (Vector.IsHardwareAccelerated)
            {
                for (; ix <= interiorEnd - Vector<double>.Count; ix += Vector<double>.Count)
                {
                    var acc = Vector<double>.Zero;
                    int start = row + ix - k;
                    for (int j = 0; j < kernel.Length; j++)
                        acc += new Vector<double>(kernel[j]) * new Vector<double>(channel, start + j);
                    acc.CopyTo(tmp, row + ix);
                }
            }
            for (; ix < interiorEnd; ix++)
            {
                double acc = 0;
                int start = row + ix - k;
                for (int j = 0; j < kernel.Length; j++) acc += kernel[j] * channel[start + j];
                tmp[row + ix] = acc;
            }
        });
        // Vertical: clamping picks whole source rows, so each output row accumulates
        // tap by tap across all its pixels (cache-friendly row reads, no per-pixel clamp).
        ForEachRow(h, workPerRow, y =>
        {
            int row = y * w;
            var output = channel.AsSpan(row, w);
            output.Clear();
            for (int j = 0; j < kernel.Length; j++)
            {
                int source = Math.Clamp(y - k + j, 0, h - 1) * w;
                double weight = kernel[j];
                int x = 0;
                if (Vector.IsHardwareAccelerated)
                {
                    var weightVector = new Vector<double>(weight);
                    for (; x <= w - Vector<double>.Count; x += Vector<double>.Count)
                    {
                        var acc = new Vector<double>(channel, row + x)
                                  + weightVector * new Vector<double>(tmp, source + x);
                        acc.CopyTo(channel, row + x);
                    }
                }
                for (; x < w; x++) channel[row + x] += weight * tmp[source + x];
            }
        });
    }

    /// <summary>One horizontal Gaussian tap sum with edge clamping (border pixels only).</summary>
    private static double ClampedTaps(double[] channel, int row, int w, int x, double[] kernel, int k)
    {
        double acc = 0;
        for (int i = -k; i <= k; i++)
            acc += kernel[i + k] * channel[row + Math.Clamp(x + i, 0, w - 1)];
        return acc;
    }

    /// <summary>
    /// Run <paramref name="body"/> for every row, in parallel once the total work is large
    /// enough to repay the scheduling cost. Rows must be independent.
    /// </summary>
    private static void ForEachRow(int h, long workPerRow, Action<int> body)
    {
        if (h * workPerRow < 1 << 18)
        {
            for (int y = 0; y < h; y++) body(y);
            return;
        }
        Parallel.For(0, h, body);
    }

    /// <summary>CIVibrance approximation: boost saturation more for less-saturated pixels.</summary>
    private static void Vibrance(double[] r, double[] g, double[] b, int count, double amount)
    {
        for (int i = 0; i < count; i++)
        {
            double maxC = Math.Max(r[i], Math.Max(g[i], b[i]));
            double minC = Math.Min(r[i], Math.Min(g[i], b[i]));
            double sat = maxC - minC;
            double boost = 1 + amount * (1 - Math.Clamp(sat * 2, 0, 1));
            double y = Luma(r[i], g[i], b[i]);
            r[i] = y + (r[i] - y) * boost;
            g[i] = y + (g[i] - y) * boost;
            b[i] = y + (b[i] - y) * boost;
        }
    }

    private const int FadedClip = 5;      // per mille cut off at each end
    private const int FadedMinSpan = 64;  // narrower channels are left as they are

    /// <summary>
    /// One 256-entry table per channel from its byte histogram: the channel is stretched between
    /// the values that leave 0.5% of the pixels outside, then a gamma moves its stretched median to
    /// the mean of the three medians, which removes the cast of the midtones.
    /// </summary>
    internal static byte[][] FadedColorTables(int[][] histograms)
    {
        var lows = new int[3];
        var highs = new[] { 255, 255, 255 };
        var medians = new double[3];
        for (int c = 0; c < 3; c++)
        {
            var h = histograms[c];
            int total = h.Sum();
            int skip = total * FadedClip / 1000;
            int low = 0, high = 255, median = 0;
            int sum = 0;
            for (int v = 0; v < 256; v++)
            {
                sum += h[v];
                if (sum > skip) { low = v; break; }
            }
            sum = 0;
            for (int v = 255; v >= 0; v--)
            {
                sum += h[v];
                if (sum > skip) { high = v; break; }
            }
            sum = 0;
            for (int v = 0; v < 256; v++)
            {
                sum += h[v];
                if (sum * 2 >= total) { median = v; break; }
            }
            if (high - low >= FadedMinSpan)
            {
                lows[c] = low;
                highs[c] = high;
            }
            double span = highs[c] - lows[c];
            medians[c] = Math.Clamp((median - lows[c]) / span, 0, 1);
        }
        double target = (medians[0] + medians[1] + medians[2]) / 3;
        var tables = new byte[3][];
        for (int c = 0; c < 3; c++)
        {
            double gamma = 1;
            if (medians[c] > 0.02 && medians[c] < 0.98 && target > 0.02 && target < 0.98)
                gamma = Math.Clamp(Math.Log(target) / Math.Log(medians[c]), 0.7, 1.4);
            double span = highs[c] - lows[c];
            tables[c] = new byte[256];
            for (int v = 0; v < 256; v++)
            {
                double t = Math.Clamp((v - lows[c]) / span, 0, 1);
                tables[c][v] = (byte)Math.Clamp(Math.Round(Math.Pow(t, gamma) * 255, MidpointRounding.AwayFromZero), 0, 255);
            }
        }
        return tables;
    }

    private static void CountChannels(int[][] histograms, double[] r, double[] g, double[] b, int from, int count)
    {
        var channels = new[] { r, g, b };
        for (int c = 0; c < 3; c++)
        {
            var histogram = histograms[c];
            var values = channels[c];
            for (int i = from; i < from + count; i++) histogram[ToByte(values[i])]++;
        }
    }

    /// <summary>Applies <see cref="FadedColorTables"/> to the first <paramref name="count"/> pixels, as bytes.</summary>
    private static void LevelChannels(double[] r, double[] g, double[] b, int count, byte[][] tables)
    {
        var channels = new[] { r, g, b };
        for (int c = 0; c < 3; c++)
        {
            var values = channels[c];
            for (int i = 0; i < count; i++) values[i] = tables[c][ToByte(values[i])] / 255.0;
        }
    }

    /// <summary>
    /// Auto-levels: the offset and gain that linear-stretch all channels so the image's 1st/99th
    /// luminance percentiles map toward 0/1, or null for a nearly flat image. The luminance of a
    /// byte pixel is (299 R + 587 G + 114 B) / 255000, so a histogram of that integer gives the
    /// percentiles exactly without sorting. Conservative stand-in for CI auto-enhance.
    /// </summary>
    private static (double Lo, double Gain)? FindLevels(byte[] pixels, int count)
    {
        if (count == 0) return null;
        var histogram = new int[255 * 1000 + 1];
        for (int i = 0; i < count; i++)
            histogram[299 * pixels[i * 4] + 587 * pixels[i * 4 + 1] + 114 * pixels[i * 4 + 2]]++;
        double lo = LumaAtRank(histogram, (int)(count * 0.01));
        double hi = LumaAtRank(histogram, Math.Min(count - 1, (int)(count * 0.99)));
        if (hi - lo < 0.05) return null; // nearly flat image: leave it alone
        return (lo, 1.0 / (hi - lo));
    }

    /// <summary>The luminance of the pixel at zero-based <paramref name="rank"/> in sorted order.</summary>
    private static double LumaAtRank(int[] histogram, int rank)
    {
        long seen = 0;
        for (int v = 0; v < histogram.Length; v++)
        {
            seen += histogram[v];
            if (seen > rank) return v / 255000.0;
        }
        return 1;
    }

    private static void ApplyLevels(double[] r, double[] g, double[] b, int count, double lo, double gain)
    {
        for (int i = 0; i < count; i++)
        {
            r[i] = (r[i] - lo) * gain;
            g[i] = (g[i] - lo) * gain;
            b[i] = (b[i] - lo) * gain;
        }
    }
}
