using System.IO;
using LazyScan.Core;
using Windows.Data.Pdf;
using Windows.Storage.Streams;

namespace LazyScan.App.Services;

/// <summary>
/// The pages of a PDF drawn for import (<see cref="PhotoImport.IsPdf"/>) with Windows.Data.Pdf, one page at a
/// time: at <see cref="PhotoImport.PdfDpi"/> on white, or at the resolution that keeps the long side within
/// <see cref="PhotoImport.PdfMaxLongSide"/> pixels, recorded on the page so its paper size survives a save.
/// A password-protected PDF is refused (<see cref="PhotoImport.LockedDetail"/>). The Mac's twin is
/// App/MacPDFPages.swift (PDFKit).
/// </summary>
public sealed class PdfPages : IDisposable
{
    private readonly PdfDocument _document;
    private readonly IRandomAccessStream _source;
    private readonly string _fileName;

    private PdfPages(PdfDocument document, IRandomAccessStream source, string fileName)
    {
        _document = document;
        _source = source;
        _fileName = fileName;
    }

    /// <summary>How many pages the PDF has (at least 1).</summary>
    public int PageCount => (int)_document.PageCount;

    /// <summary>
    /// Opens the PDF in <paramref name="bytes"/>, named <paramref name="fileName"/> in the messages. Throws
    /// <see cref="PhotoUnreadableException"/> for a protected PDF, a damaged file or a PDF without pages.
    /// </summary>
    public static async Task<PdfPages> OpenAsync(byte[] bytes, string fileName)
    {
        // The document is read from memory, so it keeps no handle on the file.
        var source = System.IO.WindowsRuntimeStreamExtensions.AsRandomAccessStream(new MemoryStream(bytes));
        try
        {
            var document = await PdfDocument.LoadFromStreamAsync(source);
            if (document.PageCount == 0) throw Refused(fileName, PhotoImport.UnreadableDetail);
            return new PdfPages(document, source, fileName);
        }
        catch (Exception e) when (e is not PhotoUnreadableException)
        {
            source.Dispose();
            // The loader gives the same error for a protected file and a damaged one: the file's own
            // /Encrypt entry tells them apart.
            throw Refused(fileName, IsEncrypted(bytes) ? PhotoImport.LockedDetail : PhotoImport.UnreadableDetail, e);
        }
        catch
        {
            source.Dispose();
            throw;
        }
    }

    /// <summary>
    /// Page <paramref name="index"/> (from 0) as a page of the queue, labelled as a photo like the others
    /// imported. Throws <see cref="PhotoUnreadableException"/> when it cannot be drawn.
    /// </summary>
    public async Task<ScannedPage> RenderAsync(int index)
    {
        string shown = PhotoImport.PageName(_fileName, index + 1, PageCount);
        try
        {
            using var page = _document.GetPage((uint)index);
            double widthPoints = page.Size.Width * 72.0 / 96.0, heightPoints = page.Size.Height * 72.0 / 96.0;
            int dpi = PhotoImport.PdfResolution(widthPoints, heightPoints);
            double scale = await DisplayScaleAsync(page);
            uint width = (uint)Math.Max(1, Math.Round(widthPoints * dpi / 72.0 / scale));
            var bytes = await RenderToBytesAsync(page, width);
            var image = await Task.Run(() => WpfImageCodec.Decode(bytes));
            return new ScannedPage(image, dpi, ColorMode.Color) { Source = PageSource.Photo };
        }
        catch (Exception e) when (e is not PhotoUnreadableException and not OperationCanceledException)
        {
            throw Refused(shown, PhotoImport.UnreadableDetail, e);
        }
    }

    public void Dispose() => _source.Dispose();

    /// <summary>
    /// The renderer multiplies the width asked for by the display scale, so a small page is drawn first to
    /// learn it.
    /// </summary>
    private static async Task<double> DisplayScaleAsync(PdfPage page)
    {
        const uint probe = 100;
        using var drawn = new InMemoryRandomAccessStream();
        await page.RenderToStreamAsync(drawn, new PdfPageRenderOptions { DestinationWidth = probe });
        drawn.Seek(0);
        using var managed = System.IO.WindowsRuntimeStreamExtensions.AsStreamForRead(drawn);
        var decoder = System.Windows.Media.Imaging.BitmapDecoder.Create(
            managed, System.Windows.Media.Imaging.BitmapCreateOptions.None, System.Windows.Media.Imaging.BitmapCacheOption.OnLoad);
        return Math.Max(1, decoder.Frames[0].PixelWidth / (double)probe);
    }

    private static async Task<byte[]> RenderToBytesAsync(PdfPage page, uint width)
    {
        using var drawn = new InMemoryRandomAccessStream();
        await page.RenderToStreamAsync(drawn, new PdfPageRenderOptions { DestinationWidth = width });
        drawn.Seek(0);
        using var managed = System.IO.WindowsRuntimeStreamExtensions.AsStreamForRead(drawn);
        var buffer = new MemoryStream();
        await managed.CopyToAsync(buffer);
        return buffer.ToArray();
    }

    private static bool IsEncrypted(byte[] bytes)
    {
        try { using var reader = new PdfReaderLite(bytes); return reader.IsEncrypted; }
        catch (Exception e) when (e is not OutOfMemoryException) { return false; }
    }

    private static PhotoUnreadableException Refused(string name, string detail, Exception? inner = null) =>
        new(PhotoImport.UnreadableMessage(name, detail), inner);
}
