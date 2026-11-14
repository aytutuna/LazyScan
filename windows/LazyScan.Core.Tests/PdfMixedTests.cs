using System.Security.Cryptography;
using System.Text;
using LazyScan.Core;
using UglyToad.PdfPig;
using Xunit;

namespace LazyScan.Core.Tests;

// Color pages at Compact and Smallest as a text mask over a background. The Mac's twin is
// Tests/LazyScanTests/PDFMixedTests.swift (the same page, the same numbers).

public class PdfMixedTests
{
    private const int Width = 240, Height = 320;

    private static RgbaImage Page() => EnhancerPages.Shadowed(Width, Height, stamp: false, picture: false);

    private static string Latin1(byte[] data) => Encoding.Latin1.GetString(data);

    /// <summary>Pixels with no paper level to speak of: every luma value in turn, so almost all of the page is ink.</summary>
    private static RgbaImage Noise()
    {
        var pixels = new byte[Width * Height * 4];
        for (int p = 0; p < Width * Height; p++)
        {
            byte v = (byte)((p * 37 + p / Width * 91) % 256);
            pixels[p * 4] = pixels[p * 4 + 1] = pixels[p * 4 + 2] = v;
            pixels[p * 4 + 3] = 255;
        }
        return new RgbaImage(Width, Height, pixels);
    }

    private static PdfMixedImage Mixed(RgbaImage image, out byte[] g4)
    {
        var split = PdfImageEncoding.SplitPage(image, 300, ColorMode.Color, PdfSizePreset.Smallest)!.Value;
        g4 = split.G4;
        return new PdfMixedImage(PdfBuilderTests.TinyJpeg, new PdfCcittImage(split.G4, split.Split.Width, split.Split.Height));
    }

    [Fact]
    public void OnlyCompactAndSmallestKeepATextMask()
    {
        foreach (var size in Enum.GetValues<PdfSizePreset>())
        {
            bool expected = size is PdfSizePreset.Compact or PdfSizePreset.Smallest;
            Assert.Equal(expected, PdfImageEncoding.Profile(size).TextMask);
        }
    }

    [Fact]
    public void ASplitColorPageIsTheTextSplitWithItsMaskAsG4()
    {
        var image = Page();
        var split = PdfImageEncoding.SplitPage(image, 300, ColorMode.Color, PdfSizePreset.Smallest)!.Value;
        var direct = TextSplit.Split(image, 300);
        Assert.Equal(direct.Mask, split.Split.Mask);
        Assert.Equal(direct.Background.Pixels, split.Split.Background.Pixels);
        Assert.Equal(CcittG4Encoder.Encode(direct.Mask, Width, Height), split.G4);
        Assert.InRange(split.G4.Length, 1, Width * Height / 80);
    }

    [Fact]
    public void AFinePageIsSplitAtTheBlackAndWhiteLimit()
    {
        var image = Page();
        var split = PdfImageEncoding.SplitPage(image, 600, ColorMode.Color, PdfSizePreset.Compact)!.Value;
        Assert.Equal(120, split.Split.Width);
        Assert.Equal(160, split.Split.Height);
        Assert.Equal(40, split.Split.Background.Width);
    }

    [Theory]
    [InlineData(PdfSizePreset.Best, ColorMode.Color)]
    [InlineData(PdfSizePreset.Standard, ColorMode.Color)]
    [InlineData(PdfSizePreset.Smallest, ColorMode.Grayscale)]
    [InlineData(PdfSizePreset.Smallest, ColorMode.BlackWhite)]
    [InlineData(PdfSizePreset.Compact, ColorMode.Grayscale)]
    public void OtherPagesAreNotSplit(PdfSizePreset size, ColorMode mode) =>
        Assert.Null(PdfImageEncoding.SplitPage(Page(), 300, mode, size));

    [Fact]
    public void APageThatIsNotTextIsNotSplit() =>
        Assert.Null(PdfImageEncoding.SplitPage(Noise(), 300, ColorMode.Color, PdfSizePreset.Smallest));

    [Fact]
    public void APageWithColoredInkIsNotSplit() =>
        Assert.Null(PdfImageEncoding.SplitPage(EnhancerPages.Shadowed(Width, Height, stamp: true, picture: false),
                                               300, ColorMode.Color, PdfSizePreset.Smallest));

    [Fact]
    public void Pdf_MixedPage_DrawsTheMaskInBlackOverTheBackground()
    {
        var image = Mixed(Page(), out var g4);
        byte[] pdf = PdfBuilder.Make([new PdfPageInput(image, Width, Height, 300, null)]);
        string text = Latin1(pdf);
        // Catalog, pages, info, then the page, its image and contents; the mask comes after the pages.
        Assert.Contains("/Resources <</XObject <</Im0 5 0 R /Mk0 7 0 R>>>>", text);
        Assert.Contains($"7 0 obj\n<</Type /XObject /Subtype /Image /Width {Width} /Height {Height} /ImageMask true " +
                        "/BitsPerComponent 1 /Filter /CCITTFaxDecode " +
                        $"/DecodeParms <</K -1 /Columns {Width} /Rows {Height} /BlackIs1 false>> /Length {g4.Length}>>\nstream\n", text);
        Assert.Contains("/Im0 Do\n0 g\n/Mk0 Do\nQ\n", text);
        Assert.Contains("/ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /DCTDecode", text);
        int start = text.IndexOf("/ImageMask", StringComparison.Ordinal);
        int data = text.IndexOf("stream\n", start, StringComparison.Ordinal) + "stream\n".Length;
        Assert.True(pdf.AsSpan(data, g4.Length).SequenceEqual(g4));
        using var document = PdfDocument.Open(pdf, new ParsingOptions { UseLenientParsing = false });
        Assert.Equal(1, document.NumberOfPages);
    }

