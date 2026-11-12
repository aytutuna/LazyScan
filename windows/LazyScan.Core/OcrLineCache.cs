using System.Runtime.CompilerServices;

namespace LazyScan.Core;

/// <summary>
/// The lines OCR read on a page, kept so a save that is cancelled or fails does not read the pages
/// again: the next save, a change of format or Copy text takes them from here. A page's lines are
/// good for the same pixels, turn, resolution and OCR language only; any edit makes a page miss.
/// Entries go with their pixels. Twin of Swift <c>OCRLineCache</c>.
/// </summary>
public sealed class OcrLineCache
{
    private sealed record Entry(string? FilePath, int Turns, int Dpi, string Language, IReadOnlyList<OcrLine> Lines);

    private readonly ConditionalWeakTable<RgbaImage, Entry> _entries = new();

    /// <summary>The lines read on <paramref name="page"/> in <paramref name="language"/>, or null when it has none kept.</summary>
    public IReadOnlyList<OcrLine>? Get(ScannedPage page, string language) =>
        _entries.TryGetValue(page.Image, out var e) && Matches(e, page, language) ? e.Lines : null;

    public void Store(ScannedPage page, string language, IReadOnlyList<OcrLine> lines) =>
        _entries.AddOrUpdate(page.Image, new Entry(page.FilePath, page.RotationQuarterTurns, page.Dpi, language, lines));

    private static bool Matches(Entry e, ScannedPage page, string language) =>
        e.FilePath == page.FilePath && e.Turns == page.RotationQuarterTurns && e.Dpi == page.Dpi && e.Language == language;
}
