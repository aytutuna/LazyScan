using LazyScan.App.Services;
using LazyScan.Core;

namespace LazyScan.App;

/// <summary>
/// A photo whose page was not found clearly, for the corner editor: the photo (upright), what the
/// page search found and suggests (<see cref="PhotoImportPlan"/>), where it is in the import, and what
/// is cut out of it, which the editor's words name (a page here; the iPhone also cuts out ID cards,
/// photos and receipts). <see cref="MoreFollow"/>: more photos or pages of the import follow this
/// one, so the editor offers Stop import.
/// </summary>
public sealed record PhotoCornersRequest(RgbaImage Photo, PhotoImportPlan Plan, string FileName, int Number, int Count,
                                         CaptureKind Kind = CaptureKind.Document, bool MoreFollow = false);

/// <summary>The corner editor's answer: what to do with the photo, and the corners placed when they are used.</summary>
public sealed record PhotoCornersAnswer(PhotoCornersChoice Choice, Quad? Corners = null)
{
    public static PhotoCornersAnswer Skip { get; } = new(PhotoCornersChoice.Skip);
}

/// <summary>
/// Importing photos of documents as pages of the queue (Import photos… under the queue, the empty
/// stage's link, or photos dropped on the window), <see cref="PhotoImport"/>. The Mac's twin is
/// App/AppState+Import.swift.
/// </summary>
public sealed partial class AppViewModel
{
    /// <summary>
    /// Asks the user to place a photo's corners when its page was not found clearly: the window shows
    /// the corner editor (<see cref="PhotoCornersWindow"/>). Nobody to ask skips the photo.
    /// </summary>
    public Func<PhotoCornersRequest, PhotoCornersAnswer>? ReviewPhotoCorners { get; set; }

    /// <summary>
    /// Photos can be imported now: the settings collect pages in the queue (<see cref="PhotoImport.IsOffered"/>),
    /// nothing else is running, no review is open, and no stack turned over by hand is under way (<see cref="IsStackUnderWay"/>).
    /// </summary>
    public bool CanImportPhotos =>
        !IsBusy && PhotoImport.IsOffered(Settings) && !IsStackUnderWay && !ShowPhotoReview && !ShowIdCardReview;

