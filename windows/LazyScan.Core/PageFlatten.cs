namespace LazyScan.Core;

// Twin of Sources/LazyScanKit/Pipeline/PageFlatten.swift: same constants, same steps and the same
// arithmetic (integer pixels and doubles, + - * / and truncation only), so a page gives the same bytes
// on both platforms.

/// <summary>
/// Flattens the curl of a book page photographed open, and fills fingers holding it at the margin.
/// <see cref="Flatten"/> finds the page's top and bottom edges column by column on a gray copy (the first
/// and last rows where the paper is bright, past the table or lid beside it), cleans the two curves up (a
/// median, then a mean, across columns) and draws every column again between them: output row y is the
/// share (y - top reference) / (bottom reference - top reference) of the way down the page, taken from the
/// same share of the way between that column's own edges. Only the height is corrected, not the
/// foreshortening across the columns. A page whose edges are not found, or are straight already, is left
/// alone. <see cref="FillFingers"/> looks in a band along each border for skin-colored patches that touch
/// the border and end inside the band (a thumb holding the page, not a picture that runs on) and paints
/// them with the paper's own color.
/// </summary>
public static class PageFlatten
{
    /// <summary>The edges are looked for in this share of the height from the top and from the bottom.</summary>
    public const double EdgeFraction = 0.25;
    /// <summary>A row is paper when its brightness is at least this share of the paper's.</summary>
    public const double PaperShare = 0.5;
    /// <summary>An edge is the first of this many paper rows in a row.</summary>
    public const int EdgeRun = 3;
    /// <summary>Columns around each one averaged when looking for the edge, on each side.</summary>
    public const int EdgeHalfWidth = 2;
    /// <summary>The edges must be found in at least this share of the columns.</summary>
    public const double MinFoundShare = 0.6;
    /// <summary>A page whose edges are further apart than this share of its height is a page.</summary>
    public const double MinPageShare = 0.5;
    /// <summary>The edges are smoothed across this share of the width, on each side (at least <see cref="MinSmoothColumns"/>).</summary>
    public const double SmoothShare = 0.01;
    public const int MinSmoothColumns = 2;
    /// <summary>
    /// An edge that jumps by more than this share of the height between two neighbouring columns where it is
    /// found is no page edge (a dark banner or a picture along the border), and the page is left alone.
    /// </summary>
    public const double MaxEdgeStepShare = 0.02;
    /// <summary>A page whose edges bend less than this share of its height is left alone.</summary>
    public const double MinCurveShare = 0.01;
    /// <summary>A page whose paper is darker than this gray level is left alone.</summary>
    public const int MinPaper = 96;
    /// <summary>The paper's brightness and color are read on the middle rows between these shares of the height...</summary>
    public const double PaperRowsFrom = 0.3;
    public const double PaperRowsTo = 0.7;
    /// <summary>...as this share of the pixels there being darker.</summary>
    public const double PaperPercentile = 0.8;

    /// <summary>Fingers are looked for this many inches inside each border...</summary>
    public const double FingerBandInches = 1.0;
    /// <summary>...in patches of at least...</summary>
    public const double MinFingerSquareInches = 0.03;
    /// <summary>...and at most this many square inches.</summary>
    public const double MaxFingerSquareInches = 4.0;
    /// <summary>A patch is painted over this far beyond its pixels, in inches (the blurred skin at its rim).</summary>
    public const double FingerGrowInches = 0.04;
    /// <summary>A pixel is skin when its red exceeds its green by this much more than the paper's does...</summary>
    public const int SkinRedOverGreen = 14;
    /// <summary>...and exceeds its blue by this much more...</summary>
    public const int SkinRedOverBlue = 25;
    /// <summary>...and its red is at least this.</summary>
    public const int SkinMinRed = 80;
    /// <summary>The paper's color is taken from pixels at least this share as bright as the paper.</summary>
    public const double InkShare = 0.7;

