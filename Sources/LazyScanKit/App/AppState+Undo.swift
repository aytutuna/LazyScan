import Foundation

// Undo after a save, for the iPhone (`AppState.keepsSavedForUndo`). Swift only: the Mac and Windows delete the
// spool files of a saved queue at once. Chosen from the saved bar and held until the next scan, import or
// save (the queue gets a page, or another file is reported as saved), when the held pages are let go.
// Pages sent to a paired computer or a cloud folder, and files shared or emailed, are out of reach.

/// A file's size and modification date, to tell on Undo whether it is still as the save left it.
struct FileStamp: Equatable {
    var size: Int
    var modified: Date?

    init?(of url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        modified = attributes[.modificationDate] as? Date
    }
}

/// A PDF the save added pages to, the copy taken of it first, how it was after the pages went in, and the
/// PDF the next save was set to add to before the save cleared it.
struct AppendedPDF {
    var url: URL
    var backup: URL
    var stamp: FileStamp?
    var earlierTarget: URL?
}

/// What a save leaves for `undoSave()`: the queue it saved, as it was (spool files kept), the files it wrote,
/// the files the saved bar showed, the PDF it added pages to, and the steps the save reset. `stamps` is how
/// each file was when it was written.
struct SavedUndo {
    var pages: [ScannedPage]
    var files: [URL]
    var stamps: [URL: FileStamp] = [:]
    var shown: [URL]
    var appended: AppendedPDF?
    var taskFlow: TaskFlow?
    var cameraSides: CameraSides?
}

