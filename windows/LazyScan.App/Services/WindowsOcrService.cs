using System.Runtime.InteropServices.WindowsRuntime;
using LazyScan.Core;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using OcrLine = LazyScan.Core.OcrLine;

namespace LazyScan.App.Services;

/// <summary>
/// Text recognition backed by Windows.Media.Ocr (built into Windows 10/11; per-language
/// packs installed via Settings → Language). The Windows counterpart of the macOS app's
/// Apple Vision OCRService.
///
/// The language chosen in the options (the first of the languages passed in) reads the page and its
/// result is returned as it is. Automatic, and a chosen language whose pack is gone, work like the
/// macOS service: Windows OCR has no language detection, so the engine for the user-profile
/// languages runs first. When more than one Latin-script pack is installed, the page is also read
/// with each of the others and the result with the most recognized text wins. When the best result
/// finds next to nothing (a page in another script or language), every other installed recognizer
/// language is tried once — bounded, and only when it clearly beats it.
///
/// Windows OCR reports word rectangles in top-left-origin pixels; this service converts
/// them to the Core convention (normalized, bottom-left origin) so PdfBuilder maps them
/// straight into PDF user space.
/// </summary>
public sealed class WindowsOcrService : IOcrService
{
    /// <summary>Below this many lines the profile-language result is considered a miss.</summary>
    private const int FewLines = 3;
    /// <summary>At most this many extra recognizers run for one page (bounds the cost on blank pages).</summary>
    private const int MaxFallbackEngines = 4;
    /// <summary>A fallback must beat a non-empty primary result by this factor (letters + digits).</summary>
    private const double FallbackAdvantage = 1.5;
    /// <summary>When the primary found nothing, a fallback needs at least this much text to count.</summary>
    private const int MinFallbackScore = 6;

    public async Task<IReadOnlyList<OcrLine>> RecognizeLinesAsync(RgbaImage image,
                                                                  IReadOnlyList<string>? languages = null)
    {
        var installed = Installed();
        var chosenEngine = OcrLanguagePlan.Chosen(languages?.FirstOrDefault(), installed) is { } chosenTag
            ? EngineFor(chosenTag)
            : null;
        var primary = chosenEngine is null ? OcrEngine.TryCreateFromUserProfileLanguages() : null;
        if (chosenEngine is null && primary is null && installed.Count == 0)
        {
            throw ScanException.ScanFailed(() => Loc.T("OCR failed: {0}",
                Loc.T("no OCR language pack is installed (Settings → Time & Language → Language).")));
        }

        // The engine rejects very large bitmaps; downscale as needed and the normalized
        // boxes stay valid because they are resolution-independent.
        var working = image;
        int maxDim = (int)OcrEngine.MaxImageDimension;
        if (image.Width > maxDim || image.Height > maxDim)
        {
            double scale = Math.Min((double)maxDim / image.Width, (double)maxDim / image.Height);
            working = image.Resized(Math.Max(1, (int)(image.Width * scale)),
                                    Math.Max(1, (int)(image.Height * scale)));
        }

        using var bitmap = new SoftwareBitmap(BitmapPixelFormat.Rgba8, working.Width, working.Height,
                                              BitmapAlphaMode.Ignore);
        bitmap.CopyFromBuffer(working.Pixels.AsBuffer());

        if (chosenEngine is not null) return await Recognize(chosenEngine, bitmap, working.Width, working.Height);

        // The user-profile engine runs first. If it fails, that counts as "no result" so
        // the fallback recognizers still get their chance.
        List<OcrLine>? primaryLines = null;
        ScanException? primaryError = null;
        string? primaryTag = primary?.RecognizerLanguage.LanguageTag;
        if (primary is not null)
        {
            try
            {
                primaryLines = await Recognize(primary, bitmap, working.Width, working.Height);
            }
            catch (ScanException e)
            {
                primaryError = e;
            }
        }

        var ran = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (primaryTag is not null) ran.Add(primaryTag);
        var latin = OcrLanguagePlan.Automatic(primaryTag, installed, MaxFallbackEngines + 1);
        if (latin.Count > 1)
        {
            foreach (var tag in latin)
            {
                if (!ran.Add(tag) || EngineFor(tag) is not { } engine) continue;
                try
                {
                    var lines = await Recognize(engine, bitmap, working.Width, working.Height);
                    if (primaryLines is null || Score(lines) > Score(primaryLines)) primaryLines = lines;
                }
                catch (ScanException)
                {
                    // one failing recognizer must not sink the page
                }
            }
        }
        if (primaryLines is { Count: >= FewLines }) return primaryLines;

        // Few or no lines: the page may be in another language/script — or simply blank or
        // a photo. Try a bounded number of other recognizers and keep the best, but only let
        // it replace the primary result when it is clearly better, so a correct short
        // result is never swapped for wrong-script noise.
        int primaryScore = primaryLines is null ? 0 : Score(primaryLines);
        List<OcrLine>? bestFallback = null;
        int bestFallbackScore = 0;
        bool anyFallbackSucceeded = false;
        int tried = 0;
        foreach (var language in OcrEngine.AvailableRecognizerLanguages)
        {
            if (tried >= MaxFallbackEngines) break;
            if (ran.Contains(language.LanguageTag)) continue;
            if (OcrEngine.TryCreateFromLanguage(language) is not { } engine) continue;
            tried++;
            List<OcrLine> lines;
            try
            {
                lines = await Recognize(engine, bitmap, working.Width, working.Height);
            }
            catch (ScanException)
            {
                continue; // one failing recognizer must not sink the page
            }
            anyFallbackSucceeded = true;
            int score = Score(lines);
            if (score > bestFallbackScore)
            {
                bestFallback = lines;
                bestFallbackScore = score;
            }
        }

        if (primaryScore > 0)
        {
            return bestFallback is not null && bestFallbackScore > primaryScore * FallbackAdvantage
                ? bestFallback
                : primaryLines!;
        }
        // Without a user-profile engine the "fallbacks" are the only recognizers there are.
        if (primary is null && bestFallback is not null) return bestFallback;
        if (bestFallback is not null && bestFallbackScore >= MinFallbackScore) return bestFallback;
        if (primaryLines is not null || anyFallbackSucceeded) return [];
        // Nothing could run at all: surface the primary engine's error (the caller then
        // writes the page without a text layer).
        throw primaryError ?? ScanException.ScanFailed(() => Loc.T("OCR failed: {0}", Loc.T("no recognizer could process the page.")));
    }

