import Foundation

// Undo after a save, for the iPhone (`AppState.keepsSavedForUndo`). Swift only: the Mac and Windows delete the
// spool files of a saved queue at once. Chosen from the saved bar and held until the next scan, import or
// save (the queue gets a page, or another file is reported as saved), when the held pages are let go.
// Pages sent to a paired computer or a cloud folder, and files shared or emailed, are out of reach.

/// A PDF the save added pages to, and the copy taken of it first.
struct AppendedPDF {
    var url: URL
    var backup: URL
}

/// What a save leaves for `undoSave()`: the queue it saved, as it was (spool files kept), the files it wrote,
/// the files the saved bar showed, the PDF it added pages to, and the steps the save reset.
struct SavedUndo {
    var pages: [ScannedPage]
    var files: [URL]
    var shown: [URL]
    var appended: AppendedPDF?
    var taskFlow: TaskFlow?
    var cameraSides: CameraSides?
}

extension AppState {
    /// The last save can be taken back: its files deleted (or the PDF it added to put back as it was) and
    /// its pages in the queue again.
    public var canUndoSave: Bool { savedUndo != nil }

    /// "Save undone: the pages are in the queue again."
    static var undoneMessage: String { L10n.t("Save undone: the pages are in the queue again.") }

    /// "Save undone: Contract.pdf is as it was, and the pages are in the queue again."
    static func undoneAppendMessage(_ fileName: String) -> String {
        L10n.t("Save undone: {0} is as it was, and the pages are in the queue again.", fileName)
    }

    /// Takes the last save back: deletes every file it wrote (one already gone is no error), puts the PDF it
    /// added pages to back from the copy taken before (through the picked file's access, as the pages were
    /// added), and puts the pages in the queue again in their order, with their spool files and edits, the
    /// task's steps and the PDF to add to. A PDF that cannot be put back stops the undo with the reason and
    /// leaves the save as it was.
    public func undoSave() {
        guard !isBusy, let held = savedUndo else { return }
        let access = accessPDFForAppend
        runExclusive { _ in
            self.statusMessage = L10n.t("Undoing the save…")
            if let appended = held.appended {
                do {
                    try await Task.detached(priority: .userInitiated) {
                        _ = try Self.accessing(appended.url, writing: true, through: access) { (file: URL) throws -> Bool in
                            _ = try FileManager.default.replaceItemAt(file, withItemAt: appended.backup)
                            return true
                        }
                    }.value
                } catch {
                    throw NotSavedError(L10n.t("{0} could not be put back as it was: {1}", appended.url.lastPathComponent,
                                               error.localizedDescription))
                }
            }
            for url in held.files {
                try? FileManager.default.removeItem(at: url)
            }
            self.savedUndo = nil
            self.scannedPages = held.pages
            self.lastSavedURLs = []
            if let url = held.appended?.url { self.appendTarget = url }
            if let flow = held.taskFlow, flow.steps == self.taskFlow?.steps { self.taskFlow = flow }
            if held.cameraSides != nil, self.cameraSides != nil { self.cameraSides = held.cameraSides }
            self.statusMessage = held.appended.map { Self.undoneAppendMessage($0.url.lastPathComponent) } ?? Self.undoneMessage
        }
    }

    /// Lets the held save go: its pages' spool files, the copy of the PDF and the spreads only they used.
    func discardSavedUndo() {
        guard let held = savedUndo else { return }
        savedUndo = nil
        deleteSpoolFiles(of: held.pages)
        if let backup = held.appended?.backup { try? FileManager.default.removeItem(at: backup) }
        pruneSpreads()
    }
}
