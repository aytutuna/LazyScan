#if os(macOS)
import AppKit
import LazyScanKit
import SwiftUI

private struct ScanSettingsShownKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    /// Whether the scan settings column is shown; set while the Scanner tab is up, where the column lives.
    var scanSettingsShown: Binding<Bool>? {
        get { self[ScanSettingsShownKey.self] }
        set { self[ScanSettingsShownKey.self] = newValue }
    }
}

/// The Scan menu: the window's main actions with keys, on and off as their buttons are.
struct ScanCommands: Commands {
    @ObservedObject var state: AppState

    /// A sheet or alert is up, so a key must not start work under it.
    private var dialogOpen: Bool {
        state.cornerReview != nil || state.showPhotoReview || state.showIdCardReview
            || state.errorMessage != nil || state.pendingIdCardLeave != nil
            || state.asksSidesOrder || state.showTroubleshooter
    }

    /// The menu is not re-evaluated when a view's own sheet or alert opens, so each action checks the key window too.
    private func run(_ action: () -> Void) {
        guard NSApp.keyWindow?.sheetParent == nil else { return }
        action()
    }

    private var canScan: Bool { !dialogOpen && !state.isBusy && state.isConnected }
    private var canPreview: Bool { !dialogOpen && !state.isBusy && state.previewUnavailableReason == nil }
    private var canSave: Bool {
        guard !dialogOpen, !state.isBusy else { return false }
        return SavePlan.make(state.scannedPages, options: state.settings.document).pageCount > 0
    }
    private var canImport: Bool { !dialogOpen && state.canImportPhotos }

    /// The page shown large, which Delete Page removes.
    private var viewedPage: UUID? {
        guard state.viewsPage, let id = state.viewedPageID else { return nil }
        return state.scannedPages.contains(where: { $0.id == id }) ? id : nil
    }
    private var canDelete: Bool { !dialogOpen && !state.isBusy && viewedPage != nil }

    var body: some Commands {
        CommandMenu("Scan") {
            Button(state.primaryActionLabel) { run { state.performScan() } }
                .keyboardShortcut("r")
                .disabled(!canScan)
            Button("Preview") { run { state.performOverview() } }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!canPreview)
            Button("Cancel") { state.cancelScan() }
                .keyboardShortcut(".")
                .disabled(!state.isBusy)
            Divider()
            Button("Save") { run { state.savePDF() } }
                .keyboardShortcut("s")
                .disabled(!canSave)
            if PhotoImport.isOffered(state.settings) {
                Button("Import Photos\u{2026}") { run { state.chooseAndImportPhotos() } }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                    .disabled(!canImport)
            }
            Divider()
            Button("Delete Page") {
                run {
                    // Cmd-Delete is also delete-to-start-of-line, so a text field being edited gets it back.
                    if NSApp.keyWindow?.firstResponder is NSText {
                        NSApp.sendAction(#selector(NSResponder.deleteToBeginningOfLine(_:)), to: nil, from: nil)
                    } else if let id = viewedPage {
                        state.removePage(id: id)
                    }
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(!canDelete)
        }
        ScanSettingsCommands()
    }
}

/// View > Show Scan Settings or Hide Scan Settings.
struct ScanSettingsCommands: Commands {
    @FocusedValue(\.scanSettingsShown) private var shown

    private var isShown: Bool { shown?.wrappedValue ?? false }

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button {
                shown?.wrappedValue.toggle()
            } label: {
                if isShown {
                    Text("Hide Scan Settings")
                } else {
                    Text("Show Scan Settings")
                }
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(shown == nil)
        }
    }
}
#endif
