using System.Text;

namespace LazyScan.Core;

// Twin of Sources/LazyScanKit/Output/TextExport.swift: the same bytes and the same messages.

/// <summary>
/// The text file of a save (<see cref="OutputFormat.Text"/>, or the text beside a PDF with
/// <see cref="OutputOptions.AlsoSaveText"/>), and what the app says about text it saved or could
/// not read. The text is <see cref="OcrText.PlainText"/>: UTF-8 without a byte order mark, "\n"
/// line breaks, one line of text per line on the page, a blank line between paragraphs and two
/// between pages.
/// </summary>
public static class TextExport
{
    private static readonly UTF8Encoding Utf8NoBom = new(encoderShouldEmitUTF8Identifier: false);

    /// <summary>The bytes of the text file for <paramref name="pages"/>.</summary>
    public static byte[] Encode(IReadOnlyList<OcrPage> pages) => Utf8NoBom.GetBytes(OcrText.PlainText(pages));

    /// <summary>Whether any page has text to save.</summary>
    public static bool HasText(IReadOnlyList<OcrPage> pages) => OcrText.PlainText(pages).Length > 0;

    /// <summary>
    /// "Saved 3-page Word document: Scan 1.docx", "Saved 1-page text file: Scan 1.txt", with
    /// " — no text was found" when the pages had none (the file is saved all the same).
    /// </summary>
    public static string SavedMessage(OutputFormat format, int pageCount, string fileName, bool hasText)
    {
        if (format == OutputFormat.Word)
        {
            return hasText ? Loc.T("Saved {0}-page Word document: {1}", pageCount, fileName)
                : Loc.T("Saved {0}-page Word document: {1} — no text was found", pageCount, fileName);
        }
        return hasText ? Loc.T("Saved {0}-page text file: {1}", pageCount, fileName)
            : Loc.T("Saved {0}-page text file: {1} — no text was found", pageCount, fileName);
    }

    /// <summary>"Saved 3-page TIFF: Scan 1.tiff": the status after the queue is saved as one TIFF.</summary>
    public static string SavedTiffMessage(int pageCount, string fileName) =>
        Loc.T("Saved {0}-page TIFF: {1}", pageCount, fileName);

    /// <summary>
    /// "Saved 3-page PDF: Scan 1.pdf (412 KB) and its text, Scan 1.txt": the status after a PDF is saved.
    /// <paramref name="detail"/> is what goes in brackets after the name (the size, password-protected),
    /// <paramref name="textFileName"/> the text saved beside the PDF; each may be null.
    /// </summary>
    public static string SavedPdfMessage(int pageCount, string fileName, string? detail, string? textFileName) =>
        (detail, textFileName) switch
        {
            (not null, not null) => Loc.Plural(pageCount, "Saved {0}-page PDF: {1} ({2}) and its text, {3}",
                                               "Saved {0}-page PDF: {1} ({2}) and its text, {3}", fileName, detail, textFileName),
            (not null, null) => Loc.Plural(pageCount, "Saved {0}-page PDF: {1} ({2})", "Saved {0}-page PDF: {1} ({2})", fileName, detail),
            (null, not null) => Loc.Plural(pageCount, "Saved {0}-page PDF: {1} and its text, {2}",
                                           "Saved {0}-page PDF: {1} and its text, {2}", fileName, textFileName),
            _ => Loc.Plural(pageCount, "Saved {0}-page PDF: {1}", "Saved {0}-page PDF: {1}", fileName),
        };

    /// <summary>
    /// "Saved Scan 1.pdf (412 KB) and its text, Scan 1.txt", or "Saved A.jpg, B.jpg": the status after a
    /// save at once. <paramref name="fileNames"/> is the names joined; the others as in <see cref="SavedPdfMessage"/>.
    /// </summary>
    public static string SavedFilesMessage(string fileNames, string? detail, string? textFileName) =>
        (detail, textFileName) switch
        {
            (not null, not null) => Loc.T("Saved {0} ({1}) and its text, {2}", fileNames, detail, textFileName),
            (not null, null) => Loc.T("Saved {0} ({1})", fileNames, detail),
            (null, not null) => Loc.T("Saved {0} and its text, {1}", fileNames, textFileName),
            _ => Loc.T("Saved {0}", fileNames),
        };

    /// <summary>
    /// What the user reads when the text could not be read: "The text could not be read: no OCR
    /// language pack is installed (…)." from the OCR error's message ("Scan failed: no OCR language …").
    /// </summary>
    public static string RecognitionFailed(string ocrMessage) => Loc.T("The text could not be read: {0}", Reason(ocrMessage));

    /// <summary>
    /// "The PDF was saved, but not its text file: …": the text beside a PDF could not be read or
    /// written (<paramref name="message"/>, an OCR or file error); the PDF is kept.
    /// </summary>
    public static string SidecarFailed(string message) => Loc.T("The PDF was saved, but not its text file: {0}", Reason(message));

    /// <summary>
    /// "The PDF was saved, but the text of 2 pages could not be read: …": the OCR of some pages of a
    /// searchable PDF failed and they were saved without text (<paramref name="message"/> is the first
    /// OCR error's).
    /// </summary>
    public static string LayerLost(int pageCount, string message) =>
        Loc.Plural(pageCount, "The PDF was saved, but the text of {0} page could not be read: {1}",
                   "The PDF was saved, but the text of {0} pages could not be read: {1}", Reason(message));

