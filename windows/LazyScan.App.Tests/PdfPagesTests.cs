using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using LazyScan.App.Services;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

// A PDF's pages drawn for import with Windows.Data.Pdf: the resolution, the refusal of a protected
// file and of one that is no PDF. The shared rules are PhotoImportTests in both Core suites; the
// Mac draws with PDFKit (App/MacPDFPages.swift).
public class PdfPagesTests
{
    /// <summary>A letter-size page (612 × 792 points) holding a gray JPEG.</summary>
    private static PdfPageInput Letter()
    {
        var gray = new byte[612 * 792];
        Array.Fill(gray, (byte)200);
        var source = BitmapSource.Create(612, 792, 72, 72, PixelFormats.Gray8, null, gray, 612);
        var encoder = new JpegBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(source));
        using var stream = new MemoryStream();
        encoder.Save(stream);
        return new PdfPageInput(stream.ToArray(), 612, 792, 72, null);
    }

    [Fact]
    public async Task PagesAreDrawnAt300DpiAsPhotoPages()
    {
        byte[] pdf = PdfBuilder.Make([Letter(), Letter()]);
        using var pages = await PdfPages.OpenAsync(pdf, "two.pdf");
        Assert.Equal(2, pages.PageCount);
        var page = await pages.RenderAsync(1);
        Assert.Equal(300, page.Dpi);
        Assert.InRange(page.Image.Width, 2548, 2552);
        Assert.InRange(page.Image.Height, 3298, 3302);
        Assert.Equal(PageSource.Photo, page.Source);
    }

    [Fact]
    public async Task AProtectedPdfIsRefusedWithTheReason()
    {
        byte[] pdf = PdfBuilder.Make([Letter()], options: new PdfWriteOptions { Protection = new PdfProtection("secret") });
        var refused = await Assert.ThrowsAsync<PhotoUnreadableException>(() => PdfPages.OpenAsync(pdf, "locked.pdf"));
        Assert.Equal(PhotoImport.UnreadableMessage("locked.pdf", PhotoImport.LockedDetail), refused.Message);
    }

    [Fact]
    public async Task AFileThatIsNoPdfIsRefusedAsUnreadable()
    {
        var refused = await Assert.ThrowsAsync<PhotoUnreadableException>(
            () => PdfPages.OpenAsync("not a pdf"u8.ToArray(), "broken.pdf"));
        Assert.Equal(PhotoImport.UnreadableMessage("broken.pdf", PhotoImport.UnreadableDetail), refused.Message);
    }
}
