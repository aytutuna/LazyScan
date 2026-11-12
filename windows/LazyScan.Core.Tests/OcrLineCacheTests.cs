using LazyScan.Core;
using Xunit;

namespace LazyScan.Core.Tests;

public class OcrLineCacheTests
{
    private static ScannedPage Page() => new(RgbaImage.Filled(20, 10, 128, 128, 128), 300, ColorMode.Grayscale);

    private static readonly IReadOnlyList<OcrLine> Lines = [new OcrLine("Hello", new RectD(0, 0, 1, 0.1), 0.9f)];

    [Fact]
    public void KeepsLinesForTheSamePage()
    {
        var cache = new OcrLineCache();
        var page = Page();
        Assert.Null(cache.Get(page, ""));
        cache.Store(page, "", Lines);
        Assert.Equal(Lines, cache.Get(page, ""));
    }

    [Fact]
    public void KeepsLinesWhenOnlyPageFactsChange()
    {
        var cache = new OcrLineCache();
        var page = Page();
        cache.Store(page, "", Lines);
        var marked = page.CopyMeta(page);
        Assert.Equal(Lines, cache.Get(marked, ""));
    }

    [Fact]
    public void TurningAPageReadsItAgain()
    {
        var cache = new OcrLineCache();
        var page = Page();
        cache.Store(page, "", Lines);
        page.RotationQuarterTurns = 1;
        Assert.Null(cache.Get(page, ""));
        page.RotationQuarterTurns = 0;
        Assert.Equal(Lines, cache.Get(page, ""));
    }

    [Fact]
    public void OtherPixelsOrLanguageReadAgain()
    {
        var cache = new OcrLineCache();
        var page = Page();
        cache.Store(page, "en-US", Lines);
        Assert.Null(cache.Get(page, "de-DE"));
        Assert.Null(cache.Get(page.WithImage(RgbaImage.Filled(20, 10, 0, 0, 0)), "en-US"));
    }

    [Fact]
    public void OtherPagesAreNotAffected()
    {
        var cache = new OcrLineCache();
        var first = Page();
        var second = Page();
        cache.Store(first, "", Lines);
        Assert.Null(cache.Get(second, ""));
    }

    [Fact]
    public void ARerunReadsOnlyThePagesAnInterruptedPassDidNot()
    {
        var cache = new OcrLineCache();
        var pages = Enumerable.Range(0, 30).Select(_ => Page()).ToList();
        int reads = 0;
        void Pass(int stopAt)
        {
            for (int i = 0; i < stopAt; i++)
            {
                if (cache.Get(pages[i], "") is not null) continue;
                reads++;
                cache.Store(pages[i], "", Lines);
            }
        }
        Pass(20);
        Assert.Equal(20, reads);
        Pass(30);
        Assert.Equal(30, reads);
    }
}
