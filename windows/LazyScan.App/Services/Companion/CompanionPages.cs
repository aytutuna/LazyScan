using System.Globalization;
using System.IO;
using LazyScan.App.Services;
using LazyScan.Core;

namespace LazyScan.App.Services.Companion;

/// <summary>
/// A document from a phone as pages of the queue: each picture decoded, turned by the rotation the
/// phone had still to apply, labelled "From phone" (<see cref="PageSource.Phone"/>), with its side
/// and sheet; a page that came with its picture as photographed keeps that as its other version, so
/// "Show as photographed" works as for an imported photo; what the phone's camera recorded about a page
/// (<see cref="ScannedPage.Capture"/>) comes with it. A document sent as a new one starts a
/// document of its own in the queue (a split before its first page, when pages are already queued)
/// and carries its name.
/// </summary>
public static class CompanionPages
{
    /// <param name="decode">Decodes a picture's bytes (JPEG, PNG or bilevel TIFF).</param>
    /// <param name="queueHasPages">Pages are queued already.</param>
    /// <param name="keep">Takes each page as soon as it is built and returns what to keep of it (a page
    /// spooled to disk, say), so a long document does not hold every picture in memory at once.</param>
    public static List<ScannedPage> ToScannedPages(CompanionDocument document, CompanionTarget target, bool queueHasPages,
                                                   Func<byte[], RgbaImage> decode, DateTime? createdAt = null,
                                                   Func<ScannedPage, ScannedPage>? keep = null)
    {
        var pages = new List<ScannedPage>(document.Pages.Count);
        DateTime created = createdAt ?? DateTime.Now;
        foreach (var source in document.Pages)
        {
            var image = Upright(decode(source.Image.Data), source.RotationQuarterTurns);
            var page = new ScannedPage(image, source.Image.Dpi, source.Image.ColorMode, createdAt: created)
            {
                Side = source.Side,
                SheetIndex = source.SheetIndex,
                Source = PageSource.Phone,
                Capture = source.Capture,
            };
            if (source.Original is { } original)
            {
                var photographed = new ScannedPage(Upright(decode(original.Data), source.RotationQuarterTurns),
                                                   source.Image.Dpi, source.Image.ColorMode, page.Id, created)
                {
                    Side = source.Side,
                    SheetIndex = source.SheetIndex,
                    Source = PageSource.Phone,
                    Capture = source.Capture,
                };
                page = photographed.WithGeometry(image, new PageGeometry(true, 0, GeometryBasis.Perspective));
            }
            pages.Add(keep is null ? page : keep(page));
        }
        if (pages.Count > 0 && target == CompanionTarget.New)
        {
            string name = DocumentName(document);
            var first = pages[0];
            if (queueHasPages) first = first.WithDocumentBreak(DocumentBreak.Split);
            if (name.Length > 0) first = first.WithDocumentLabel(name);
            pages[0] = first;
        }
        return pages;
    }

    /// <summary>The name the sender's document was given; "" for none.</summary>
    public static string DocumentName(CompanionDocument document) => (document.SuggestedName ?? "").Trim();

    /// <summary>
    /// The queue's pages as one document named <paramref name="name"/>, for a package: each page's
    /// picture as shown, at full resolution (<paramref name="load"/>, turned as the page is), a black
    /// &amp; white page as a bilevel TIFF and the others as a JPEG at <paramref name="jpegQuality"/>
    /// (a gray one as a gray JPEG), with its side, sheet and what the camera recorded. Document breaks
    /// and recognized text are not carried. With <paramref name="encodedFolder"/>, each encoded picture
    /// goes to a file there as soon as it is made and is read back when the package is written.
    /// </summary>
    public static CompanionDocument ToDocument(IReadOnlyList<ScannedPage> pages, string name, double jpegQuality,
                                               Func<ScannedPage, RgbaImage> load, string? encodedFolder = null)
    {
        var packaged = new List<CompanionPage>(pages.Count);
        foreach (var page in pages)
        {
            var image = load(page);
            bool bilevel = page.ColorMode == ColorMode.BlackWhite;
            byte[] encoded = bilevel
                ? BilevelTiff.Make(image, page.Dpi)
                : WpfImageCodec.EncodeJpeg(image, page.Dpi, jpegQuality, page.ColorMode == ColorMode.Grayscale);
            var format = bilevel ? CompanionImageFormat.Tiff : CompanionImageFormat.Jpeg;
            CompanionImage picture;
            if (encodedFolder is null)
            {
                picture = new CompanionImage(encoded, format, image.Width, image.Height, page.Dpi, page.ColorMode);
            }
            else
            {
                string file = Path.Combine(encodedFolder, (packaged.Count + 1).ToString(CultureInfo.InvariantCulture));
                File.WriteAllBytes(file, encoded);
                picture = new CompanionImage(file, format, image.Width, image.Height, page.Dpi, page.ColorMode);
            }
            packaged.Add(new CompanionPage(picture) { Side = page.Side, SheetIndex = page.SheetIndex, Capture = page.Capture });
        }
        return new CompanionDocument(name, packaged) { SuggestedName = DocumentSplitter.Cleaned(pages.FirstOrDefault()?.DocumentLabel) };
    }

    private static RgbaImage Upright(RgbaImage image, int quarterTurns) =>
        quarterTurns is > 0 and <= 3 ? image.RotatedQuarterTurns(quarterTurns) : image;
}
