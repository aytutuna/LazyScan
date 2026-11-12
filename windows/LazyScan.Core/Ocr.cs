namespace LazyScan.Core;

// Port of the OCR surface from Sources/LazyScanKit/Output/OCRService.swift. The Mac
// app uses Apple Vision; on Windows the shell provides an implementation backed by
// Windows.Media.Ocr (see LazyScan.App/Services/WindowsOcrService.cs).

/// <summary>One recognized line of text on a scanned page.</summary>
/// <param name="Text">The recognized text.</param>
/// <param name="BoundingBox">
/// Normalized (0...1) bounding box with a BOTTOM-LEFT origin — the Vision convention kept
/// deliberately, because it maps straight into PDF user space with no flip (see CONTRACTS.md).
/// Implementations converting from top-left pixel rects must flip:
/// ny = 1 - (y + h) / imageHeight.
/// </param>
/// <param name="Confidence">0...1.</param>
public sealed record OcrLine(string Text, RectD BoundingBox, float Confidence);

/// <summary>
/// Text recognition over a scanned image. Platform shells provide the implementation;
/// Core's PdfBuilder consumes the results.
/// </summary>
public interface IOcrService
{
    /// <summary>
    /// Run text recognition over <paramref name="image"/> and return one OcrLine per
    /// recognized line. Throws <see cref="ScanException"/> (ScanFailed) when recognition fails.
    ///
    /// The Mac implementation detects the language(s) on the page itself; Windows reads with the chosen
    /// language or, for Automatic, the installed packs. <paramref name="languages"/> is the language chosen in
    /// the options (<see cref="ScanSettings.OcrLanguage"/>), or null for Automatic; the Windows service
    /// reads with the first one when its pack is installed, the Mac service ignores it.
    /// </summary>
    Task<IReadOnlyList<OcrLine>> RecognizeLinesAsync(RgbaImage image, IReadOnlyList<string>? languages = null);
}
