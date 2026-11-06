using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Media.Imaging;
using LazyScan.App.Services;
using LazyScan.App.Services.Companion;
using LazyScan.Core;

namespace LazyScan.App;

/// <summary>The banner's texts for a <c>.lsdoc</c> opened by hand. Twin of Swift <c>PackageText</c>.</summary>
public static class PackageText
{
    public static string AddToPages => Loc.T("Add to pages");
    public static string OpenAsNew => Loc.T("Open as new");
    public static string NotAddedTitle => Loc.T("Not added");

    /// <summary>Why a document's pages are not added with these settings, and what to change to add them.</summary>
    public static string NotOfferedMessage(ScanSettings settings) =>
        PhotoImport.OwnSaveTaskReason(settings) is not null && settings.Task is { } task
            ? Loc.T("The {0} task saves its scans on its own, so a document's pages cannot be added here. Leave the task or pick Document to PDF to add them.", TaskCatalog.Definition(task).Title)
            : Loc.T("A document's pages are added to the page queue: choose Document mode, or a document task, with Collect pages before saving on, to add them.");

    /// <summary>"Opened Receipt.lsdoc: 3 pages"</summary>
    public static string OpenedMessage(string fileName, int pageCount) =>
        Loc.Plural(pageCount, "Opened {1}: {0} page", "Opened {1}: {0} pages", fileName);

    /// <summary>"Receipt.lsdoc cannot be opened: one of its pictures cannot be read."</summary>
    public static string UnreadablePictureMessage(string fileName) =>
        Loc.T("{0} cannot be opened: one of its pictures cannot be read.", fileName);
}

/// <summary>
/// A <c>.lsdoc</c> opened by hand and waiting on the banner: its file's name, its pages decoded as the
/// queue takes them (<see cref="CompanionPages.ToScannedPages"/> for a document added to the current
/// one), and the name its document carries ("" for none).
/// </summary>
public sealed record PendingPackage(string FileName, IReadOnlyList<ScannedPage> Pages, string DocumentName)
{
    public int PageCount => Pages.Count;

