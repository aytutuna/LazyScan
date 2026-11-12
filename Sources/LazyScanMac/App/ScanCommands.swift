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
        return state.queuePlans.save.pageCount > 0
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

/// Edit > Undo and Redo. Undo puts back removed pages; a text field being edited keeps its own undo and redo.
struct UndoCommands: Commands {
    @ObservedObject var state: AppState

    private var title: String {
        if state.canUndoSave { return String(localized: "Undo Save") }
        if !state.canUndoRemove { return String(localized: "Undo") }
        if state.removedByReorder { return String(localized: "Undo Spread Update") }
        return state.removedByClear ? String(localized: "Undo Clear") : String(localized: "Undo Remove Page")
    }

    /// The menu is not re-evaluated when focus moves into a text field, so Undo and Redo stay on unless
    /// they could only do nothing: Undo while the pages cannot come back.
    private var canUndo: Bool { !(state.canUndoSave || state.canUndoRemove) || (!state.isBusy && !state.readsQueue) }

    private var editsText: Bool { NSApp.keyWindow?.firstResponder is NSText }

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(title) {
                if editsText {
                    NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
                } else if NSApp.keyWindow?.sheetParent == nil {
                    if state.canUndoSave {
                        state.undoSave()
                    } else {
                        state.undoRemove()
                    }
                }
            }
            .keyboardShortcut("z")
            .disabled(!canUndo)
            Button("Redo") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
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
