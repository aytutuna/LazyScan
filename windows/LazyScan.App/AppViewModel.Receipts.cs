using System.Globalization;
using System.IO;
using LazyScan.App.Services;
using LazyScan.Core;

namespace LazyScan.App;

/// <summary>
/// The Receipts task: the receipts on a scan are found (<see cref="ReceiptDetector"/>), cut out,
/// straightened and made easy to read (<see cref="ReceiptEnhancer"/>), reviewed in the photo review,
/// then saved: each one's text is read once with OCR as the review opens for its date (the file
/// name's {docdate}, which the review shows and lets the user correct), the PDF's text layer and the
/// text beside it, and the receipts are written as a file each or as one PDF, all or nothing. Twin
/// of the Mac's AppState+Receipts.swift.
/// </summary>
public sealed partial class AppViewModel
{
    /// <summary>The scans of the settings are receipts (the Receipts task).</summary>
    public bool IsReceiptFlow => TaskCatalog.FlowOf(Settings) == TaskFlowKind.ReceiptSplit;

    /// <summary>The review holds receipts rather than photos: it is titled and saved as receipts.</summary>
    public bool IsReceiptReview { get; private set; }

    /// <summary>The review's title: "Found 3 receipts", or for photos "Found 3 photos".</summary>
    public string ReviewTitle => IsReceiptReview
        ? Receipts.ReviewTitle(DetectedPhotos.Count)
        : PhotoReview.Title(DetectedPhotos.Count);

    /// <summary>The review's save button: "Save 2 Receipts", "Save as One PDF", "Save 3 photos".</summary>
    public string ReviewSaveTitle
    {
        get
        {
            int included = DetectedPhotos.Count(p => p.Photo.Included);
            return IsReceiptReview
                ? Receipts.SaveTitle(included, Settings.TaskOptions.ReceiptCombine, Settings.Format)
                : PhotoReview.SaveTitle(included);
        }
    }

    public void SetReceiptNameByDate(bool byDate)
    {
        if (Settings.TaskOptions.ReceiptNameByDate == byDate) return;
        Settings.TaskOptions.ReceiptNameByDate = byDate;
        SettingsEdited();
        NotifyAll();
    }

    public void SetReceiptCombine(bool combine)
    {
        if (Settings.TaskOptions.ReceiptCombine == combine) return;
        Settings.TaskOptions.ReceiptCombine = combine;
        SettingsEdited();
        NotifyAll();
    }

    /// <summary>
    /// The receipts on one scanned page, cut out, upright and cleaned up: several on the glass, the
    /// whole sheet as one from the feeder; the whole page when nothing looks like a receipt. Each one is
    /// given the quarter turns that read upright (<see cref="Receipts.UprightTurns"/>) as its rotation in
    /// the review.
    /// </summary>
    private List<DetectedPhoto> SplitReceipts(ScannedPage page, ScanSettings s, CancellationToken token)
    {
        var options = new ReceiptDetectorOptions { SingleReceipt = s.Source == ScanSource.DocumentFeeder };
        var regions = ReceiptDetector.DetectRegions(page.Image, page.Dpi, options);
        if (regions.Count == 0)
        {
            double w = page.Image.Width, h = page.Image.Height;
            regions = [new DetectedPhotoRegion(new PointD(w / 2, h / 2), new SizeD(w, h), 0)];
        }
        var receipts = new List<DetectedPhoto>();
        foreach (var region in regions)
        {
            token.ThrowIfCancellationRequested();
            if (ReceiptDetector.ExtractEnhanced(page.Image, region, page.Dpi) is { } image)
            {
                receipts.Add(new DetectedPhoto(region, image, page.Dpi, sourcePageId: page.Id)
                {
                    RotationQuarterTurns = Receipts.UprightTurns(image, page.Dpi, _orientation, token),
                });
            }
        }
        return receipts;
    }

    /// <summary>Opens the review on the receipts found on the pages just scanned.</summary>
    private async Task ShowReceipts(List<ScannedPage> processed, ScanSettings s, int generation, CancellationToken token)
    {
        StatusMessage = Loc.T("Finding receipts…");
        NotifyAll();
        bool byDate = Receipts.NamesByDate(s);
        var found = await Task.Run(() =>
        {
            var all = new List<PhotoItem>();
            foreach (var page in processed)
            {
                token.ThrowIfCancellationRequested();
                all.AddRange(SplitReceipts(page, s, token).Select(p => new PhotoItem(p) { DatesShown = byDate }));
            }
            return all;
        }, token);
        if (_switchGeneration != generation) return;
        token.ThrowIfCancellationRequested();
        // Every page's full-resolution scan stays while the review is open, for Fix crop.
        _photoSourceImages = processed.ToDictionary(p => p.Id, p => p.Image);
        PhotoItem.Renumber(found);
        DetectedPhotos = new System.Collections.ObjectModel.ObservableCollection<PhotoItem>(found);
        IsReceiptReview = true;
        RecordCaptures(found.Select(item => item.Photo.Id));
        ShowPhotoReview = found.Count > 0;
        if (!ShowPhotoReview) _photoSourceImages = [];
        SetStatus(Loc.Plural(found.Count, "Found {0} receipt.", "Found {0} receipts."), new(new StatusHead.Found(found.Count, FileKind.Receipt)));
        if (byDate) foreach (var item in found) ReadReceiptDate(item);
    }