    /// <summary><paramref name="path"/> names a <c>.lsdoc</c> (by its extension).</summary>
    public static bool IsPackageFile(string path) =>
        Path.GetExtension(path).Equals("." + CompanionPackage.FileExtension, StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// The first <c>.lsdoc</c> among a command line's arguments. When the first argument is a <c>lazyscan:</c>
    /// address the app is only being opened, and the rest is dropped: the scheme's command is
    /// <c>"exe" "%1"</c>, so an address with a quote in it can add arguments of its own.
    /// </summary>
    public static string? PackageIn(IEnumerable<string> args)
    {
        var all = args.ToList();
        return all.Count > 0 && FileAssociation.IsAddress(all[0]) ? null : all.FirstOrDefault(IsPackageFile);
    }

    /// <summary>
    /// The package at <paramref name="path"/> with every picture decoded. Throws
    /// <see cref="CompanionPackageException"/>: a newer format is refused with
    /// <see cref="CompanionPackage.NewerVersionMessage"/>, a picture that cannot be decoded (or that
    /// <see cref="Decode"/> turns down) with <see cref="PackageText.UnreadablePictureMessage"/>.
    /// </summary>
    public static PendingPackage Read(string path, Func<byte[], RgbaImage> decode)
    {
        string name = Path.GetFileName(path);
        var document = CompanionPackage.ReadFile(path);
        List<ScannedPage> pages;
        try
        {
            pages = CompanionPages.ToScannedPages(document, CompanionTarget.Current, queueHasPages: false, decode);
        }
        catch (Exception e) when (e is NotSupportedException or FileFormatException or COMException or ArgumentException
                                      or InvalidOperationException or OverflowException or OutOfMemoryException or IOException)
        {
            throw new CompanionPackageException(CompanionPackageErrorKind.UnsupportedImage, PackageText.UnreadablePictureMessage(name), e);
        }
        return new PendingPackage(name, pages, CompanionPages.DocumentName(document));
    }

    /// <summary>
    /// A package's picture decoded as <see cref="WpfImageCodec.Decode"/> does, except that one whose header
    /// claims more than <see cref="PhotoImport.MaxPhotoPixels"/> is turned down before its pixels take
    /// memory: a file opened by hand can come from anywhere, not only a paired phone.
    /// </summary>
    public static RgbaImage Decode(byte[] data)
    {
        var decoder = BitmapDecoder.Create(new MemoryStream(data, writable: false), BitmapCreateOptions.None, BitmapCacheOption.None);
        var frame = decoder.Frames[0];
        if ((long)frame.PixelWidth * frame.PixelHeight > PhotoImport.MaxPhotoPixels) throw new NotSupportedException();
        return WpfImageCodec.FromBitmapSource(frame);
    }

    /// <summary>The pages as Open as new adds them: the first carries the document's name.</summary>
    public IReadOnlyList<ScannedPage> AsNewDocument()
    {
        if (DocumentName.Length == 0 || Pages.Count == 0) return Pages;
        var named = Pages.ToList();
        named[0] = named[0].WithDocumentLabel(DocumentName);
        return named;
    }
}

/// <summary>
/// A <c>.lsdoc</c> opened by hand (dropped on the window, or opened through the file association) is
/// offered, not added: a banner adds its pages to the queue or opens it as a new one, unlike a paired
/// phone's documents, which <see cref="AppViewModel"/>'s phone link adds on its own. The queue can also
/// be written as a <c>.lsdoc</c>. The Mac and the iPhone do the same (Sources/LazyScanKit/App/AppState+Package.swift).
/// </summary>
public sealed partial class AppViewModel
{
    /// <summary>The <c>.lsdoc</c> offered on the banner; null when none is.</summary>
    public PendingPackage? PendingPackage { get; private set; }

    /// <summary>Counts the <c>.lsdoc</c> files opened, so a slow read does not replace a file opened after it.</summary>
    private int _packageOpens;

    /// <summary>
    /// Reads the <c>.lsdoc</c> at <paramref name="path"/> off the UI thread and offers it, replacing one
    /// offered before; a package that cannot be read is said in <see cref="ErrorMessage"/>. When another
    /// file is opened before the read ends, the read is dropped: the file opened last is the one offered.
    /// The queue is not touched, so a package can be opened while a scan runs.
    /// </summary>
    public async Task OpenPackage(string path)
    {
        int opening = ++_packageOpens;
        try
        {
            var package = await Task.Run(() => PendingPackage.Read(path, PendingPackage.Decode));
            if (opening != _packageOpens) return;
            PendingPackage = package;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            if (opening != _packageOpens) return;
            ErrorMessage = e.Message;
        }
        NotifyAll();
    }

    /// <summary>
    /// Add to pages: the offered pages are spooled and join the queue after its pages, as a phone's
    /// pages do. Not while something runs or a review is open (the offer stays), nor while the
    /// settings do not collect pages (said in <see cref="ErrorMessage"/>).
    /// </summary>
    public Task AddPendingPackageToPages() =>
        PendingPackage is { } package ? TakePackage(package, package.Pages, asNew: false) : Task.CompletedTask;

    /// <summary>
    /// Open as new: the queue is cleared and the offered pages become it, under the document's name.
    /// Refused as Add to pages is, and the queue is then left alone.
    /// </summary>
    public Task OpenPendingPackageAsNew() =>
        PendingPackage is { } package ? TakePackage(package, package.AsNewDocument(), asNew: true) : Task.CompletedTask;

    public void DismissPendingPackage()
    {
        PendingPackage = null;
        NotifyAll();
    }

