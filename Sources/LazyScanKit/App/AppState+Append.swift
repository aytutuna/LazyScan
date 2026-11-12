import Foundation

// Twin of windows/LazyScan.App/AppViewModel.Append.cs: the queued pages added to the end of a
// PDF the user picks, as an incremental update (`PDFAppender`). The window asks the question
// (`confirmAppend`); the iPhone also wraps the file's reading and its update in the picked file's
// security scope and a coordinated access (`accessPDFForAppend`), which Windows has no need of. A PDF
// picked before scanning (`appendTarget`) is checked when it is picked (`checkAppendTarget`) and takes
// the queue when it is saved (`savePDF()`), which reads it again.

extension AppState {
    /// There are pages to add (some are not left out), in reading order, and nothing else is running.
    public var canAppendPages: Bool {
        !isBusy && !sidesNeedOrder && SavePlan.make(scannedPages, options: settings.document).pageCount > 0
    }

    /// Makes Save add the queue to the PDF at `url` (read when the pages are added, not now) until the
    /// pages are in or `clearAppendTarget()` is called.
    public func setAppendTarget(_ url: URL) {
        appendTarget = url
    }

    /// Reads the PDF at `url` before it becomes the append target, so a file that can never take the pages
    /// (password-protected, damaged, read-only, open in another app) is refused now with what to do, and
    /// the signed or PDF/A question is asked now. True when the file can take them (and the question, if
    /// any, got a yes): the caller then calls `setAppendTarget`. The answer is kept for the file as it is
    /// now; `appendToPDF` asks again only when the file has changed since.
    public func checkAppendTarget(_ url: URL) async -> Bool {
        let access = accessPDFForAppend
        do {
            let (target, seen): (PDFAppendTarget, FileStamp?) = try await Task.detached(priority: .userInitiated) { () throws -> (PDFAppendTarget, FileStamp?) in
                try Self.accessing(url, writing: false, through: access) { (file: URL) throws -> (PDFAppendTarget, FileStamp?) in
                    (try PDFAppender.inspect(path: file.path), FileStamp(of: file))
                }
            }.value
            if let question = target.confirmMessage {
                var yes = false
                if let ask = confirmAppend { yes = await ask(question) }
                if !yes { return false }
            }
            confirmedAppend = (url: url, stamp: seen)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Save writes a new file again.
    public func clearAppendTarget() {
        appendTarget = nil
        confirmedAppend = nil
    }

    /// Adds the pages the queue would save (all its documents, in order; pages left out stay out) to
    /// the end of the PDF at `url`, stored as the PDF size and the text layer settings say. The file
    /// is read first: a password-protected, damaged or unreadable file, or one that is read-only or
    /// open in another app, is refused with what to do, and the pages stay in the queue. The file
    /// decides the rest: no password is added (the password switch is for new files) and a PDF/A file
    /// stays one where it can (`PDFAppender.keepsPdfA`), with a question first where it may not, or
    /// where it is signed. Once the pages are in, the queue is cleared and the file is offered like a
    /// saved one, with the after-save action, and the `appendTarget` is cleared.
    public func appendToPDF(at url: URL) {
        guard !scannedPages.isEmpty else { return }
        guard !sidesNeedOrder else {
            // The answer only puts the pages in order; the file is picked again.
            afterSidesAnswer = {}
            asksSidesOrder = true
            return
        }
        let s: ScanSettings = settings
        let access = accessPDFForAppend
        runExclusive { flag in
            // Let page swaps and turns that were clicked before land first.
            await self.pageEditChain?.value
            let queued: [ScannedPage] = self.scannedPages
            guard !queued.isEmpty else { return }
            let plan: SavePlan = SavePlan.make(queued, options: s.document)
            guard !plan.isEmpty else {
                self.errorMessage = PageFilter.nothingToSaveMessage
                self.errorTitle = PageFilter.nothingSavedTitle
                self.statusMessage = L10n.t("{0}.", DocumentSplitter.queueSummary(queued, options: s.document))
                return
            }
            let name: String = url.lastPathComponent
            self.statusMessage = L10n.t("Reading {0}…", name)
            let (target, seen): (PDFAppendTarget, FileStamp?) = try await Task.detached(priority: .userInitiated) { () throws -> (PDFAppendTarget, FileStamp?) in
                try Self.accessing(url, writing: false, through: access) { (file: URL) throws -> (PDFAppendTarget, FileStamp?) in
                    (try PDFAppender.inspect(path: file.path), FileStamp(of: file))
                }
            }.value
            let answered: Bool = url == self.appendTarget && (self.confirmedAppend.map { $0.url == url && $0.stamp == seen } ?? false)
            if !answered, let question = target.confirmMessage {
                var yes = false
                if let ask = self.confirmAppend { yes = await ask(question) }
                if !yes {
                    self.statusMessage = L10n.t("Nothing was added to {0}.", name)
                    return
                }
            }
            var collected: [ScannedPage] = []
            for document in plan.documents {
                collected.append(contentsOf: document.pages)
            }
            let pages: [ScannedPage] = collected
            let count: Int = pages.count
            let failures = PDFTextFailures()
            self.statusMessage = s.pdfSearchable ? L10n.t("Running OCR and adding pages…") : L10n.t("Adding pages…")
            let backup: URL? = self.keepsSavedForUndo ? self.spoolDirectory.appendingPathComponent("\(UUID().uuidString).pdf") : nil
            let (result, kept, stamp): (PDFAppendResult, Bool, FileStamp?) = try await Task.detached(priority: .userInitiated) { () throws -> (PDFAppendResult, Bool, FileStamp?) in
                let report: (String) -> Void = { [weak self] msg in
                    Task { @MainActor in self?.statusMessage = msg }
                }
                let reportAdding: (String, StatusDetail) -> Void = { [weak self] msg, detail in
                    Task { @MainActor in self?.setStatus(msg, detail) }
                }
                let inputs: [PDFPageInput] = try PDFBuilder.pageInputs(
                    pages, pdfSize: s.output.pdfSize, progress: report, shouldContinue: { !flag.isCancelled },
                    textLayer: Self.textLayer(searchable: s.pdfSearchable, collecting: nil, pages: pages, failures: failures))
                reportAdding(L10n.plural(count, one: "Adding {0} page to {1}…", other: "Adding {0} pages to {1}…", name),
                             StatusDetail(head: .addingPages(count)))
                return try Self.accessing(url, writing: true, through: access) { (file: URL) throws -> (PDFAppendResult, Bool, FileStamp?) in
                    // A copy from before, for Undo; without one the save cannot be undone.
                    let copied: Bool = backup.map { (try? FileManager.default.copyItem(at: file, to: $0)) != nil } ?? false
                    do {
                        let added: PDFAppendResult = try PDFAppender.appendToFile(path: file.path, pages: inputs,
                                                                                  shouldContinue: { !flag.isCancelled })
                        return (added, copied, FileStamp(of: file))
                    } catch {
                        if copied, let backup { try? FileManager.default.removeItem(at: backup) }
                        throw error
                    }
                }
            }.value
            self.lastPDFByteCount = Int64(result.bytes)
            self.lastPDFProtected = false
            // The URL picked, not the result's path: on the iPhone it carries the file's security scope,
            // kept open for the file actions after the save (`scopedSavedURL`).
            self.lastSavedURLs = [url]
            if self.scopedSavedURL == nil, url.startAccessingSecurityScopedResource() {
                self.scopedSavedURL = url
            }
            let earlierTarget: URL? = self.appendTarget
            self.appendTarget = nil
            self.confirmedAppend = nil
            self.dropSaved(queued, appended: backup.map { AppendedPDF(url: url, backup: $0, stamp: stamp, earlierTarget: earlierTarget) },
                           undoable: kept)
            self.resetFlow()
            let size: String = ByteCountFormatter.string(fromByteCount: Int64(result.bytes), countStyle: .file)
            var message: String = PDFAppender.addedMessage(count, fileName: name, pageCount: result.pageCount, size: size)
            message += plan.leftOutNote()
            if s.output.protect { message = L10n.t("{0}. {1}", message, PDFAppender.noPasswordNote) }
            if let note = failures.note { self.errorMessage = note }
            self.setStatus(message, StatusDetail(head: .pagesAdded(count, queue: nil, blank: 0, split: 0)))
            self.runAfterSave(s.output.afterSave, saved: [url])
        }
    }

    /// `body` run on the file at `url` through `access` (the iPhone's `accessPDFForAppend`), or on
    /// `url` itself when there is none.
    nonisolated static func accessing<T>(_ url: URL, writing: Bool,
                                         through access: (@Sendable (URL, Bool, (URL) throws -> Void) throws -> Void)?,
                                         _ body: (URL) throws -> T) throws -> T {
        guard let access else { return try body(url) }
        var result: T?
        try access(url, writing) { (file: URL) throws -> Void in
            result = try body(file)
        }
        guard let result else {
            throw PDFAppendError(.missing, PDFAppender.message(.missing, url.lastPathComponent))
        }
        return result
    }
}
