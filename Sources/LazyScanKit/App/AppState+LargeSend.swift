import Foundation

// Files too big for most mail services (`SaveActions.largeAttachmentBytes`) are not handed to Mail or the
// share sheet until the user has seen their size.

/// Files held back from Mail or the share sheet for their size. `canSaveSmaller` is true while the save
/// that wrote them is still held for Undo and was not made at the smallest sizes already.
public struct LargeSendNotice: Equatable, Sendable {
    public let action: FileAction
    public let urls: [URL]
    public let bytes: Int64
    public let canSaveSmaller: Bool

    public var title: String {
        L10n.plural(urls.count, one: "Large file", other: "Large files")
    }

    public var message: String {
        L10n.plural(urls.count,
                    one: "This file is {1}. Many mail services reject attachments over {2}.",
                    other: "These files are {1}. Many mail services reject attachments over {2}.",
                    Self.sizeText(bytes), Self.sizeText(SaveActions.largeAttachmentBytes))
    }

    static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

extension AppState {
    /// The settings a save uses: the chosen ones, or the smallest sizes while Save smaller saves again.
    var saveSettings: ScanSettings {
        guard savingSmaller else { return settings }
        var smaller: ScanSettings = settings
        smaller.output.pdfSize = .smallest
        smaller.jpegQuality = SaveActions.smallestJPEGQuality
        return smaller
    }

    func attachmentBytes(of urls: [URL]) -> Int64 {
        urls.reduce(0) { (total: Int64, url: URL) -> Int64 in
            let size: NSNumber? = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
            return total + (size?.int64Value ?? 0)
        }
    }

    /// Holds an email or share of large files back and says so in `largeSendNotice`; false when they are small
    /// enough or the action sends nothing.
    func holdsBackLargeSend(_ action: FileAction, urls: [URL]) -> Bool {
        guard action == .email || action == .share else { return false }
        let bytes: Int64 = attachmentBytes(of: urls)
        guard bytes > SaveActions.largeAttachmentBytes else { return false }
        largeSendNotice = LargeSendNotice(action: action, urls: urls, bytes: bytes, canSaveSmaller: canSaveSmaller(urls))
        return true
    }

    /// The pages of the save that wrote `urls` are still held, and saving them again at the smallest sizes
    /// changes something.
    private func canSaveSmaller(_ urls: [URL]) -> Bool {
        guard let held = savedUndo, !held.smaller, held.appended == nil,
              Set(held.files).isSuperset(of: urls) else { return false }
        if savesPictures {
            return settings.format == .jpeg && settings.jpegQuality > SaveActions.smallestJPEGQuality
        }
        return settings.format.queueFormat == .pdf && settings.output.pdfSize != .smallest
    }

    /// The iPhone's Save writes a picture of each page for an image format; everything else is one file.
    private var savesPictures: Bool {
        platform == .ios && appendTarget == nil && settings.format.isImageFormat
    }

    /// Sends the files the notice holds back, as asked.
    public func sendLargeAnyway(_ notice: LargeSendNotice) {
        largeSendNotice = nil
        runFileAction(notice.action, urls: notice.urls, ignoringSize: true)
    }

    /// Takes the held save back and saves its pages again at the smallest sizes, replacing the files, then
    /// sends the new ones as the notice's action says (again held back if they are still too big).
    public func saveSmaller(_ notice: LargeSendNotice) {
        largeSendNotice = nil
        guard notice.canSaveSmaller, canUndoSave, !isBusy else { return }
        smallerSend = notice.action
        undoSave()
    }

    func saveAgainSmaller(thenSending action: FileAction) {
        let pictures: Bool = savesPictures
        savingSmaller = true
        if action == .email {
            saveAndEmail(images: pictures)
        } else {
            saveAndShare(images: pictures)
        }
        if !isBusy { savingSmaller = false }
    }
}
