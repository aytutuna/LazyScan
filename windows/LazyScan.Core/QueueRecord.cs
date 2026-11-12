using System.Text.Json;

namespace LazyScan.Core;

/// <summary>
/// The page queue as the app keeps it beside its spool files (queue.json): each page's spool files and what
/// the queue knows about it, so the pages of a run that did not end cleanly can be found again. The previews
/// are read from the files again. The spreads book pages were cut from and the spine's shadow stay in memory
/// only. Twin of the Kit's <c>QueueRecord</c>, which the iPhone keeps.
/// </summary>
public sealed class QueueRecord
{
    public const string FileName = "queue.json";

    public List<QueuePage> Pages { get; set; } = [];

    /// <summary>How many pages the queue had when it was recorded, those left out included; null in a record written before it existed.</summary>
    public int? Queued { get; set; }

    /// <summary>
    /// The record of <paramref name="pages"/>. A page without a file in <paramref name="spool"/> (kept in memory
    /// because its spill failed) is left out, as the record could not bring it back, and so is a version not
    /// shown that is in memory only.
    /// </summary>
    public static QueueRecord Of(IReadOnlyList<ScannedPage> pages, string spool)
    {
        var record = new QueueRecord { Queued = pages.Count };
        foreach (var page in pages)
        {
            if (!InSpool(page.FilePath, spool)) continue;
            string? alternate = page.Alternate?.FilePath;
            record.Pages.Add(new QueuePage
            {
                Id = page.Id,
                File = Path.GetFileName(page.FilePath!),
                FullPixelSize = page.FullPixelSize,
                AlternateFile = InSpool(alternate, spool) ? Path.GetFileName(alternate!) : null,
                AlternatePixelSize = page.Alternate?.FullPixelSize,
                Dpi = page.Dpi,
                ColorMode = page.ColorMode,
                CreatedAt = page.CreatedAt,
                RotationQuarterTurns = page.RotationQuarterTurns,
                Side = page.Side,
                SheetIndex = page.SheetIndex,
                Blank = page.Blank,
                Inclusion = page.Inclusion,
                Geometry = page.Geometry,
                ShowsOriginal = page.ShowsOriginal,
                Patch = page.Patch,
                Barcodes = page.Barcodes?.ToList(),
                DocumentBreak = page.DocumentBreak,
                DocumentLabel = page.DocumentLabel,
                Upright = page.Upright,
                Source = page.Source,
                Capture = page.Capture,
            });
        }
        return record;
    }

    /// <summary>Writes the record of <paramref name="pages"/> into <paramref name="spool"/>, or removes it when none of them has a file there.</summary>
    public static void Write(IReadOnlyList<ScannedPage> pages, string spool)
    {
        string path = Path.Combine(spool, FileName);
        var record = Of(pages, spool);
        if (record.Pages.Count == 0)
        {
            try { File.Delete(path); } catch { /* best effort */ }
            return;
        }
        StoreFiles.Write(record, path);
    }

    /// <summary>
    /// The record in <paramref name="spool"/>, or null when there is none or no page of it can come back. Each
    /// page is read on its own, so one that does not decode is left out and the rest stay; so is a page whose
    /// file is gone (the record is written a moment after a page goes, and the app may end in between).
    /// </summary>
    public static QueueRecord? Read(string spool)
    {
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(spool, FileName)));
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object
                || !root.TryGetProperty("pages", out var list) || list.ValueKind != JsonValueKind.Array)
            {
                return null;
            }
            var record = new QueueRecord();
            if (root.TryGetProperty("queued", out var queued) && queued.TryGetInt32(out int count)) record.Queued = count;
            foreach (var element in list.EnumerateArray())
            {
                QueuePage? page;
                try { page = element.Deserialize<QueuePage>(StoreFiles.JsonOptions); }
                catch (JsonException) { continue; }
                if (page is null || page.Id == Guid.Empty || !IsFileName(page.File)
                    || !File.Exists(Path.Combine(spool, page.File)))
                {
                    continue;
                }
                if (page.AlternateFile is not null && !IsFileName(page.AlternateFile)) page.AlternateFile = null;
                record.Pages.Add(page);
            }
            return record.Pages.Count == 0 ? null : record;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException)
        {
            return null;
        }
    }

    private static bool InSpool(string? file, string spool) =>
        file is not null
        && string.Equals(Path.GetDirectoryName(Path.GetFullPath(file)), Path.GetFullPath(spool),
                         StringComparison.OrdinalIgnoreCase);

    private static bool IsFileName(string name) => name.Length > 0 && Path.GetFileName(name) == name;
}

/// <summary>One page of a <see cref="QueueRecord"/>: its spool files and the facts of a <see cref="ScannedPage"/>.</summary>
public sealed class QueuePage
{
    public Guid Id { get; set; }
    public string File { get; set; } = "";
    public SizeD? FullPixelSize { get; set; }
    public string? AlternateFile { get; set; }
    public SizeD? AlternatePixelSize { get; set; }
    public int Dpi { get; set; } = CompanionPackage.DefaultDpi;
    public ColorMode ColorMode { get; set; }
    public DateTime CreatedAt { get; set; }
    public int RotationQuarterTurns { get; set; }
    public PageSide? Side { get; set; }
    public int? SheetIndex { get; set; }
    public BlankPageResult? Blank { get; set; }
    public PageInclusion Inclusion { get; set; }
    public PageGeometry? Geometry { get; set; }
    public bool ShowsOriginal { get; set; }
    public PatchCode? Patch { get; set; }
    public List<BarcodeReading>? Barcodes { get; set; }
    public DocumentBreak DocumentBreak { get; set; }
    public string? DocumentLabel { get; set; }
    public UprightTurn? Upright { get; set; }
    public PageSource Source { get; set; }
    public CaptureFacts? Capture { get; set; }
}
