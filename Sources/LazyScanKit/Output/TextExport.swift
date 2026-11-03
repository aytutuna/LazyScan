import Foundation

// Twin of windows/LazyScan.Core/TextExport.cs: the same bytes and the same messages.

/// The text file of a save (`OutputFormat.text`, or the text beside a PDF with
/// `OutputOptions.alsoSaveText`), and what the app says about text it saved or could not read. The
/// text is `OCRText.plainText`: UTF-8 without a byte order mark, "\n" line breaks, one line of text
/// per line on the page, a blank line between paragraphs and two between pages.
public enum TextExport {
    /// The bytes of the text file for `pages`.
    public static func encode(_ pages: [OCRPage]) -> Data {
        Data(OCRText.plainText(pages).utf8)
    }

    /// Whether any page has text to save.
    public static func hasText(_ pages: [OCRPage]) -> Bool {
        !OCRText.plainText(pages).isEmpty
    }

    /// "Saved 3-page Word document: Scan 1.docx", "Saved 1-page text file: Scan 1.txt", with
    /// " — no text was found" when the pages had none (the file is saved all the same).
    public static func savedMessage(format: OutputFormat, pageCount: Int, fileName: String, hasText: Bool) -> String {
        if format == .word {
            return hasText ? L10n.t("Saved {0}-page Word document: {1}", pageCount, fileName)
                : L10n.t("Saved {0}-page Word document: {1} — no text was found", pageCount, fileName)
        }
        return hasText ? L10n.t("Saved {0}-page text file: {1}", pageCount, fileName)
            : L10n.t("Saved {0}-page text file: {1} — no text was found", pageCount, fileName)
    }

    /// " and its text, Scan 1.txt": added after a PDF's name when its text was saved beside it.
    public static func sidecarSuffix(_ textFileName: String) -> String {
        " " + L10n.t("and its text, {0}", textFileName)
    }

    /// What the user reads when the text could not be read: "The text could not be read: no OCR
    /// language … ." from the OCR error's message ("Scan failed: OCR failed: …").
    public static func recognitionFailed(_ ocrMessage: String) -> String {
        L10n.t("The text could not be read: {0}", reason(ocrMessage))
    }

    /// "The PDF was saved, but not its text file: …": the text beside a PDF could not be read or
    /// written (`message`, an OCR or file error); the PDF is kept.
    public static func sidecarFailed(_ message: String) -> String {
        L10n.t("The PDF was saved, but not its text file: {0}", reason(message))
    }

    /// What the user reads when a scan to be saved at once as Word or text could not be (its text
    /// could not be read, its file could not be written, or the save was cancelled) and its pages
    /// went to the queue instead: "The 3 pages are kept in the queue: press Save Word once the text
    /// can be read, or choose PDF to save them as scanned." when `textUnreadable` (OCR failed),
    /// "… press Save Word to try again, or choose PDF …" for any other failure, or
    /// "Cancelled — the page is kept in the queue.".
    public static func keptInQueue(format: OutputFormat, pageCount: Int, cancelled: Bool,
                                   textUnreadable: Bool = true) -> String {
        if cancelled { return cancelledInQueue(pageCount) }
        if textUnreadable {
            return L10n.plural(pageCount,
                               one: "The page is kept in the queue: press {1} once the text can be read, or choose PDF to save it as scanned.",
                               other: "The {0} pages are kept in the queue: press {1} once the text can be read, or choose PDF to save them as scanned.",
                               format.saveTitle)
        }
        return L10n.plural(pageCount,
                           one: "The page is kept in the queue: press {1} to try again, or choose PDF to save it as scanned.",
                           other: "The {0} pages are kept in the queue: press {1} to try again, or choose PDF to save them as scanned.",
                           format.saveTitle)
    }

    /// What the user reads when a PDF or pictures to be saved at once could not be written, or the save
    /// was cancelled, and the pages not written went to the queue: "Not saved — the 3 pages are kept in
    /// the queue: press Save PDF to try again." or "Cancelled — the page is kept in the queue."; with
    /// `written` of the `pageCount` pictures saved, "2 of 5 pages saved — the other 3 are kept in the
    /// queue: press Save 3 JPEGs to try again." or "Cancelled — 2 of 5 pages saved; the other 3 are kept
    /// in the queue.". `saveTitle` is the button that saves them.
    public static func pagesKeptInQueue(pageCount: Int, written: Int, cancelled: Bool, saveTitle: String) -> String {
        if written == 0 {
            if cancelled { return cancelledInQueue(pageCount) }
            return L10n.plural(pageCount,
                               one: "Not saved — the page is kept in the queue: press {1} to try again.",
                               other: "Not saved — the {0} pages are kept in the queue: press {1} to try again.",
                               saveTitle)
        }
        let rest = pageCount - written
        if cancelled {
            return L10n.plural(rest,
                               one: "Cancelled — {1} of {2} pages saved; the other one is kept in the queue.",
                               other: "Cancelled — {1} of {2} pages saved; the other {0} are kept in the queue.",
                               written, pageCount)
        }
        return L10n.plural(rest,
                           one: "{1} of {2} pages saved — the other one is kept in the queue: press {3} to try again.",
                           other: "{1} of {2} pages saved — the other {0} are kept in the queue: press {3} to try again.",
                           written, pageCount, saveTitle)
    }

    private static func cancelledInQueue(_ pageCount: Int) -> String {
        L10n.plural(pageCount,
                    one: "Cancelled — the page is kept in the queue.",
                    other: "Cancelled — the {0} pages are kept in the queue.")
    }

    /// "Copied the text of page 2." or "No text was found on page 2." after Copy Text; `pageNumber`
    /// counts from 1.
    public static func copiedMessage(pageNumber: Int, hasText: Bool) -> String {
        hasText ? L10n.t("Copied the text of page {0}.", pageNumber) : L10n.t("No text was found on page {0}.", pageNumber)
    }

    /// An error's message without the "Scan failed: " and "OCR failed: " it starts with, ending in a
    /// full stop.
    private static func reason(_ message: String) -> String {
        var reason = message.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Scan failed: ", "OCR failed: "] where reason.hasPrefix(prefix) {
            reason = String(reason.dropFirst(prefix.count))
        }
        if reason.isEmpty { reason = L10n.t("the text recognition did not work") }
        if !reason.hasSuffix(".") { reason += "." }
        return reason
    }
}

/// Text the user asked for could not be read or written; its message says why (a missing OCR
/// language names the setting that adds one). Not a `ScanError`: the troubleshooter does not record it.
public struct TextOutputError: LocalizedError, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}
