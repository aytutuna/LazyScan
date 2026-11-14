namespace LazyScan.Core;

// The Mac's twin is Sources/LazyScanKit/Pipeline/TextSplit.swift (the same tests, the same bytes).

/// <summary>
/// A page cut into a one-bit text mask at the page's own resolution (<see cref="Bilevel"/> layout,
/// 0 = ink) and a low-resolution color background with the ink filled in from the paper around it:
/// the two layers of a mixed-raster PDF page.
/// </summary>
public sealed class TextSplit
{
    /// <summary>The background's resolution in dots per inch.</summary>
    public const int BackgroundDpi = 100;

    /// <summary>The ink, packed as <see cref="Bilevel"/>, <see cref="Width"/> × <see cref="Height"/> pixels.</summary>
    public byte[] Mask { get; }

    public int Width { get; }

    public int Height { get; }

    /// <summary>The page without its ink, at about <see cref="BackgroundDpi"/>.</summary>
    public RgbaImage Background { get; }

    private TextSplit(byte[] mask, int width, int height, RgbaImage background)
    {
        Mask = mask;
        Width = width;
        Height = height;
        Background = background;
    }

    /// <summary>
    /// Splits <paramref name="image"/>, scanned at <paramref name="dpi"/>: a pixel is ink where it is below
    /// the share of the paper there that black &amp; white makes black (<see cref="DocumentEnhancer.BlackShare"/>
    /// at <see cref="DocumentEnhancer.DefaultThreshold"/>). Each background pixel is the mean of the pixels it
    /// covers that are neither ink nor next to ink (the soft edge of a glyph); one with none takes the mean of
    /// the background pixels around it, pass after pass.
    /// </summary>
    public static TextSplit Split(RgbaImage image, int dpi)
    {
        int w = image.Width, h = image.Height;
        var gray = GrayImage.Luma(image);
        var paper = DocumentEnhancer.PaperMap(gray);
        int blackBelow = (int)Math.Floor(DocumentEnhancer.BlackShare(DocumentEnhancer.DefaultThreshold) * DocumentEnhancer.Levels + 0.5);
        int stride = Bilevel.Stride(w);
        var mask = new byte[stride * h];
        Array.Fill(mask, (byte)0xFF);
        var ink = new bool[w * h];
        for (int y = 0; y < h; y++)
        {
            for (int x = 0; x < w; x++)
            {
                if (DocumentEnhancer.Level(gray.Pixels[y * w + x], paper.ValueAt(x, y)) >= blackBelow) continue;
                ink[y * w + x] = true;
                mask[y * stride + (x >> 3)] &= (byte)~(0x80 >> (x & 7));
            }
        }

        int bw = Math.Clamp((int)(((long)w * BackgroundDpi + dpi / 2) / dpi), 1, w);
        int bh = Math.Clamp((int)(((long)h * BackgroundDpi + dpi / 2) / dpi), 1, h);
        var sums = new int[bw * bh * 3];
        var counts = new int[bw * bh];
        var src = image.Pixels;
        for (int by = 0; by < bh; by++)
        {
            int y0 = by * h / bh, y1 = Math.Max(y0 + 1, (by + 1) * h / bh);
            for (int bx = 0; bx < bw; bx++)
            {
                int x0 = bx * w / bw, x1 = Math.Max(x0 + 1, (bx + 1) * w / bw);
                int r = 0, g = 0, b = 0, n = 0;
                for (int y = y0; y < y1; y++)
                {
                    for (int x = x0; x < x1; x++)
                    {
                        if (NearInk(ink, w, h, x, y)) continue;
                        int i = (y * w + x) * 4;
                        r += src[i];
                        g += src[i + 1];
                        b += src[i + 2];
                        n++;
                    }
                }
                int o = by * bw + bx;
                counts[o] = n;
                if (n == 0) continue;
                sums[o * 3] = r / n;
                sums[o * 3 + 1] = g / n;
                sums[o * 3 + 2] = b / n;
            }
        }
        FillEmpty(sums, counts, bw, bh);

        var pixels = new byte[bw * bh * 4];
        for (int p = 0; p < bw * bh; p++)
        {
            pixels[p * 4] = (byte)sums[p * 3];
            pixels[p * 4 + 1] = (byte)sums[p * 3 + 1];
            pixels[p * 4 + 2] = (byte)sums[p * 3 + 2];
            pixels[p * 4 + 3] = 255;
        }
        return new TextSplit(mask, w, h, new RgbaImage(bw, bh, pixels));
    }

    private static bool NearInk(bool[] ink, int w, int h, int x, int y)
    {
        for (int ny = Math.Max(0, y - 1); ny <= Math.Min(h - 1, y + 1); ny++)
            for (int nx = Math.Max(0, x - 1); nx <= Math.Min(w - 1, x + 1); nx++)
                if (ink[ny * w + nx]) return true;
        return false;
    }

    /// <summary>Gives each pixel with no count the mean of the counted ones among its eight neighbors, until all have a value (white when none has).</summary>
    private static void FillEmpty(int[] values, int[] counts, int w, int h)
    {
        var known = new bool[w * h];
        int missing = 0;
        for (int p = 0; p < known.Length; p++)
        {
            known[p] = counts[p] > 0;
            if (!known[p]) missing++;
        }
        if (missing == known.Length)
        {
            Array.Fill(values, 255);
            return;
        }
        while (missing > 0)
        {
            var found = new List<int>();
            for (int y = 0; y < h; y++)
            {
                for (int x = 0; x < w; x++)
                {
                    int p = y * w + x;
                    if (known[p]) continue;
                    int r = 0, g = 0, b = 0, n = 0;
                    for (int ny = Math.Max(0, y - 1); ny <= Math.Min(h - 1, y + 1); ny++)
                    {
                        for (int nx = Math.Max(0, x - 1); nx <= Math.Min(w - 1, x + 1); nx++)
                        {
                            int q = ny * w + nx;
                            if (!known[q]) continue;
                            r += values[q * 3];
                            g += values[q * 3 + 1];
                            b += values[q * 3 + 2];
                            n++;
                        }
                    }
                    if (n == 0) continue;
                    values[p * 3] = r / n;
                    values[p * 3 + 1] = g / n;
                    values[p * 3 + 2] = b / n;
                    found.Add(p);
                }
            }
            foreach (int p in found) known[p] = true;
            missing -= found.Count;
        }
    }
}