    /// <summary>
    /// <paramref name="image"/> with its page drawn flat between its curved top and bottom edges; null when
    /// the edges are not found or bend less than <see cref="MinCurveShare"/> of the height.
    /// </summary>
    public static RgbaImage? Flatten(RgbaImage image)
    {
        int w = image.Width, h = image.Height;
        if (w < 16 || h < 16) return null;
        byte[] gray = GrayImage.Luma(image).Pixels;
        int paper = PaperLevel(gray, w, h);
        if (paper < MinPaper) return null;
        double threshold = paper * PaperShare;
        int depth = (int)(h * EdgeFraction);
        if (Edges(gray, w, h, threshold, depth, fromTop: true) is not { } rawTop
            || Edges(gray, w, h, threshold, depth, fromTop: false) is not { } rawBottom) return null;
        int half = Math.Max(MinSmoothColumns, (int)(w * SmoothShare));
        var top = Smoothed(rawTop, half);
        var bottom = Smoothed(rawBottom, half);
        double topRef = top[0], bottomRef = bottom[0];
        for (int x = 0; x < w; x++)
        {
            if (top[x] < topRef) topRef = top[x];
            if (bottom[x] > bottomRef) bottomRef = bottom[x];
        }
        if (bottomRef - topRef < h * MinPageShare) return null;
        double bend = 0;
        for (int x = 0; x < w; x++)
        {
            if (bottom[x] - top[x] < h * MinPageShare) return null;
            bend = Math.Max(bend, (top[x] - topRef) + (bottomRef - bottom[x]));
        }
        if (bend < h * MinCurveShare) return null;

        var output = new byte[w * h * 4];
        Array.Fill(output, (byte)255);
        double span = bottomRef - topRef;
        double last = h - 1;
        var pixels = image.Pixels;
        for (int y = 0; y < h; y++)
        {
            double t = (y - topRef) / span;
            for (int x = 0; x < w; x++)
            {
                double s = top[x] + t * (bottom[x] - top[x]);
                if (s < 0) s = 0;
                if (s > last) s = last;
                int y0 = (int)s;
                if (y0 > h - 2) y0 = h - 2;
                double f = s - y0;
                int a = (y0 * w + x) * 4;
                int b = a + w * 4;
                int o = (y * w + x) * 4;
                for (int c = 0; c < 3; c++)
                {
                    double v = pixels[a + c] * (1 - f) + pixels[b + c] * f;
                    output[o + c] = (byte)(v + 0.5);
                }
            }
        }
        return new RgbaImage(w, h, output);
    }

