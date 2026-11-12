import Foundation

/// What the camera says for a step: one line to act on (ten words at most) and the fuller help behind it
/// (25 words at most), as a task's `TaskStep` does for the scanner glass.
public struct CameraStepText: Equatable, Sendable {
    public let prompt: String
    public let help: String

    public init(prompt: String, help: String) {
        self.prompt = prompt
        self.help = help
    }
}

/// The camera's words for every task (I14): what to point the phone at and how the steps go, where
/// `TaskCatalog` speaks of the scanner glass and the feeder. Keyed by `ScanTask`; the two-sided task and
/// the book have a line for each way the camera takes them (`TaskOptions.cameraFrontsFirst`,
/// `cameraSpreads`). Swift only: the Windows app takes no camera shots, so `TaskCatalog` stays the one
/// source of the tasks' titles and the scanner's steps on both platforms.
public enum CameraTaskCatalog {
    /// Flip & capture: after each front, its back.
    public static var turnOverPrompt: String { L10n.t("Turn the sheet over and take its back.") }
    public static var turnOverHelp: String { L10n.t("No back side skips an empty back. Then take the next sheet's front.") }
    /// Flip & capture, once a sheet's back is in or skipped.
    public static var nextFrontPrompt: String { L10n.t("Take the next sheet's front.") }
    /// Fronts first, once every front is in.
    public static var backsPrompt: String { L10n.t("Now take each back, first sheet first.") }
    public static var backsHelp: String { L10n.t("Turn the sheets over. The fronts and backs are put in order when the last back is in.") }
    /// The batch's next page starts a new document.
    public static var newDocumentPrompt: String { L10n.t("The next page starts a new document.") }
    public static var newDocumentCancelled: String { L10n.t("No new document will start.") }

    public static var noBackLabel: String { L10n.t("No back side") }
    public static var startBacksLabel: String { L10n.t("Now the backs") }
    public static var putInOrderLabel: String { L10n.t("Put in order") }
    public static var combineLabel: String { L10n.t("Combine anyway") }
    public static var newDocumentLabel: String { L10n.t("New document") }
    public static var flipLabel: String { L10n.t("Flip & capture") }
    public static var frontsFirstLabel: String { L10n.t("Fronts, then backs") }
    public static var pageByPageLabel: String { L10n.t("Page by page") }
    public static var wholeSpreadLabel: String { L10n.t("Whole spread") }
    /// A book read from right to left: the right page of each spread comes first.
    public static var rightToLeftLabel: String { L10n.t("Right to left") }
    public static var rightToLeftHint: String { L10n.t("Arabic, Hebrew, manga: the right page of each spread comes first.") }
    /// Under the Book picker while a scanner is in use: the choice steers only the photos brought in.
    public static var spreadsWithScannerNote: String { L10n.t("For photos from Photos and Files. The scanner's spreads are always cut at the spine.") }
    /// Why a patch code on a photographed page may not be read: its bars are measured in inches.
    public static var separatorHint: String { L10n.t("Read once the page matches a paper size") }

    /// The camera's words for `task`, as `options` take it: the two-sided task's flip & capture or fronts
    /// first, the book's page by page or whole spread.
    public static func text(_ task: ScanTask, options: TaskOptions = TaskOptions()) -> CameraStepText {
        switch task {
        case .document:
            return CameraStepText(prompt: L10n.t("Hold the phone over each page."),
                                  help: L10n.t("Take each page in turn, then save."))
        case .feeder:
            return CameraStepText(prompt: L10n.t("Take the pages one by one."),
                                  help: L10n.t("The phone has no feeder: hold it over each page in turn, then save."))
        case .photos:
            return CameraStepText(prompt: L10n.t("Lay the photos apart on a dark table."),
                                  help: L10n.t("Each photo is found, cut out and straightened. Check them before saving."))
        case .photoRestore:
            return CameraStepText(prompt: L10n.t("Lay the old photos apart on a dark table."),
                                  help: L10n.t("Faded colors are restored. Check each photo before saving."))
        case .quickScan:
            return CameraStepText(prompt: L10n.t("Hold the phone over the page and take it."),
                                  help: L10n.t("Then save it as a picture or copy its text. Press on the text to select part of it."))
        case .email:
            return CameraStepText(prompt: L10n.t("Hold the phone over each page."),
                                  help: L10n.t("Saving makes a small PDF and opens Mail, or the share sheet. Nothing is sent until you send it."))
        case .twoSided:
            if options.cameraFrontsFirst {
                return CameraStepText(prompt: L10n.t("Take the front of every sheet."),
                                      help: L10n.t("Then tap Now the backs and take each back, first sheet first."))
            }
            return CameraStepText(prompt: L10n.t("Take the front of the first sheet."),
                                  help: L10n.t("After each front, turn the sheet over and take its back."))
        case .idCard:
            return CameraStepText(prompt: L10n.t("Fit the card in the frame."),
                                  help: L10n.t("Front, then back. Nothing is kept once you save or discard it."))
        case .copy:
            return CameraStepText(prompt: L10n.t("Hold the phone over the original."),
                                  help: L10n.t("Real size only when the page matches a paper size."))
        case .word:
            return CameraStepText(prompt: L10n.t("Hold the phone over each page."),
                                  help: L10n.t("The text is read into a Word document you can edit."))
        case .receipt:
            return CameraStepText(prompt: L10n.t("Lay up to six receipts apart on a dark table."),
                                  help: L10n.t("Each one is found, straightened and made easy to read. Check them before saving."))
        case .batch:
            return CameraStepText(prompt: L10n.t("Take a document's pages, then tap Split here."),
                                  help: L10n.t("Separator sheets work too, once a page matches a paper size. Check the splits in the pages, then save."))
        case .book:
            if options.cameraSpreads {
                return CameraStepText(prompt: L10n.t("Take the open book, both pages at once."),
                                      help: L10n.t("Each spread is cut at the spine into two pages. Curved pages are not flattened."))
            }
            return CameraStepText(prompt: L10n.t("Take one page at a time, in order."),
                                  help: L10n.t("Hold the book open and flat. Curved pages are not flattened."))
        case .archive:
            return CameraStepText(prompt: L10n.t("Hold the phone over each page."),
                                  help: L10n.t("Saved as a PDF/A, made to be kept for years."))
        }
    }

    /// What the camera says now for `task`: the two-sided camera's turn line while a back is due
    /// (`sides`) and flip & capture's next front after the first sheet, the batch's line while the next
    /// page starts a new document (`newDocument`), else the task's own words; nil without a task.
    public static func current(_ task: ScanTask?, options: TaskOptions, sides: CameraSides?,
                               newDocument: Bool) -> CameraStepText? {
        guard let task else { return nil }
        if task == .twoSided, let sides {
            if sides.next == .back {
                if sides.mode == .flip {
                    return CameraStepText(prompt: turnOverPrompt, help: turnOverHelp)
                }
                return CameraStepText(prompt: backsPrompt, help: backsHelp)
            }
            if sides.mode == .flip && sides.sheet > 0 {
                return CameraStepText(prompt: nextFrontPrompt, help: text(task, options: options).help)
            }
        }
        if task == .batch && newDocument {
            return CameraStepText(prompt: newDocumentPrompt, help: text(task, options: options).help)
        }
        return text(task, options: options)
    }
}
