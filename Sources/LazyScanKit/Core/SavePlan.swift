import Foundation

// Twin of windows/LazyScan.Core/SavePlan.cs.

/// A document of the queue as saved: its number (from 1), its pages in order and its name, if any.
/// Twin of C# `SaveDocument`.
public struct SaveDocument {
    public let number: Int
    public let pages: [ScannedPage]
    public let label: String?

    public init(number: Int, pages: [ScannedPage], label: String?) {
        self.number = number
        self.pages = pages
        self.label = label
    }
}

/// What saving the collected pages writes: the documents of the split plan (`DocumentSplitter`),
/// each its own file, and what is left out. The files of one save are written all or nothing
/// (`writeAllOrNothing`): a save that fails or is cancelled part-way removes what it wrote, so the
/// queue, which stays as it was, can be saved again without duplicates. Twin of C# `SavePlan`.
public struct SavePlan {
    public var documents: [SaveDocument]
    public var separatorPages: Int
    public var skippedPages: Int

    public init(documents: [SaveDocument], separatorPages: Int, skippedPages: Int) {
        self.documents = documents
        self.separatorPages = separatorPages
        self.skippedPages = skippedPages
    }

    /// The plan for saving `queue` with `options`.
    public static func make(_ queue: [ScannedPage], options: DocumentOptions) -> SavePlan {
        let plan = DocumentSplitter.plan(queue, options: options)
        let documents = plan.documents.map { document in
            SaveDocument(number: document.number, pages: document.pages.map { queue[$0] }, label: document.label)
        }
        return SavePlan(documents: documents, separatorPages: plan.separatorCount, skippedPages: plan.skippedCount)
    }

    /// The pages written, in every document.
    public var pageCount: Int { documents.reduce(0) { $0 + $1.pages.count } }
    /// Nothing would be written: every page is left out.
    public var isEmpty: Bool { documents.isEmpty }
    /// More than one file is written.
    public var isSplit: Bool { documents.count > 1 }

    /// The {index} of the document's file name: its number when the queue is split, else none.
    public func fileIndex(_ document: SaveDocument) -> Int? { isSplit ? document.number : nil }

    /// The save button: "Save 3 PDFs (7 pages)" for a split queue, otherwise
    /// `OutputFormat.saveTitle(pageCount:)` ("Save PDF (7 pages)").
    public func saveTitle(_ format: OutputFormat) -> String {
        guard isSplit else { return format.saveTitle(pageCount: pageCount) }
        switch format.queueFormat {
        case .word:
            return L10n.plural(pageCount, one: "Save {1} Word documents ({0} page)",
                               other: "Save {1} Word documents ({0} pages)", documents.count)
        case .text:
            return L10n.plural(pageCount, one: "Save {1} text files ({0} page)",
                               other: "Save {1} text files ({0} pages)", documents.count)
        default:
            return L10n.plural(pageCount, one: "Save {1} PDFs ({0} page)",
                               other: "Save {1} PDFs ({0} pages)", documents.count)
        }
    }

    /// `saveTitle` for a PDF that gets a password, as VoiceOver reads it: "Save password-protected PDF
    /// (7 pages)", "Save 3 password-protected PDFs (7 pages)".
    public var protectedSaveTitle: String {
        if isSplit {
            return L10n.plural(pageCount, one: "Save {1} password-protected PDFs ({0} page)",
                               other: "Save {1} password-protected PDFs ({0} pages)", documents.count)
        }
        guard pageCount > 0 else { return L10n.t("Save password-protected PDF") }
        return L10n.plural(pageCount, one: "Save password-protected PDF ({0} page)",
                           other: "Save password-protected PDF ({0} pages)")
    }

    /// What was left out, after the saved message: " — 1 skipped page was left out", " — 2 separator
    /// pages were left out", " — 2 separator pages and 1 skipped page were left out"; empty when nothing was.
    public func leftOutNote() -> String {
        let s = separatorPages, k = skippedPages
        if s == 0 && k == 0 { return "" }
        if s == 0 {
            return " " + L10n.plural(k, one: "— {0} skipped page was left out", other: "— {0} skipped pages were left out")
        }
        if k == 0 {
            return " " + L10n.plural(s, one: "— {0} separator page was left out", other: "— {0} separator pages were left out")
        }
        let separators = L10n.plural(s, one: "{0} separator page", other: "{0} separator pages")
        let skipped = L10n.plural(k, one: "{0} skipped page", other: "{0} skipped pages")
        return " " + L10n.t("— {0} and {1} were left out", separators, skipped)
    }