    /// <summary>
    /// <paramref name="image"/>, taken at <paramref name="dpi"/>, with the fingers at its margins painted
    /// over with paper; null when there are none.
    /// </summary>
    public static RgbaImage? FillFingers(RgbaImage image, double dpi)
    {
        int w = image.Width, h = image.Height;
        int band = (int)(FingerBandInches * dpi);
        if (w < 16 || h < 16 || band < 8 || band * 4 > Math.Min(w, h)) return null;
        byte[] gray = GrayImage.Luma(image).Pixels;
        int paper = PaperLevel(gray, w, h);
        if (paper < MinPaper || PaperTone(image, gray, paper) is not { } tone) return null;
        int redOverGreen = tone.R - tone.G + SkinRedOverGreen;
        int redOverBlue = tone.R - tone.B + SkinRedOverBlue;
        var source = image.Pixels;

        bool IsSkin(int i)
        {
            int r = source[i], g = source[i + 1], b = source[i + 2];
            return r >= SkinMinRed && r - g >= redOverGreen && r - b >= redOverBlue;
        }
        int DepthAt(int x, int y) => Math.Min(Math.Min(x, w - 1 - x), Math.Min(y, h - 1 - y));

        var skin = new byte[w * h];
        for (int y = 0; y < h; y++)
        {
            for (int x = 0; x < w; x++)
            {
                if (DepthAt(x, y) < band && IsSkin((y * w + x) * 4)) skin[y * w + x] = 1;
            }
        }

        int minArea = (int)(MinFingerSquareInches * dpi * dpi);
        int maxArea = (int)(MaxFingerSquareInches * dpi * dpi);
        int grow = Math.Max(2, (int)(FingerGrowInches * dpi));
        double brightest = paper * InkShare;
        var output = image.Clone();
        bool painted = false;
        var seen = new byte[w * h];
        var next = new int[4];
        for (int start = 0; start < w * h; start++)
        {
            if (skin[start] != 1 || seen[start] != 0) continue;
            var cells = new List<int> { start };
            var stack = new Stack<int>();
            stack.Push(start);
            seen[start] = 1;
            bool runsOn = false;
            int minX = w, maxX = 0, minY = h, maxY = 0;
            while (stack.Count > 0)
            {
                int at = stack.Pop();
                int x = at % w, y = at / w;
                if (DepthAt(x, y) >= band - 1) runsOn = true;
                minX = Math.Min(minX, x); maxX = Math.Max(maxX, x);
                minY = Math.Min(minY, y); maxY = Math.Max(maxY, y);
                int count = 0;
                if (x > 0) next[count++] = at - 1;
                if (x < w - 1) next[count++] = at + 1;
                if (y > 0) next[count++] = at - w;
                if (y < h - 1) next[count++] = at + w;
                for (int k = 0; k < count; k++)
                {
                    int n = next[k];
                    if (skin[n] != 1 || seen[n] != 0) continue;
                    seen[n] = 1;
                    cells.Add(n);
                    stack.Push(n);
                }
            }
            if (runsOn || cells.Count < minArea || cells.Count > maxArea) continue;
            bool touches = false;
            foreach (int at in cells)
            {
                if (DepthAt(at % w, at / w) == 0)
                {
                    touches = true;
                    break;
                }
            }
            if (!touches) continue;

            // The paper beside the patch: bright pixels around its box that are not skin.
            long sumR = 0, sumG = 0, sumB = 0;
            int around = 0;
            int x0 = Math.Max(0, minX - grow - 4), x1 = Math.Min(w - 1, maxX + grow + 4);
            int y0 = Math.Max(0, minY - grow - 4), y1 = Math.Min(h - 1, maxY + grow + 4);
            for (int y = y0; y <= y1; y++)
            {
                for (int x = x0; x <= x1; x++)
                {
                    int i = y * w + x;
                    if (skin[i] == 0 && gray[i] >= brightest)
                    {
                        sumR += source[i * 4];
                        sumG += source[i * 4 + 1];
                        sumB += source[i * 4 + 2];
                        around++;
                    }
                }
            }
            if (around < 20) continue;
            byte[] fill = [(byte)(sumR / around), (byte)(sumG / around), (byte)(sumB / around)];
            int gx0 = Math.Max(0, minX - grow), gx1 = Math.Min(w - 1, maxX + grow);
            int gy0 = Math.Max(0, minY - grow), gy1 = Math.Min(h - 1, maxY + grow);
            int bw = gx1 - gx0 + 1, bh = gy1 - gy0 + 1;
            var cover = new byte[bw * bh];
            foreach (int at in cells) cover[(at / w - gy0) * bw + (at % w - gx0)] = 1;
            var wide = Spread(cover, bw, bh, grow, alongRows: true);
            var grown = Spread(wide, bw, bh, grow, alongRows: false);
            for (int y = gy0; y <= gy1; y++)
            {
                for (int x = gx0; x <= gx1; x++)
                {
                    if (grown[(y - gy0) * bw + (x - gx0)] != 1) continue;
                    int o = (y * w + x) * 4;
                    output.Pixels[o] = fill[0];
                    output.Pixels[o + 1] = fill[1];
                    output.Pixels[o + 2] = fill[2];
                }
            }
            painted = true;
        }
        return painted ? output : null;
    }