    [Fact]
    public void Pdf_MixedPages_NumberTheirMasksInPageOrder()
    {
        var mixed = Mixed(Page(), out _);
        byte[] pdf = PdfBuilder.Make(
        [
            new PdfPageInput(mixed, Width, Height, 300, null),
            new PdfPageInput(PdfBuilderTests.TinyJpeg, 100, 150, 300, null),
            new PdfPageInput(mixed, Width, Height, 300, null),
        ]);
        string text = Latin1(pdf);
        Assert.Contains("/XObject <</Im0 5 0 R /Mk0 13 0 R>>", text);
        Assert.Contains("/XObject <</Im1 8 0 R>>", text);
        Assert.Contains("/XObject <</Im2 11 0 R /Mk2 14 0 R>>", text);
        using var document = PdfDocument.Open(pdf, new ParsingOptions { UseLenientParsing = false });
        Assert.Equal(3, document.NumberOfPages);
    }

    [Fact]
    public void Pdf_PagesKeptInFiles_AreTheSameBytes()
    {
        var image = Mixed(Page(), out var g4);
        string folder = Path.Combine(Path.GetTempPath(), "lazyscan-test-" + Guid.NewGuid().ToString("N"));
        System.IO.Directory.CreateDirectory(folder);
        try
        {
            string background = Path.Combine(folder, "1"), mask = Path.Combine(folder, "1-mask");
            File.WriteAllBytes(background, PdfBuilderTests.TinyJpeg);
            File.WriteAllBytes(mask, g4);
            var inFiles = new PdfMixedImage(background, new PdfCcittImage(mask, Width, Height));
            var options = new PdfWriteOptions { CreationDate = new DateTimeOffset(2026, 10, 19, 21, 30, 5, TimeSpan.Zero), DocumentId = new byte[16] };
            Assert.Equal(PdfBuilder.Make([new PdfPageInput(image, Width, Height, 300, null)], options: options),
                         PdfBuilder.Make([new PdfPageInput(inFiles, Width, Height, 300, null)], options: options));
        }
        finally
        {
            System.IO.Directory.Delete(folder, recursive: true);
        }
    }

    [Fact]
    public void PdfA_WithAMixedPage_KeepsItsStructure()
    {
        var image = Mixed(Page(), out _);
        var options = new PdfWriteOptions { Conformance = PdfConformance.PdfA2b, Title = "Karma sayfa",
                                            CreationDate = new DateTimeOffset(2026, 10, 20, 9, 30, 0, TimeSpan.FromHours(3)),
                                            DocumentId = new byte[16] };
        byte[] pdf = PdfBuilder.Make([new PdfPageInput(image, Width, Height, 300, null)], options: options);
        string text = Latin1(pdf);
        Assert.StartsWith("%PDF-1.7", text);
        Assert.Contains("/OutputIntents", text);
        Assert.Contains("/ImageMask true", text);
        using var document = PdfDocument.Open(pdf, new ParsingOptions { UseLenientParsing = false });
        Assert.Equal(1, document.NumberOfPages);
    }

    [Fact]
    public void Protected_MixedPage_OpensWithThePassword()
    {
        var image = Mixed(Page(), out _);
        using var protection = new PdfProtection("Şifre 2026");
        byte[] pdf = PdfBuilder.Make([new PdfPageInput(image, Width, Height, 300, null)],
                                     options: new PdfWriteOptions { Protection = protection });
        using var document = PdfDocument.Open(pdf, new ParsingOptions { Password = "Şifre 2026" });
        Assert.True(document.IsEncrypted);
        Assert.Equal(1, document.NumberOfPages);
    }

    [Fact]
    public void Appended_MixedPage_IsReadBack()
    {
        var image = Mixed(Page(), out _);
        byte[] original = PdfBuilder.Make([new PdfPageInput(PdfBuilderTests.TinyJpeg, 850, 1100, 100, null)]);
        byte[] appended = PdfAppender.Append(original, [new PdfPageInput(image, Width, Height, 300, null)]);
        Assert.True(appended.AsSpan(0, original.Length).SequenceEqual(original));
        Assert.Contains("/ImageMask true", Latin1(appended[original.Length..]));
        using var document = PdfDocument.Open(appended, new ParsingOptions { UseLenientParsing = false });
        Assert.Equal(2, document.NumberOfPages);
    }

    [Fact]
    public void Pdf_MixedPage_GoldenBytes()
    {
        // The Mac's twin (PDFMixedTests) must write the same bytes.
        var image = Mixed(Page(), out _);
        byte[] pdf = PdfBuilder.Make(
        [
            new PdfPageInput(image, Width, Height, 300, null),
            new PdfPageInput(PdfBuilderTests.TinyJpeg, 850, 1100, 100, null),
        ], options: new PdfWriteOptions { Title = "Karma sayfa", CreationDate = new DateTimeOffset(2026, 10, 19, 21, 30, 5, TimeSpan.FromHours(3)), DocumentId = [.. Enumerable.Range(0xA0, 16).Select(i => (byte)i)] });
        Assert.Equal(2565, pdf.Length);
        Assert.Equal("0105040C139E7FF70AE916665FCA3BEC0EF19469395D8FB2F716C8FE5D92F3E3", Convert.ToHexString(SHA256.HashData(pdf)));
    }
}