    internal static List<OcrLanguagePlan.Pack> Installed() =>
        [.. OcrEngine.AvailableRecognizerLanguages.Select(l => new OcrLanguagePlan.Pack(l.LanguageTag, l.Script))];

    internal static OcrEngine? EngineFor(string tag) =>
        OcrEngine.AvailableRecognizerLanguages
            .FirstOrDefault(l => string.Equals(l.LanguageTag, tag, StringComparison.OrdinalIgnoreCase)) is { } language
            ? OcrEngine.TryCreateFromLanguage(language)
            : null;

    private static async Task<List<OcrLine>> Recognize(OcrEngine engine, SoftwareBitmap bitmap,
                                                       double w, double h)
    {
        OcrResult result;
        try
        {
            result = await engine.RecognizeAsync(bitmap);
        }
        catch (Exception e)
        {
            throw ScanException.ScanFailed(() => Loc.T("OCR failed: {0}", e.Message));
        }

        var lines = new List<OcrLine>();
        foreach (var line in result.Lines)
        {
            if (string.IsNullOrWhiteSpace(line.Text)) continue;
            // Union of the word rects = the line's bounding box.
            double minX = double.MaxValue, minY = double.MaxValue;
            double maxX = double.MinValue, maxY = double.MinValue;
            foreach (var word in line.Words)
            {
                var r = word.BoundingRect;
                minX = Math.Min(minX, r.X);
                minY = Math.Min(minY, r.Y);
                maxX = Math.Max(maxX, r.X + r.Width);
                maxY = Math.Max(maxY, r.Y + r.Height);
            }
            if (maxX <= minX || maxY <= minY) continue;
            // Top-left pixel rect → normalized bottom-left origin.
            var box = new RectD(minX / w, 1.0 - maxY / h, (maxX - minX) / w, (maxY - minY) / h);
            // Windows OCR has no per-line confidence; report 1.
            lines.Add(new OcrLine(line.Text, box, 1.0f));
        }
        return lines;
    }

    /// <summary>Amount of recognized text: letters and digits across all lines.</summary>
    private static int Score(List<OcrLine> lines) =>
        lines.Sum(line => line.Text.Count(char.IsLetterOrDigit));
}