    /// <summary><paramref name="mask"/> with every set cell widened to the <paramref name="by"/> cells on each side of it, along its rows or along its columns.</summary>
    private static byte[] Spread(byte[] mask, int bw, int bh, int by, bool alongRows)
    {
        var result = new byte[bw * bh];
        int lines = alongRows ? bh : bw;
        int length = alongRows ? bw : bh;
        int stepAlong = alongRows ? 1 : bw;
        int stepAcross = alongRows ? bw : 1;
        for (int line = 0; line < lines; line++)
        {
            int start = line * stepAcross;
            int since = by + 1;
            for (int k = 0; k < length; k++)
            {
                int i = start + k * stepAlong;
                since = mask[i] == 1 ? 0 : since + 1;
                if (since <= by) result[i] = 1;
            }
            since = by + 1;
            for (int k = length - 1; k >= 0; k--)
            {
                int i = start + k * stepAlong;
                since = mask[i] == 1 ? 0 : since + 1;
                if (since <= by) result[i] = 1;
            }
        }
        return result;
    }

    /// <summary>The paper's gray level: the <see cref="PaperPercentile"/> of the middle rows.</summary>
    private static int PaperLevel(byte[] gray, int width, int height)
    {
        var histogram = new int[256];
        int from = (int)(height * PaperRowsFrom), to = (int)(height * PaperRowsTo);
        for (int y = from; y < Math.Max(from + 1, to); y++)
        {
            for (int x = 0; x < width; x++) histogram[gray[y * width + x]]++;
        }
        double wanted = (double)(width * Math.Max(1, to - from)) * PaperPercentile;
        double seen = 0;
        for (int level = 0; level < 256; level++)
        {
            seen += histogram[level];
            if (seen >= wanted) return level;
        }
        return 255;
    }

    /// <summary>The paper's mean color over the middle rows' pixels at or above <paramref name="level"/>; null when there are none.</summary>
    private static (int R, int G, int B)? PaperTone(RgbaImage image, byte[] gray, int level)
    {
        int w = image.Width, h = image.Height;
        int from = (int)(h * PaperRowsFrom), to = (int)(h * PaperRowsTo);
        long sumR = 0, sumG = 0, sumB = 0;
        int count = 0;
        for (int y = from; y < Math.Max(from + 1, to); y++)
        {
            for (int x = 0; x < w; x++)
            {
                if (gray[y * w + x] < level) continue;
                int i = (y * w + x) * 4;
                sumR += image.Pixels[i];
                sumG += image.Pixels[i + 1];
                sumB += image.Pixels[i + 2];
                count++;
            }
        }
        if (count == 0) return null;
        return ((int)(sumR / count), (int)(sumG / count), (int)(sumB / count));
    }