    /// "Saved 3 PDFs (7 pages, 1.2 MB): A.pdf, B.pdf, C.pdf and their text, A.txt, B.txt, C.txt — 2
    /// separator pages were left out" after a split save: `size` is the files' size together (nil
    /// when unknown), `textFileNames` the text files written beside the PDFs, and `noTextFound` the
    /// Word or text files with no text in them (" — no text was found" when that is all of them,
    /// " — no text was found in B.txt" otherwise).
    public func savedMessage(_ format: OutputFormat, fileNames: [String], size: String? = nil,
                             textFileNames: [String] = [], noTextFound: [String] = []) -> String {
        let pages: String = size.map { L10n.plural(pageCount, one: "{0} page, {1}", other: "{0} pages, {1}", $0) }
            ?? L10n.plural(pageCount, one: "{0} page", other: "{0} pages")
        let names: String = fileNames.joined(separator: ", ")
        let empty: String
        if noTextFound.isEmpty {
            empty = ""
        } else if noTextFound.count == fileNames.count {
            empty = " " + L10n.t("— no text was found")
        } else {
            empty = " " + L10n.t("— no text was found in {0}", noTextFound.joined(separator: ", "))
        }
        let count: Int = fileNames.count
        let saved: String
        switch format.queueFormat {
        case .word:
            saved = L10n.plural(count, one: "Saved {0} Word document ({1}): {2}", other: "Saved {0} Word documents ({1}): {2}", pages, names)
        case .text:
            saved = L10n.plural(count, one: "Saved {0} text file ({1}): {2}", other: "Saved {0} text files ({1}): {2}", pages, names)
        default:
            if textFileNames.isEmpty {
                saved = L10n.plural(count, one: "Saved {0} PDF ({1}): {2}", other: "Saved {0} PDFs ({1}): {2}", pages, names)
            } else {
                saved = L10n.plural(count, one: "Saved {0} PDF ({1}): {2} and their text, {3}",
                                    other: "Saved {0} PDFs ({1}): {2} and their text, {3}",
                                    pages, names, textFileNames.joined(separator: ", "))
            }
        }
        return saved + empty + leftOutNote()
    }

    /// The short status line's kind for `savedMessage`: "Saved 3 PDFs", or just "Saved" for Word and text.
    public func savedHead(_ format: OutputFormat, count: Int) -> StatusHead {
        switch format.queueFormat {
        case .word, .text: return .saved
        default: return .savedFiles(count, .pdf)
        }
    }

    /// The error when a split save fails: nothing of it is kept, and the queue is still there.
    public static func notSavedMessage(_ reason: String) -> String {
        L10n.t("None of the documents was saved; the pages are still in the queue. {0}", reason)
    }

    /// Why a document could not be written, for `notSavedMessage`: the message of a saving error
    /// without its "Saving failed: " (the message says that already), else the error's description.
    public static func failureReason(_ error: Error) -> String {
        if let scanError = error as? ScanError, case .exportFailed(let message) = scanError { return message }
        return error.localizedDescription
    }

    /// Runs `write`, which records every file it writes in `files`; when it throws (a failure or a
    /// cancel), every file recorded is removed again and the error goes on. Once `write` has
    /// finished the save counts as done.
    public static func writeAllOrNothing(_ files: WrittenFiles, _ write: () async throws -> Void) async throws {
        do {
            try await write()
        } catch {
            files.rollBack()
            throw error
        }
    }
}

/// A save that wrote nothing, with the message to show as it is: a split save undone
/// (`SavePlan.notSavedMessage`), or the separator sheet. Not a scanner failure, so the
/// troubleshooter does not record it. Twin of the IOException the Windows save throws.
public struct NotSavedError: LocalizedError, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// The files one save has written so far, so that a save that does not finish can remove them
/// (`SavePlan.writeAllOrNothing`). Twin of C# `WrittenFiles`.
public final class WrittenFiles {
    /// The files written, in order.
    public private(set) var urls: [URL] = []

    public init() {}

    public func add(_ url: URL) { urls.append(url) }

    /// Deletes every file written (best effort) and forgets them.
    public func rollBack() {
        for url in urls { try? FileManager.default.removeItem(at: url) }
        urls.removeAll()
    }
}