/// What `undoRemove()` puts back: the pages taken out of the queue, in the order they were taken, each with the
/// place it had when its turn came (the queue as it was once the pages before it in this list were gone), their
/// spool files kept, and the steps of the task as they were before the first of them.
struct RemovedUndo {
    var pages: [(page: ScannedPage, index: Int)]
    var cleared: Bool
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
    /// task's steps and the PDF to add to. A file changed since the save (another size or date) is kept and
    /// the undo refused, as is one that cannot be deleted or put back: the reason is shown and the save stays
    /// held, as far as it still stands.
    public func undoSave() {
        guard !isBusy, let held = savedUndo else { return }
        let access = accessPDFForAppend
        runExclusive { _ in
            self.statusMessage = L10n.t("Undoing the save…")
            if let appended = held.appended {
                do {
                    try await Task.detached(priority: .userInitiated) {
                        _ = try Self.accessing(appended.url, writing: true, through: access) { (file: URL) throws -> Bool in
                            if let stamp = appended.stamp, FileStamp(of: file) != stamp {
                                throw NotSavedError(L10n.t("{0} was changed after the pages were added, so Undo left it as it is.",
                                                           appended.url.lastPathComponent))
                            }
                            // The copy goes next to the file first, so the swap stays on its volume.
                            let manager = FileManager.default
                            let folder = try manager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                         appropriateFor: file, create: true)
                            defer { try? manager.removeItem(at: folder) }
                            let staged = folder.appendingPathComponent(file.lastPathComponent)
                            try manager.copyItem(at: appended.backup, to: staged)
                            _ = try manager.replaceItemAt(file, withItemAt: staged)
                            return true
                        }
                    }.value
                } catch let error as NotSavedError {
                    throw error
                } catch {
                    throw NotSavedError(L10n.t("{0} could not be put back as it was: {1}", appended.url.lastPathComponent,
                                               error.localizedDescription))
                }
                try? FileManager.default.removeItem(at: appended.backup)
            }
            let files = held.files
            let stamps = held.stamps
            let failures: [(url: URL, reason: String)] = try await Task.detached(priority: .userInitiated) {
                () throws -> [(url: URL, reason: String)] in
                for url in files {
                    if let stamp = stamps[url], let now = FileStamp(of: url), now != stamp {
                        throw NotSavedError(L10n.t("{0} was changed after it was saved, so Undo left it as it is.",
                                                   url.lastPathComponent))
                    }
                }
                var failed: [(url: URL, reason: String)] = []
                for url in files {
                    do {
                        try Self.coordinateWriting(url, options: .forDeleting) { try FileManager.default.removeItem(at: $0) }
                    } catch where !Self.isMissing(error) {
                        failed.append((url: url, reason: error.localizedDescription))
                    } catch {}
                }
                return failed
            }.value
            if let first = failures.first {
                // The ones deleted are gone; what is left stays held, to try again.
                self.savedUndo?.files = failures.map { $0.url }
                throw NotSavedError(L10n.t("{0} could not be deleted: {1}", first.url.lastPathComponent, first.reason))
            }
            self.savedUndo = nil
            self.scannedPages = held.pages
            self.lastSavedURLs = []
            if let appended = held.appended { self.appendTarget = appended.earlierTarget }
            if let flow = held.taskFlow, flow.steps == self.taskFlow?.steps { self.taskFlow = flow }
            if held.cameraSides != nil, self.cameraSides != nil { self.cameraSides = held.cameraSides }
            self.statusMessage = held.appended.map { Self.undoneAppendMessage($0.url.lastPathComponent) } ?? Self.undoneMessage
        }
    }

    /// Pages were taken out of the queue (removed, cleared, or backs left out) and can be put back.
    public var canUndoRemove: Bool { removedUndo != nil }

    /// "Page removed", "3 pages removed" or "Cleared 12 pages": what the hold is, for the Undo beside it.
    public var removedTitle: String {
        guard let held = removedUndo else { return "" }
        return held.cleared ? Self.clearedMessage(held.pages.count) : Self.removedMessage(held.pages.count)
    }

    static func removedMessage(_ count: Int) -> String {
        L10n.plural(count, one: "Page removed", other: "{0} pages removed")
    }

    static func clearedMessage(_ count: Int) -> String {
        L10n.plural(count, one: "Cleared {0} page", other: "Cleared {0} pages")
    }

    /// Takes the pages out of the queue into the hold, keeping their spool files, and says how many went.
    /// A hold already there grows, so one Undo puts back everything removed since the last scan, save or task
    /// change. `flowBefore` is the task's steps when they were changed before the pages left.
    @discardableResult
    func holdRemoved(_ ids: Set<UUID>, cleared: Bool = false, flowBefore: TaskFlow? = nil) -> Int {
        var hold = removedUndo ?? RemovedUndo(pages: [], cleared: false, taskFlow: flowBefore ?? taskFlow,
                                              cameraSides: cameraSides)
        var gone = 0
        for (index, page) in scannedPages.enumerated() where ids.contains(page.id) {
            hold.pages.append((page: page, index: index - gone))
            gone += 1
        }
        guard gone > 0 else { return 0 }
        hold.cleared = cleared && hold.pages.count == gone
        removedUndo = hold
        scannedPages.removeAll { ids.contains($0.id) }
        return gone
    }

    /// Puts the held pages back in the queue, each where it was, with its spool files and edits, and the steps
    /// of the task as they were. A page whose file has gone is left out and the status says so.
    public func undoRemove() {
        guard !isBusy, !readsQueue, let held = removedUndo else { return }
        removedUndo = nil
        var queue = scannedPages
        var lost = 0
        for (page, index) in held.pages.reversed() {
            let files = [page.fileURL, page.alternate?.fileURL].compactMap { $0 }
            if files.contains(where: { !FileManager.default.fileExists(atPath: $0.path) }) {
                lost += 1
                continue
            }
            queue.insert(page, at: min(index, queue.count))
        }
        scannedPages = queue
        if let flow = held.taskFlow, flow.steps == taskFlow?.steps { taskFlow = flow }
        if held.cameraSides != nil, cameraSides != nil { cameraSides = held.cameraSides }
        let restored = held.pages.count - lost
        var message = L10n.plural(restored, one: "Page restored", other: "{0} pages restored")
        if lost > 0 {
            message = L10n.plural(lost, one: "{0} page could not be restored", other: "{0} pages could not be restored")
        }
        statusMessage = message
    }

    /// Lets the held pages go: their spool files and the spreads only they used.
    func discardRemovedUndo() {
        guard let held = removedUndo else { return }
        removedUndo = nil
        deleteSpoolFiles(of: held.pages.map { $0.page })
        pruneSpreads()
    }

    /// The error says the file is not there.
    nonisolated static func isMissing(_ error: Error) -> Bool {
        let code = (error as? CocoaError)?.code
        return code == .fileNoSuchFile || code == .fileReadNoSuchFile
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