    /// <summary>
    /// The row of the page's top edge in every column (or of its bottom edge, <paramref name="fromTop"/> false):
    /// the first of <see cref="EdgeRun"/> rows in a row that are paper, looked for within
    /// <paramref name="depth"/> rows of the border, where a row is paper when the mean of the
    /// 2 x <see cref="EdgeHalfWidth"/> + 1 columns around it reaches <paramref name="threshold"/>. Columns
    /// with no such row take the nearest column's that has one; null when fewer than
    /// <see cref="MinFoundShare"/> do, or when the edge jumps by more than <see cref="MaxEdgeStepShare"/> of
    /// the height between neighbouring columns that have one.
    /// </summary>
    private static double[]? Edges(byte[] gray, int w, int h, double threshold, int depth, bool fromTop)
    {
        var found = new int[w];
        Array.Fill(found, -1);
        int foundCount = 0;
        for (int x = 0; x < w; x++)
        {
            int c0 = Math.Max(0, x - EdgeHalfWidth), c1 = Math.Min(w - 1, x + EdgeHalfWidth);
            double need = threshold * (c1 - c0 + 1);
            int run = 0;
            for (int step = 0; step < depth; step++)
            {
                int y = fromTop ? step : h - 1 - step;
                int sum = 0;
                for (int c = c0; c <= c1; c++) sum += gray[y * w + c];
                if (sum >= need)
                {
                    run++;
                    if (run == EdgeRun)
                    {
                        found[x] = fromTop ? y - (EdgeRun - 1) : y + (EdgeRun - 1);
                        foundCount++;
                        break;
                    }
                }
                else
                {
                    run = 0;
                }
            }
        }
        if (foundCount < w * MinFoundShare) return null;
        double maxStep = h * MaxEdgeStepShare;
        int last = -1;
        for (int x = 0; x < w; x++)
        {
            if (found[x] < 0) continue;
            if (last >= 0 && Math.Abs((double)(found[x] - found[last])) > maxStep) return null;
            last = x;
        }
        var result = new double[w];
        int previous = -1;
        for (int x = 0; x < w; x++)
        {
            if (found[x] < 0) continue;
            if (previous < 0)
            {
                for (int k = 0; k < x; k++) result[k] = found[x];
            }
            else
            {
                int gap = x - previous;
                for (int k = previous + 1; k < x; k++)
                {
                    double share = (double)(k - previous) / gap;
                    result[k] = found[previous] + share * (found[x] - found[previous]);
                }
            }
            result[x] = found[x];
            previous = x;
        }
        for (int k = previous + 1; k < w; k++) result[k] = found[previous];
        return result;
    }

    /// <summary><paramref name="values"/> with a median over 2 x <paramref name="half"/> + 1 columns (specks of text, a finger), then a mean over the same.</summary>
    private static double[] Smoothed(double[] values, int half)
    {
        int n = values.Length;
        var middle = new double[n];
        for (int x = 0; x < n; x++)
        {
            int from = Math.Max(0, x - half), to = Math.Min(n - 1, x + half);
            var window = values[from..(to + 1)];
            Array.Sort(window);
            middle[x] = window[window.Length / 2];
        }
        var result = new double[n];
        for (int x = 0; x < n; x++)
        {
            int from = Math.Max(0, x - half), to = Math.Min(n - 1, x + half);
            double sum = 0;
            for (int k = from; k <= to; k++) sum += middle[k];
            result[x] = sum / (to - from + 1);
        }
        return result;
    }
}

/// <summary>
/// Draws the page of a book taken by a camera flat (<see cref="PageFlatten.Flatten"/>), right after
/// <see cref="PerspectiveStep"/>; the photo stays the other version. Once only, as <see cref="EnhanceStep"/>:
/// pages not cut out along their corners, pages already cleaned up or filtered, and pages with edges that
/// are not found or are straight stay as they are.
/// </summary>
public sealed class FlattenStep : IPageStep
{
    public string Name => "flatten";

    public ScannedPage Apply(ScannedPage page)
    {
        if (page.Capture is not { Scale: not null, Enhancement: null, Filter: null } capture
            || page.Geometry?.Basis != GeometryBasis.Perspective
            || PageFlatten.Flatten(page.Image) is not { } flat) return page;
        return page.WithImage(flat).WithCapture(capture with { Flattened = true });
    }
}

/// <summary>
/// Paints the fingers at the margins of a camera's page with paper (<see cref="PageFlatten.FillFingers"/>);
/// runs where <see cref="FlattenStep"/> does, with the same conditions.
/// </summary>
public sealed class FingerFillStep : IPageStep
{
    public string Name => "fingers";

    public ScannedPage Apply(ScannedPage page)
    {
        if (page.Capture is not { Scale: not null, Enhancement: null, Filter: null } capture
            || page.Geometry?.Basis != GeometryBasis.Perspective
            || PageFlatten.FillFingers(page.Image, page.Dpi) is not { } filled) return page;
        return page.WithImage(filled).WithCapture(capture with { FingersFilled = true });
    }
}
