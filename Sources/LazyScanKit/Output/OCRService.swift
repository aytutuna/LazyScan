import CoreGraphics
import Foundation
import Vision

/// One recognized word of an `OCRLine`, with its own box.
public struct OCRWord {
    public let text: String
    /// Vision-normalized bounding box (origin bottom-left).
    public let boundingBox: CGRect
    public init(text: String, boundingBox: CGRect) {
        self.text = text
        self.boundingBox = boundingBox
    }
}

/// One recognized line of text on a scanned page.
public struct OCRLine {
    public let text: String
    /// Vision-normalized bounding box (origin bottom-left).
    public let boundingBox: CGRect
    public let confidence: Float
    /// The line's words with their own boxes, when the recognizer gave them; the PDF text layer
    /// places each one, and the line as a whole when there are none.
    public let words: [OCRWord]?
    public init(text: String, boundingBox: CGRect, confidence: Float, words: [OCRWord]? = nil) {
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.words = words
    }
}

public enum OCRService {
    /// Run accurate text recognition over `image` and return one OCRLine per observation
    /// (top candidate). Throws `ScanError.scanFailed` when the Vision handler fails.
    ///
    /// Recognition is universal: Vision detects the language(s) on the page itself, so no
    /// configuration is required. The `languages` parameter is kept for API stability but
    /// no longer constrains recognition.
    public static func recognizeLines(in image: CGImage, languages: [String] = []) throws -> [OCRLine] {
        _ = languages
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        // Offer every language Vision knows so mixed-language and non-Latin pages
        // recognize too; automatic detection narrows per page.
        if let supported = try? request.supportedRecognitionLanguages(), !supported.isEmpty {
            request.recognitionLanguages = supported
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw ScanError.scanFailed(reason: { error.localizedDescription })
        }

        let observations = request.results ?? []
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return OCRLine(text: candidate.string,
                           boundingBox: observation.boundingBox,
                           confidence: candidate.confidence,
                           words: words(of: candidate))
        }
    }

    /// The runs of non-space characters of `candidate`, each with Vision's box for it; nil when the
    /// line has none or Vision gives no box for one of them.
    private static func words(of candidate: VNRecognizedText) -> [OCRWord]? {
        let string = candidate.string
        var words: [OCRWord] = []
        var start: String.Index?
        var index = string.startIndex
        while true {
            let atEnd = index == string.endIndex
            if atEnd || string[index].isWhitespace {
                if let from = start {
                    let range = from..<index
                    guard let box = try? candidate.boundingBox(for: range)?.boundingBox else { return nil }
                    words.append(OCRWord(text: String(string[range]), boundingBox: box))
                    start = nil
                }
            } else if start == nil {
                start = index
            }
            if atEnd { break }
            index = string.index(after: index)
        }
        return words.isEmpty ? nil : words
    }

    /// The candidates Vision must be at least this sure of to count when turning pages upright.
    static let orientationMinConfidence: Float = 0.3

    /// What fast text recognition reads on `image` as it is, for turning pages upright
    /// (`OrientationDecision`): the lines Vision is more than `orientationMinConfidence` sure of,
    /// with no language correction, so text read the wrong way up is not mended into words. Throws
    /// `ScanError.scanFailed` when the Vision handler fails.
    public static func orientationScore(in image: CGImage) throws -> OrientationScore {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw ScanError.scanFailed(reason: { error.localizedDescription })
        }
        let lines: [String] = (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first,
                  candidate.confidence > orientationMinConfidence else { return nil }
            return candidate.string
        }
        return OrientationScore.of(lines)
    }
}

/// Reads a page for turning pages upright (`OrientationDecision`) with Vision's fast text
/// recognition (`OCRService.orientationScore(in:)`). The Mac counterpart of the Windows
/// `WindowsOrientationScorer`.
public struct VisionOrientationScorer: OrientationScorer {
    public init() {}

    /// Vision's text recognition is always there on macOS 14.
    public var isAvailable: Bool { true }

    public func score(_ image: RgbaImage) throws -> OrientationScore {
        guard let cgImage = image.makeCGImage() else {
            throw ScanError.scanFailed(reason: { L10n.t("the page could not be prepared for reading.") })
        }
        return try OCRService.orientationScore(in: cgImage)
    }
}