    private Task _receiptReads = Task.CompletedTask;

    /// <summary>A receipt is turned in the review: its text and date are read again from the new image.</summary>
    public void RotateReviewPhoto(PhotoItem item)
    {
        item.RotateClockwise();
        if (item.DatesShown) ReadReceiptDate(item);
    }

    /// <summary>
    /// The text of <paramref name="turned"/>, a receipt turned <paramref name="turns"/> quarter turns, and the
    /// date found in it when <paramref name="byDate"/>. A receipt whose text cannot be read is still saved:
    /// without a text layer, named by the scan date.
    /// </summary>
    private async Task<ReceiptReading> ReadReceipt(RgbaImage turned, int turns, bool byDate, bool dayFirst,
                                                   IReadOnlyList<string>? languages, CancellationToken token)
    {
        try
        {
            var lines = await _ocrService.RecognizeLinesAsync(turned, languages).WaitAsync(token);
            var date = byDate
                ? ReceiptDateExtractor.FindDate(Receipts.TextLines(lines, turned.Width, turned.Height), DocumentDate.Of(DateTime.Now), dayFirst)
                : null;
            return new ReceiptReading(turns, lines, null, date);
        }
        catch (Exception e) when (!token.IsCancellationRequested)
        {
            return new ReceiptReading(turns, null, e.Message, null);
        }
    }

    /// <summary>
    /// Reads a receipt's text and the date in it in the background, one receipt after another, so the
    /// review shows the date and Save does not read the text again. A date the user typed is kept.
    /// </summary>
    private void ReadReceiptDate(PhotoItem item)
    {
        var languages = OcrLanguages(Settings);
        bool dayFirst = ReceiptDateExtractor.PrefersDayFirst(CultureInfo.CurrentCulture.DateTimeFormat.ShortDatePattern);
        item.BeginReading();
        int generation = item.ReadGeneration;
        var previous = _receiptReads;
        _receiptReads = Settled(Run());
        NotifyAll();

        async Task Run()
        {
            await Settled(previous);
            // The receipt may have been turned, cropped again or discarded meanwhile.
            if (!DetectedPhotos.Contains(item) || item.ReadGeneration != generation) return;
            var photo = item.Photo;
            int turns = photo.RotationQuarterTurns;
            var reading = await Task.Run(async () =>
            {
                var image = turns == 0 ? photo.Image : ImagePipeline.Rotate(photo.Image, turns);
                return await ReadReceipt(image, turns, true, dayFirst, languages, CancellationToken.None);
            });
            if (!DetectedPhotos.Contains(item) || item.ReadGeneration != generation) return;
            item.EndReading(reading);
            NotifyAll();
        }
    }

