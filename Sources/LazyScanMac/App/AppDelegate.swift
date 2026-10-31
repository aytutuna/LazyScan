#if os(macOS)
import AppKit
import LazyScanKit

/// The app's delegate (`LazyScanApp`'s `@NSApplicationDelegateAdaptor`): Quit asks first while a scan or
/// save runs or work is unsaved, as closing the Windows window does (`MainWindow_Closing`), since the Mac
/// keeps neither the queue nor a review nor an ID card's sides once it has quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set when the window appears.
    weak var state: AppState?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state else { return .terminateNow }
        let unsaved = Self.unsavedWork(state)
        guard state.isBusy || unsaved != nil else { return .terminateNow }
        let alert = NSAlert()
        alert.alertStyle = .warning
        if state.isBusy {
            alert.messageText = "Stop it and quit?"
            alert.informativeText = "A scan or save is still running." + (unsaved.map { " " + $0 } ?? "")
        } else {
            alert.messageText = "Quit anyway?"
            alert.informativeText = unsaved ?? ""
        }
        let quit = alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        // Return does not quit, as No is the Windows question's default.
        quit.keyEquivalent = ""
        // Quit from the Dock or at logout can come while the app is in the background.
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        // TODO: let a running save finish its cleanup first (.terminateLater), as Windows does.
        if state.isBusy { state.cancelScan() }
        return .terminateNow
    }

    /// What quitting would lose, in the words of the Windows question (`UnsavedWorkDescription`): the
    /// queue, else an open review, else a held ID card side; nil when nothing is unsaved.
    static func unsavedWork(_ state: AppState) -> String? {
        let pages = state.scannedPages.count
        if pages > 0 {
            return "\(pages) scanned page\(pages == 1 ? " is" : "s are") still in the queue and not saved."
        }
        if state.showPhotoReview {
            return state.isReceiptReview
                ? "The receipts found have not been saved."
                : "The detected photos have not been saved."
        }
        if state.hasIdCardCaptures {
            return "The ID card has not been saved."
        }
        return nil
    }
}
#endif