    /// <summary>
    /// What the user reads when a scan to be saved at once as Word or text could not be (its text
    /// could not be read, its file could not be written, or the save was cancelled) and its pages
    /// went to the queue instead: "The 3 pages are kept in the queue: press Save Word once the text
    /// can be read, or choose PDF to save them as scanned." when <paramref name="textUnreadable"/>
    /// (OCR failed), "… press Save Word to try again, or choose PDF …" for any other failure, or
    /// "Cancelled — the page is kept in the queue.".
    /// </summary>
    public static string KeptInQueue(OutputFormat format, int pageCount, bool cancelled, bool textUnreadable = true)
    {
        if (cancelled) return CancelledInQueue(pageCount);
        string saveTitle = OutputFormats.SaveTitle(format);
        if (textUnreadable)
        {
            return Loc.Plural(pageCount,
                "The page is kept in the queue: press {1} once the text can be read, or choose PDF to save it as scanned.",
                "The {0} pages are kept in the queue: press {1} once the text can be read, or choose PDF to save them as scanned.",
                saveTitle);
        }
        return Loc.Plural(pageCount,
            "The page is kept in the queue: press {1} to try again, or choose PDF to save it as scanned.",
            "The {0} pages are kept in the queue: press {1} to try again, or choose PDF to save them as scanned.",
            saveTitle);
    }

    /// <summary>
    /// What the user reads when a PDF or pictures to be saved at once could not be written, or the
    /// save was cancelled, and the pages not written went to the queue: "Not saved — the 3 pages are
    /// kept in the queue: press Save PDF to try again." or "Cancelled — the page is kept in the
    /// queue."; with <paramref name="written"/> of the <paramref name="pageCount"/> pictures saved,
    /// "Pages saved: 2 of 5. The other 3 are kept in the queue: press Save PDF to try again." or
    /// "Cancelled. Pages saved: 2 of 5. The other 3 are kept in the queue.".
    /// <paramref name="saveTitle"/> is the button that saves them.
    /// </summary>
    public static string PagesKeptInQueue(int pageCount, int written, bool cancelled, string saveTitle)
    {
        if (written == 0)
        {
            if (cancelled) return CancelledInQueue(pageCount);
            return Loc.Plural(pageCount,
                "Not saved — the page is kept in the queue: press {1} to try again.",
                "Not saved — the {0} pages are kept in the queue: press {1} to try again.",
                saveTitle);
        }
        int rest = pageCount - written;
        if (cancelled)
        {
            return Loc.Plural(rest,
                "Cancelled. Pages saved: {1} of {2}. The other one is kept in the queue.",
                "Cancelled. Pages saved: {1} of {2}. The other {0} are kept in the queue.",
                written, pageCount);
        }
        return Loc.Plural(rest,
            "Pages saved: {1} of {2}. The other one is kept in the queue: press {3} to try again.",
            "Pages saved: {1} of {2}. The other {0} are kept in the queue: press {3} to try again.",
            written, pageCount, saveTitle);
    }

    private static string CancelledInQueue(int pageCount) =>
        Loc.Plural(pageCount,
            "Cancelled — the page is kept in the queue.",
            "Cancelled — the {0} pages are kept in the queue.");

    /// <summary>An error's message without the "Scan failed: " it starts with, ending in a full stop.</summary>
    private static string Reason(string message)
    {
        string reason = Loc.Bare(message).Trim();
        string prefix = Loc.Bare(Loc.T("Scan failed: {0}", ""));
        if (reason.StartsWith(prefix, StringComparison.Ordinal)) reason = reason[prefix.Length..];
        if (reason.Length == 0) reason = Loc.T("the text recognition did not work");
        if (!reason.EndsWith('.')) reason += ".";
        return reason;
    }

    /// <summary>
    /// "Copied the text of page 2." or "No text was found on page 2." after Copy Text;
    /// <paramref name="pageNumber"/> counts from 1.
    /// </summary>
    public static string CopiedMessage(int pageNumber, bool hasText) =>
        hasText ? Loc.T("Copied the text of page {0}.", pageNumber) : Loc.T("No text was found on page {0}.", pageNumber);

    /// <summary>
    /// Write <paramref name="content"/> to a hidden temporary file next to <paramref name="path"/>
    /// and move it into place without ever replacing a file: when the name is taken, the next free
    /// " 2", " 3", … name is used (<see cref="NamingTemplate.MoveToFreePath"/>), as for PDFs.
    /// Returns the path written.
    /// </summary>
    public static string WriteNewFile(byte[] content, string path)
    {
        string directory = Path.GetDirectoryName(Path.GetFullPath(path))!;
        string extension = Path.GetExtension(path).TrimStart('.');
        string tmp = Path.Combine(directory, $".{Guid.NewGuid()}.{extension}.tmp");
        try
        {
            using (var stream = File.Create(tmp))
            {
                PdfBuilder.SetHidden(tmp, true);
                stream.Write(content);
            }
            PdfBuilder.SetHidden(tmp, false);
            string written = NamingTemplate.MoveToFreePath(tmp, path);
            PdfBuilder.SetHidden(written, false);
            return written;
        }
        catch (Exception e)
        {
            try { File.Delete(tmp); } catch { /* best effort */ }
            if (e is IOException or UnauthorizedAccessException) throw ScanException.ExportFailed(SaveErrors.Describe(e, directory));
            throw;
        }
    }
}