    /// <summary>
    /// The settings collect pages in the queue, where a package's pages go: <see cref="PhotoImport.IsOffered"/>
    /// with Collect pages before saving on, as the Mac and the iPhone need for <c>ingest</c> to queue them.
    /// </summary>
    public bool CollectsPackages => PhotoImport.IsOffered(Settings) && Settings.DocumentMultiPage;

    private Task TakePackage(PendingPackage package, IReadOnlyList<ScannedPage> pages, bool asNew)
    {
        if (!CollectsPackages)
        {
            ErrorTitle = PackageText.NotAddedTitle;
            ErrorMessage = PackageText.NotOfferedMessage(Settings);
            NotifyAll();
            return Task.CompletedTask;
        }
        if (!CanTakePhonePages) return Task.CompletedTask;
        return RunExclusive(async token =>
        {
            SavedBarPaths = null;
            if (asNew)
            {
                DeleteSpoolFiles(ScannedPages.Select(p => p.Page));
                ScannedPages.Clear();
                ResetFlow();
            }
            string spoolDirectory = _spool.Directory;
            var spooled = await Task.Run(() => SpoolPages([.. pages], spoolDirectory).Select(p => new PageItem(p)).ToList(), token);
            foreach (var item in spooled) ScannedPages.Add(item);
            // Another file may have been opened while the pages were spooled: that offer stays.
            if (ReferenceEquals(PendingPackage, package)) PendingPackage = null;
            if (spooled.Count > 0) SetLastScan(ScanHistory.MakePreview(spooled[^1].Page.Image, CanvasPreviewMaxSide));
            if (PageProcessor.ReadsBarcodes(Settings)) _readBarcodesAfterWork = true;
            SetStatus(Loc.Plural(spooled.Count, "Added {0} page from {1} — {2} in queue.", "Added {0} pages from {1} — {2} in queue.",
                package.FileName, ScannedPages.Count), new(new StatusHead.PagesAdded(spooled.Count, ScannedPages.Count, 0, 0)));
        });
    }

    /// <summary>
    /// Writes the queued pages as one <c>.lsdoc</c> in <paramref name="folder"/>, named as the next
    /// saved file would be (the running number is read, not taken), and returns its path
    /// (<see cref="CompanionPages.ToDocument"/>).
    /// </summary>
    public async Task<string> ExportPackage(string folder)
    {
        var pages = ScannedPages.Select(p => p.Page).ToList();
        if (pages.Count == 0) throw new CompanionPackageException(CompanionPackageErrorKind.NoPages, CompanionPackage.NoPagesMessage);
        var s = Settings.Clone();
        string name = new NamingTemplate(s.NamingTemplate)
            .BaseFilename(new NamingContext(PeekCounter() + 1, DateTime.Now, s.Intent)
            {
                Task = TaskCatalog.Infer(s),
                Label = pages[0].DocumentLabel,
            });
        string path = NamingTemplate.UniquePath(folder, name, CompanionPackage.FileExtension);
        await Task.Run(() =>
        {
            var document = CompanionPages.ToDocument(pages, name, s.JpegQuality, page =>
            {
                var spooled = SpoolImage(page);
                // A spooled page whose file went (the queue saved or cleared meanwhile) would be written
                // from its preview: refused rather than written small.
                if (spooled is null && page.FilePath is not null)
                {
                    throw new CompanionPackageException(CompanionPackageErrorKind.InvalidDocument,
                        Loc.T("The picture of page {0} could not be written.", pages.IndexOf(page) + 1));
                }
                return PdfBuilder.PreparePage(page, spooled).Image;
            }) with
            {
                Writer = new CompanionWriterInfo("Lazy Scan", typeof(AppViewModel).Assembly.GetName().Version?.ToString(3) ?? "", "windows"),
                Created = DateTimeOffset.Now,
                TaskId = s.TaskId,
                NamingTemplate = s.NamingTemplate,
            };
            File.WriteAllBytes(path, CompanionPackage.Make(document));
        });
        return path;
    }
}