    /// <summary>
    /// Saves the receipts kept in the review: each turned as shown, its text as the review read it, or
    /// read here with OCR when it is needed (<see cref="Receipts.ReadsText"/>) and was not; then a file
    /// each, or one PDF for all (<see cref="TaskOptions.ReceiptCombine"/>), named by the receipt's date
    /// as the review shows it ({docdate}; for one PDF the earliest), the scan date when it has none.
    /// All or nothing: a failed or cancelled save removes what it wrote and the review stays open.
    /// </summary>
    private Task SaveReceipts()
    {
        var s = Settings.Clone();
        var format = OutputFormats.PageFormat(s.Format);
        bool byDate = Receipts.NamesByDate(s);
        bool readsText = Receipts.ReadsText(s);
        bool dayFirst = ReceiptDateExtractor.PrefersDayFirst(CultureInfo.CurrentCulture.DateTimeFormat.ShortDatePattern);
        return RunExclusive(async token =>
        {
            // A crop correction applied just before saving must be in the files.
            await Settled(_recropChain);
            var items = DetectedPhotos.Where(p => p.Photo.Included).ToList();
            var receipts = items.Select(p => p.Photo).ToList();
            if (receipts.Count == 0) return;
            // Receipts still being read since the review opened are waited for, not read again.
            int pending = items.FindIndex(p => p.IsReading);
            if (pending >= 0)
            {
                StatusMessage = Loc.T("Reading receipt {0} of {1}…", pending + 1, items.Count);
                NotifyAll();
                await _receiptReads.WaitAsync(token);
            }
            // A protected PDF's password is asked for before the receipts are read.
            if (format == OutputFormat.Pdf) ProtectionFor(s);
            bool combine = Receipts.Combines(s.TaskOptions.ReceiptCombine, s.Format, receipts.Count);

            // 1. Each receipt as shown, its text read once (in the review, when it was read for the date).
            var images = new List<RgbaImage>();
            var lines = new List<IReadOnlyList<OcrLine>?>();
            var dates = new List<DocumentDate?>();
            string? ocrProblem = null;
            for (int i = 0; i < receipts.Count; i++)
            {
                token.ThrowIfCancellationRequested();
                var receipt = receipts[i];
                var image = await Task.Run(() => receipt.RotationQuarterTurns == 0
                    ? receipt.Image
                    : ImagePipeline.Rotate(receipt.Image, receipt.RotationQuarterTurns), token);
                images.Add(image);
                var reading = receipt.IsRead ? receipt.Reading : null;
                if (reading is null && readsText)
                {
                    StatusMessage = Loc.T("Reading receipt {0} of {1}…", i + 1, receipts.Count);
                    NotifyAll();
                    reading = await ReadReceipt(image, receipt.RotationQuarterTurns, byDate, dayFirst, OcrLanguages(s), token);
                }
                if (reading?.Problem is { } problem) ocrProblem ??= problem;
                // A date typed in the review replaces the one found.
                var date = !byDate ? null : receipt.TypedDate is not null ? receipt.ReceiptDate : reading?.Date;
                var read = reading?.Lines;
                lines.Add(read);
                dates.Add(date);
            }

            // 2. The files, all or nothing.
            var saved = new List<string>();
            var textFiles = new List<string>();
            async Task WriteText(string pdfPath, IReadOnlyList<int> indices)
            {
                if (!s.Output.SavesTextBeside) return;
                var text = new PdfText();
                foreach (int i in indices)
                {
                    if (lines[i] is { } l) text.Pages.Add(OcrPage.Of(l, images[i].Width, images[i].Height, receipts[i].Dpi));
                    else text.Problem ??= ocrProblem ?? Loc.T("The text could not be read.");
                }
                // A text file that cannot be written is reported; the PDF is kept.
                if (await WriteTextBeside(pdfPath, text) is { } written) textFiles.Add(written);
            }
            await WriteImagesRollingBack(saved, async () =>
            {
                if (combine)
                {
                    StatusMessage = Loc.T("Writing the PDF…");
                    NotifyAll();
                    var pages = images.Select((image, i) => new ScannedPage(image, receipts[i].Dpi, ColorMode.Grayscale)).ToList();
                    string path = await WritePdfAtomically(pages, s, await OutputPath(s, "pdf", documentDate: Receipts.CombinedDate(dates)),
                                                           token, knownLines: lines);
                    saved.Add(path);
                    await WriteText(path, Enumerable.Range(0, receipts.Count).ToList());
                    return;
                }
                for (int i = 0; i < receipts.Count; i++)
                {
                    token.ThrowIfCancellationRequested();
                    StatusMessage = Loc.T("Saving receipt {0} of {1}…", i + 1, receipts.Count);
                    NotifyAll();
                    string path = await OutputPath(s, format.FileExtension(), documentDate: dates[i]);
                    if (format == OutputFormat.Pdf)
                    {
                        var page = new ScannedPage(images[i], receipts[i].Dpi, ColorMode.Grayscale);
                        path = await WritePdfAtomically([page], s, path, token, knownLines: [lines[i]]);
                        saved.Add(path);
                        await WriteText(path, [i]);
                    }
                    else
                    {
                        var image = images[i];
                        int dpi = receipts[i].Dpi;
                        saved.Add(await Task.Run(() => WpfImageCodec.SaveAsNew(image, path, format, dpi, s.JpegQuality)));
                    }
                }
            }, alsoWritten: textFiles);
            MarkSaved(saved);
            DetectedPhotos = [];
            ShowPhotoReview = false;
            IsReceiptReview = false;
            _photoSourceImages = [];
            ResetFlow();
            // With Also save text on, WriteTextBeside has reported the unread text already.
            if (ocrProblem is not null && ErrorMessage is null) ErrorMessage = TextExport.RecognitionFailed(ocrProblem);
            int undated = byDate ? dates.Count(d => d is null) : 0;
            var names = saved.Select(p => Path.GetFileName(p)).ToList();
            // Protected PDFs say so after their names: "a.pdf, b.pdf (password-protected)".
            bool pdfs = combine || format == OutputFormat.Pdf;
            if (pdfs && names.Count > 0 && PdfNote(null, LastPdfProtected) is { } note) names[^1] = Loc.T("{0} ({1})", names[^1], note);
            SetStatus(Receipts.SavedMessage(receipts.Count, names, combine, undated),
                      new(new StatusHead.SavedFiles(receipts.Count, FileKind.Receipt)));
            RunAfterSave(s.Output.AfterSave, saved);
        });
    }
}
