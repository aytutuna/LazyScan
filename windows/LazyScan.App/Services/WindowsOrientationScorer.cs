using System.Runtime.InteropServices.WindowsRuntime;
using LazyScan.Core;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;

namespace LazyScan.App.Services;

/// <summary>
/// Reads a page for turning pages upright (<see cref="OrientationDecision"/>) with Windows OCR: the
/// recognizer for the language chosen in the options, else the user's languages, else the first one
/// installed. One recognizer only, unlike
/// <see cref="WindowsOcrService"/>: the reading only has to tell which way up the page is, and runs
/// up to four times a page. The Windows counterpart of the Mac's VisionOrientationScorer.
/// </summary>
public sealed class WindowsOrientationScorer(Func<string> chosenLanguage) : IOrientationScorer
{
    private Tuple<string, OcrEngine?>? _cached;

    public bool IsAvailable => Engine() is not null;

    private OcrEngine? Engine()
    {
        string tag = chosenLanguage();
        if (_cached is { } cached && cached.Item1 == tag) return cached.Item2;
        var engine = CreateEngine(tag);
        _cached = Tuple.Create(tag, engine);
        return engine;
    }

    public OrientationScore Score(RgbaImage image, CancellationToken token)
    {
        var engine = Engine()
            ?? throw ScanException.ScanFailed(() =>
                Loc.T("no OCR language pack is installed (Settings → Time & Language → Language)."));
        // The copy read is at most 1600 pixels long, well inside the engine's limit; a larger
        // image is made smaller all the same.
        var working = image;
        int maxDim = (int)OcrEngine.MaxImageDimension;
        if (image.Width > maxDim || image.Height > maxDim)
        {
            double scale = Math.Min((double)maxDim / image.Width, (double)maxDim / image.Height);
            working = image.Resized(Math.Max(1, (int)(image.Width * scale)), Math.Max(1, (int)(image.Height * scale)));
        }
        using var bitmap = new SoftwareBitmap(BitmapPixelFormat.Rgba8, working.Width, working.Height, BitmapAlphaMode.Ignore);
        bitmap.CopyFromBuffer(working.Pixels.AsBuffer());
        // Called on a worker thread of the clean-up stage, which has no synchronization context.
        var result = engine.RecognizeAsync(bitmap).AsTask(token).GetAwaiter().GetResult();
        return OrientationScore.Of(result.Lines.Select(line => line.Text));
    }

    private static OcrEngine? CreateEngine(string chosen)
    {
        try
        {
            if (OcrLanguagePlan.Chosen(chosen, WindowsOcrService.Installed()) is { } tag
                && WindowsOcrService.EngineFor(tag) is { } chosenEngine) return chosenEngine;
            if (OcrEngine.TryCreateFromUserProfileLanguages() is { } engine) return engine;
            foreach (var language in OcrEngine.AvailableRecognizerLanguages)
            {
                if (OcrEngine.TryCreateFromLanguage(language) is { } other) return other;
            }
        }
        catch (Exception)
        {
            // Windows OCR could not be reached: pages are not turned.
        }
        return null;
    }
}