    /// <summary>
    /// Adds the photos among <paramref name="paths"/> to the queue, one after another: each is read
    /// (the file itself is never changed), turned upright by its orientation tag, its page found and
    /// cut out along its corners; a photo whose page is not found clearly goes to the corner editor
    /// (<see cref="ReviewPhotoCorners"/>), which may also take the whole photo or skip it. Each page
    /// goes through the clean-up stage (<see cref="PageProcessor.ForPhotoImport"/>), is spooled with the
    /// photo as its other version and added to the queue at once, so a Cancel keeps the pages already
    /// added. With Collect pages before saving off the pages are held instead, after a scan's clean-up
    /// stage (<see cref="PageProcessor.ForScan"/>), and saved together once the last photo is in, as a
    /// scan's are; a Cancel puts the pages held so far in the queue. Each page of a TIFF of several pages
    /// is imported as a photo of its own. Photos that cannot be read (too large ones too) are listed in
    /// one error at the end; the others are imported.
    /// </summary>
    public Task ImportPhotos(IReadOnlyList<string> paths)
    {
        if (IsBusy) return Task.CompletedTask;
        var files = PhotoImport.PhotoFiles(paths);
        if (files.Count == 0 || !CanImportPhotos)
        {
            if (paths.Count > 0)
            {
                ErrorTitle = PhotoImport.NotImportedTitle;
                ErrorMessage = files.Count == 0 ? PhotoImport.NoPhotosMessage : PhotoImport.NotOfferedMessage(Settings);
            }
            NotifyAll();
            return Task.CompletedTask;
        }
        var s = Settings.Clone();
        // With Collect pages before saving off the pages are saved together once the last photo is in, as
        // a scan's are, and cleaned up as a scan's: pages saved at once are never checked or turned unseen.
        bool savesAtOnce = !s.DocumentMultiPage;
        return RunExclusive(async token =>
        {
            // The bar of the previous save makes way for the new pages.
            SavedBarPaths = null;
            var processor = savesAtOnce ? PageProcessor.ForScan(s) : PageProcessor.ForPhotoImport(s, _orientation, _barcodes);
            string spoolDirectory = _spool.Directory;
            var added = new List<ScannedPage>();
            var problems = new List<string>();
            int skipped = 0;
            RgbaImage? lastPreview = null;
            try
            {
                for (int i = 0; i < files.Count; i++)
                {
                    token.ThrowIfCancellationRequested();
                    string path = files[i];
                    int fileNumber = i + 1;
                    StatusMessage = PhotoImport.ProgressMessage(fileNumber, files.Count);
                    NotifyAll();
                    byte[] bytes;
                    try
                    {
                        bytes = await Task.Run(() => PhotoFileReader.ReadBytes(path), token);
                    }
                    catch (PhotoUnreadableException e)
                    {
                        problems.Add(e.Message);
                        continue;
                    }
                    // A TIFF may hold several pages: each is imported in turn. Their count is read from the
                    // file's header, so a page that cannot be decoded does not end the file's import.
                    int pageCount = await Task.Run(() => PhotoFileReader.PageCount(bytes), token);
                    for (int pageNumber = 1; pageNumber <= pageCount; pageNumber++)
                    {
                        token.ThrowIfCancellationRequested();
                        int number = pageNumber;
                        PhotoFile file;
                        try
                        {
                            file = await Task.Run(() => PhotoFileReader.Decode(bytes, path, number), token);
                        }
                        catch (PhotoUnreadableException e)
                        {
                            problems.Add(e.Message);
                            continue;
                        }
                        if (pageCount > 1)
                        {
                            StatusMessage = PhotoImport.ProgressMessage(fileNumber, files.Count, number, pageCount);
                            NotifyAll();
                        }
                        await ImportPage(file, fileNumber);
                    }
                }
            }
            catch (OperationCanceledException) when (token.IsCancellationRequested)
            {
                // The pages added before Cancel stay in the queue; pages held to be saved go there too,
                // as a save at once that was cancelled leaves them.
                if (lastPreview is not null) SetLastScan(lastPreview);
                if (savesAtOnce && added.Count > 0)
                {
                    await KeepInQueue(added);
                    StatusMessage = TextExport.PagesKeptInQueue(added.Count, 0, cancelled: true, OutputFormats.SaveTitle(s.Format));
                }
                else
                {
                    StatusMessage = PhotoImport.CancelledMessage(added.Count, ScannedPages.Count);
                }
                if (problems.Count > 0) ErrorMessage = string.Join(Environment.NewLine, problems);
                return;
            }
            if (lastPreview is not null) SetLastScan(lastPreview);
            if (savesAtOnce && added.Count > 0)
            {
                await SaveImmediately(added, s, token);
                RecordCaptures(added.Select(page => page.Id));
            }
            else
            {
                StatusMessage = PhotoImport.AddedMessage(added.Count, skipped, problems.Count, ScannedPages.Count,
                                                         OutputFormats.SaveTitle(Settings.Format));
                if (added.Count > 0)
                {
                    StatusMessage += QueueScanNote(added, s.Document);
                    if (s.Document.AutoRotate && !_orientation.IsAvailable) StatusMessage += PageTurns.UnavailableNote;
                    // Pages queued earlier and never read (a reading stopped) are read once the import is done.
                    if (PageProcessor.ReadsBarcodes(Settings)) _readBarcodesAfterWork = true;
                }
            }
            // A failed save at once keeps its message above the unreadable photos.
            if (problems.Count > 0)
            {
                var saveFailed = savesAtOnce && added.Count > 0 && !string.IsNullOrEmpty(ErrorMessage);
                ErrorMessage = string.Join(Environment.NewLine, saveFailed ? problems.Prepend(ErrorMessage!) : problems);
            }

            // One photo (or one page of a TIFF): its page found and cut out, or the corner editor asked;
            // then cleaned up, spooled and added to the queue, or held to be saved at once.
            async Task ImportPage(PhotoFile file, int fileNumber)
            {
                var (photo, plan) = await Task.Run(() =>
                {
                    var upright = PhotoImport.Oriented(file.Stored, file.Orientation);
                    return (upright, PhotoImport.Plan(upright, _cornerModel));
                }, token);
                ScannedPage? page = plan.Action == PhotoImportAction.Correct
                    ? await Task.Run(() => PhotoImport.CorrectedPage(photo, plan.Corners), token)
                    : null;
                if (page is null)
                {
                    var request = new PhotoCornersRequest(photo, plan, file.DisplayName, fileNumber, files.Count,
                                                          MoreFollow: fileNumber < files.Count || file.Page < file.PageCount);
                    var answer = ReviewPhotoCorners?.Invoke(request) ?? PhotoCornersAnswer.Skip;
                    token.ThrowIfCancellationRequested();
                    page = answer switch
                    {
                        { Choice: PhotoCornersChoice.UseCorners, Corners: { } corners } =>
                            await Task.Run(() => PhotoImport.CorrectedPage(photo, corners) ?? PhotoImport.WholePhotoPage(photo), token),
                        { Choice: PhotoCornersChoice.WholePhoto } => PhotoImport.WholePhotoPage(photo),
                        _ => null,
                    };
                    if (page is null)
                    {
                        skipped++;
                        return;
                    }
                }
                var cleaned = page;
                var (processed, preview) = await Task.Run(() =>
                    (processor.Process([cleaned], token).Pages.ToList(), ScanHistory.MakePreview(cleaned.Image, CanvasPreviewMaxSide)), token);
                if (savesAtOnce)
                {
                    added.AddRange(processed);
                    lastPreview = preview;
                    return;
                }
                // Spill the page and the photo it was taken from to disk; keep only previews in the queue.
                var spooled = await Task.Run(() => SpoolPages(processed, spoolDirectory).Select(p => new PageItem(p)).ToList());
                if (token.IsCancellationRequested)
                {
                    DeleteSpoolFiles(spooled.Select(item => item.Page));
                    token.ThrowIfCancellationRequested();
                }
                foreach (var item in spooled) ScannedPages.Add(item);
                added.AddRange(spooled.Select(item => item.Page));
                // Photos come in between stacks turned over by hand, never as one of their sides.
                if (!IsTurningOverByHand) RecordCaptures(spooled.Select(item => item.Page.Id));
                lastPreview = preview;
                NotifyAll();
            }
        });
    }
}
