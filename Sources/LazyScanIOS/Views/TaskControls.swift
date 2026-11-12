#if os(iOS)
import LazyScanKit
import SwiftUI

/// The PDF's Archive and Password choices as the scan screen shows them: the two exclude each other (a
/// PDF/A file can't have a password), so while one is on the other is off, dimmed, with its short reason;
/// a settings file with both on shows the password (`PDFWriteOptions.forOutput` writes it). The same rule
/// as the Mac's inspector and the Windows window.
enum IOSPDFOptions {
    /// The Archive switch is on: archival, and no password.
    static func archivalShown(_ output: OutputOptions) -> Bool {
        output.archival && !output.protect
    }

    /// The Archive switch turned on or off; it can't be turned on while the password is.
    static func settingArchival(_ on: Bool, in output: OutputOptions) -> OutputOptions {
        var changed: OutputOptions = output
        changed.archival = on && !output.protect
        return changed
    }

    /// The Password switch turned on or off: on turns archival PDF off; archival keeps only what its switch
    /// showed, so turning the password off later leaves it off.
    static func settingProtect(_ on: Bool, in output: OutputOptions) -> OutputOptions {
        var changed: OutputOptions = output
        let shown: Bool = archivalShown(output)
        changed.archival = shown && !on
        changed.protect = on
        return changed
    }

    /// The short reason beside a dimmed switch: the Archive switch's while the password is on, the
    /// Password switch's while archival is; nil when neither is dimmed.
    static func archivalReason(_ output: OutputOptions) -> String? {
        output.protect ? PDFA.notWithPasswordReason : nil
    }

    static func protectReason(_ output: OutputOptions) -> String? {
        archivalShown(output) ? PDFProtection.notWithArchivalReason : nil
    }

    /// The pages' text in a .txt file beside the PDF, as the Mac's "Also save text".
    static var alsoSaveTextLabel: String { String(localized: "Also save text (.txt)") }
    static var alsoSaveTextHint: String { String(localized: "Saves the text in a .txt file next to the PDF") }
}

/// The camera's buttons between shots for the task set up: No back side (flip & capture, while a back is
/// due), Now the backs and Put in order or Combine anyway (fronts first). Nothing for the other tasks, nor on
/// the printer screen (`printer`): a scanned page never takes the camera's sides. Split here sits between
/// Options and Save instead (`SplitHereButton`). `onDark` draws them over the camera's live preview, which is
/// mostly the white page or a dark desk: the secondary ones white on a dark capsule, as the status line is,
/// the prominent ones in the accent color.
struct CameraTaskButtons: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var importer: IOSImportSession
    var onDark: Bool = false
    var printer: Bool = false

    var body: some View {
        let busy: Bool = state.isBusy || importer.isImporting
        HStack(spacing: 10) {
            if !printer, let sides = state.cameraSides {
                if sides.canSkipBack {
                    Button(CameraTaskCatalog.noBackLabel) {
                        state.skipCameraBack()
                    }
                    .modifier(SecondaryTaskButton(onDark: onDark))
                    .disabled(busy)
                    .accessibilityIdentifier("task.noBack")
                }
                if sides.canStartBacks {
                    Button(CameraTaskCatalog.startBacksLabel) {
                        state.startCameraBacks()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy)
                    .accessibilityIdentifier("task.startBacks")
                }
                if sides.canPutInOrder {
                    Button(state.sidesMismatch == nil ? CameraTaskCatalog.putInOrderLabel : CameraTaskCatalog.combineLabel) {
                        state.putCameraSidesInOrder()
                    }
                    .modifier(SecondaryTaskButton(onDark: onDark))
                    .disabled(busy)
                    .accessibilityIdentifier("task.putInOrder")
                }
            }
        }
    }

    /// Whether any button shows, so the scan screen leaves out an empty row.
    static func showsAny(_ state: AppState, printer: Bool = false) -> Bool {
        guard !printer, let sides = state.cameraSides else { return false }
        return sides.canSkipBack || sides.canStartBacks || sides.canPutInOrder
    }
}

/// Separate documents' page break: the next page starts a new document (Command-N). It sits between Options
/// and Save on the picture, dark like Options, so it does not read as a second Save.
struct SplitHereButton: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var importer: IOSImportSession

    static var label: String { String(localized: "Split here") }

    var body: some View {
        Button {
            state.startNewDocument()
        } label: {
            Label(Self.label, systemImage: "scissors")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(Capsule().fill(Color(white: 0.15)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(state.isBusy || importer.isImporting || !state.canStartNewDocument)
        .opacity(state.canStartNewDocument && !importer.isImporting ? 1 : 0.4)
        .keyboardShortcut(IOSShortcuts.newDocument.keyboardShortcut)
        .accessibilityHint(Text(CameraTaskCatalog.newDocumentPrompt))
        .accessibilityIdentifier("task.newDocument")
    }
}

/// A secondary task button: bordered in the accent color on the list, white on a dark capsule over the
/// camera's preview.
private struct SecondaryTaskButton: ViewModifier {
    let onDark: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if onDark {
            content
                .buttonStyle(.borderedProminent)
                .tint(Color.black.opacity(0.55))
        } else {
            content
                .buttonStyle(.bordered)
                .tint(Color.accentColor)
        }
    }
}

/// How the camera takes the task set up: Flip & capture or Fronts, then backs for the two-sided task;
/// Page by page or Whole spread for a book (`TaskOptions.cameraFrontsFirst`, `cameraSpreads`), and while
/// spreads are cut (whole spreads, or a network scanner's scans) whether the book reads right to left
/// (`bookRightToLeft`, as the Mac's inspector has it; `IOSShell.showsRightToLeft`). With a scanner in use
/// the book's picker only governs the photos brought in from Photos and Files, since a scanner's spreads are
/// always cut, and a note under it says so.
/// Nothing for the other tasks. Kept in the settings, as the task's other choices are.
struct TaskWayPicker: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var importer: IOSImportSession
    /// The book's Reads right to left is left out where the Pages page has it among the book's choices.
    var includesRightToLeft: Bool = true

    var body: some View {
        if state.activeTask == .twoSided {
            Picker("Sides", selection: frontsFirst) {
                Text(CameraTaskCatalog.flipLabel).tag(false)
                Text(CameraTaskCatalog.frontsFirstLabel).tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(state.isBusy || importer.isImporting)
            .accessibilityIdentifier("task.sidesWay")
        } else if state.activeTask == .book {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Book", selection: spreads) {
                    Text(CameraTaskCatalog.pageByPageLabel).tag(false)
                    Text(CameraTaskCatalog.wholeSpreadLabel).tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("task.bookWay")
                if selectedDevice != nil {
                    Text(CameraTaskCatalog.spreadsWithScannerNote)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
                if includesRightToLeft && IOSShell.showsRightToLeft(state.settings, device: selectedDevice) {
                    Toggle(CameraTaskCatalog.rightToLeftLabel, isOn: rightToLeft)
                        .accessibilityHint(Text(CameraTaskCatalog.rightToLeftHint))
                        .accessibilityIdentifier("task.rightToLeft")
                }
            }
            .disabled(state.isBusy || importer.isImporting)
        }
    }

    private var selectedDevice: ScannerInfo? {
        let selected: String? = state.selectedDeviceID
        return state.devices.first(where: { (info: ScannerInfo) -> Bool in info.id == selected })
    }

    private var frontsFirst: Binding<Bool> {
        let appState: AppState = state
        return Binding<Bool>(
            get: { appState.settings.taskOptions.cameraFrontsFirst },
            set: { (on: Bool) in
                appState.settings.taskOptions.cameraFrontsFirst = on
            })
    }

    private var spreads: Binding<Bool> {
        let appState: AppState = state
        return Binding<Bool>(
            get: { appState.settings.taskOptions.cameraSpreads },
            set: { (on: Bool) in
                appState.settings.taskOptions.cameraSpreads = on
            })
    }

    private var rightToLeft: Binding<Bool> {
        let appState: AppState = state
        return Binding<Bool>(
            get: { appState.settings.taskOptions.bookRightToLeft },
            set: { (on: Bool) in
                appState.settings.taskOptions.bookRightToLeft = on
            })
    }
}

/// Options' Both sides for the camera: the two-sided task under the hood (`IOSShell.settingBothSides`), so
/// the camera takes each sheet's front and back; how it does is `TaskWayPicker`'s. Dimmed with its reason
/// while the scanner set up has no feeder, as the two-sided task's tile was, and while Separate documents is
/// on, since one task holds either.
struct BothSidesToggle: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var importer: IOSImportSession

    var body: some View {
        let on: Bool = state.activeTask == .twoSided
        let availability: TaskAvailability = TaskCatalog.availability(of: .twoSided, capabilities: state.capabilities)
        let separates: Bool = !on && IOSShell.separatesDocuments(state.settings)
        Toggle("Both sides", isOn: bothSides)
            .disabled(state.isBusy || importer.isImporting || (!on && (!availability.isAvailable || separates)))
            .accessibilityHint(Text("Takes the front and back of each sheet"))
            .accessibilityIdentifier("options.bothSides")
        if separates {
            OptionReason(text: IOSCameraText.notWithSeparate)
        } else if !on, let reason = availability.reason {
            OptionReason(text: reason)
        }
    }

    private var bothSides: Binding<Bool> {
        let appState: AppState = state
        return Binding<Bool>(
            get: { appState.activeTask == .twoSided },
            set: { (on: Bool) in
                // Off goes back to the flatbed, unless the scanner has none.
                let s: ScanSettings = IOSShell.settingBothSides(on, in: appState.settings)
                appState.settings = SettingsAdapter.adapt(s, to: appState.capabilities).settings
            })
    }
}

/// Options' Restore faded colours for Photos: Restore old photos under the hood (`IOSShell.settingRestore`).
struct RestoreToggle: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var importer: IOSImportSession

    var body: some View {
        Toggle("Restore faded colors", isOn: restore)
            .disabled(state.isBusy || importer.isImporting)
            .accessibilityHint(Text("Brings back the colors of old prints"))
            .accessibilityIdentifier("options.restore")
    }

    private var restore: Binding<Bool> {
        let appState: AppState = state
        return Binding<Bool>(
            get: { appState.settings.adjustments.restoreFadedColors },
            set: { (on: Bool) in
                appState.settings = IOSShell.settingRestore(on, in: appState.settings)
            })
    }
}

/// Options' Separate documents: the Separate documents task under the hood (`IOSShell.setSeparate`), with its
/// New document button and separator sheets; dimmed without a feeder as its tile was, and while Both sides is
/// on, since one task holds either. Split into documents (`SplitSettingsRows`) is the same setting seen as the
/// queue's split, and turns this on and off from its choices.
struct SeparateToggle: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var importer: IOSImportSession

    var body: some View {
        let s: ScanSettings = state.settings
        let busy: Bool = state.isBusy || importer.isImporting
        let separates: Bool = IOSShell.separatesDocuments(s)
        let bothSides: Bool = !separates && state.activeTask == .twoSided
        let availability: TaskAvailability = TaskCatalog.availability(of: .batch, capabilities: state.capabilities)
        Toggle("Separate documents", isOn: separate)
            .disabled(busy || (!separates && (!availability.isAvailable || bothSides)))
            .accessibilityHint(Text("Splits the pages into documents at separator sheets"))
            .accessibilityIdentifier("options.separate")
        if bothSides {
            OptionReason(text: IOSCameraText.notWithBothSides)
        } else if !separates, let reason = availability.reason {
            OptionReason(text: reason)
        }
    }

    private var separate: Binding<Bool> {
        let appState: AppState = state
        return Binding<Bool>(
            get: { IOSShell.separatesDocuments(appState.settings) },
            set: { (on: Bool) in
                IOSShell.setSeparate(on, in: appState)
            })
    }
}

/// After saving (`IOSAfterSave`): what Save also does, each a check, and under them Then, the settings' own
/// action after a save (`OutputOptions.afterSave`) in the phone's words. The After saving page's content. Send
/// to computer is dimmed, with its reason under it, while nothing can send; its
/// check stays as it was. Then is dimmed while Email is checked: the email goes in its place.
struct AfterSaveSection: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(IOSAfterSave.email.key) private var emails: Bool = false

    var body: some View {
        Section {
            ForEach(IOSAfterSave.rows) { (action: IOSAfterSave) in
                let reason: String? = unavailableReason(of: action)
                AfterSaveRow(action: action)
                    .disabled(reason != nil)
                if let reason = reason {
                    OptionReason(text: reason)
                }
            }
            thenRow
        } footer: {
            Text(IOSAfterSave.footer)
        }
    }

    @ViewBuilder
    private var thenRow: some View {
        Picker(IOSAfterSave.thenTitle, selection: $state.settings.output.afterSave) {
            ForEach(AfterSaveAction.allCases) { (action: AfterSaveAction) in
                Text(IOSAfterSave.thenLabel(action)).tag(action)
            }
        }
        .disabled(emails)
        .accessibilityHint(Text(IOSAfterSave.thenHint(state.settings.output.afterSave)))
        .accessibilityIdentifier("options.afterSave.then")
        if emails {
            OptionReason(text: IOSAfterSave.emailInsteadReason)
        }
    }

    /// Why `action` cannot run now, nil while it can. Only Send to computer can be out of reach: Options
    /// shows it under the same test (`IOSShell.offersSendToComputer`).
    private func unavailableReason(of action: IOSAfterSave) -> String? {
        let s: ScanSettings = state.settings
        guard action == .send, !IOSShell.offersSendToComputer(s, status: state.companionStatus) else { return nil }
        return IOSShell.collectsPages(s) ? IOSCompanionText.sendNeedsPairingReason : IOSCompanionText.sendNeedsPagesReason
    }
}

/// A row of After saving: a check kept in the user's defaults under the action's key.
private struct AfterSaveRow: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.isEnabled) private var isEnabled: Bool
    let action: IOSAfterSave
    @AppStorage private var checked: Bool

    init(action: IOSAfterSave) {
        self.action = action
        _checked = AppStorage(wrappedValue: false, action.key)
    }

    var body: some View {
        Button {
            checked.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(action.label(lazyPrintInstalled: state.lazyPrintInstalled))
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 8)
                if checked {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        // The label sets its own colours, so a disabled button does not dim it.
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityAddTraits(checked ? AccessibilityTraits.isSelected : [])
        .accessibilityIdentifier("options.afterSave.\(action.rawValue)")
    }
}

/// Why an option is dimmed, in one short line under it.
private struct OptionReason: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(Color.secondary)
    }
}

/// The PDF's choices while a save writes one (`IOSSettingsSections.writesPDF`): its size (Best, Standard,
/// Compact, Smallest), Searchable PDF (not for the ID card), Archive (PDF/A) and Password, which exclude each
/// other (`IOSPDFOptions`), and the pages' text in a .txt file beside the PDF (`OutputOptions.alsoSaveText`, as
/// on the Mac). The password itself is asked for when saving (`IOSPasswordPrompt`) and never kept.
struct PDFOptionsSection: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let s: ScanSettings = state.settings
        let output: OutputOptions = s.output
        let flow: TaskFlowKind = TaskCatalog.flow(of: s)
        if IOSSettingsSections.shownFormat(s) == OutputFormat.pdf
            && (s.intent == ScanIntent.document || IOSSettingsSections.offersEveryFormat(s)) {
            Picker("PDF size", selection: pdfSize) {
                ForEach(PDFSizePreset.displayOrder, id: \.self) { (size: PDFSizePreset) in
                    Text(size.label).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityHint(Text("\(output.pdfSize.hint). \(output.pdfSize.detail)"))
            .accessibilityIdentifier("pdf.size")
        }
        if IOSSettingsSections.writesPDF(s) {
            if flow != TaskFlowKind.copy && flow != TaskFlowKind.idCard {
                Toggle("Searchable PDF", isOn: $state.settings.pdfSearchable)
                    .accessibilityHint(Text("Lets you search and copy the text (OCR)"))
                    .accessibilityIdentifier("pdf.searchable")
            }
            Toggle(PDFA.optionLabel, isOn: archival)
                .disabled(output.protect)
                .accessibilityHint(Text(output.protect ? PDFA.cannotProtectNote : PDFA.optionHint))
                .accessibilityIdentifier("pdf.archival")
            if let reason = IOSPDFOptions.archivalReason(output) {
                reasonLine(reason)
            }
            Toggle(PDFProtection.optionLabel, isOn: protect)
                .disabled(IOSPDFOptions.archivalShown(output))
                .accessibilityHint(Text(IOSPDFOptions.archivalShown(output) ? PDFA.cannotProtectNote : PDFProtection.optionHint))
                .accessibilityIdentifier("pdf.protect")
            if let reason = IOSPDFOptions.protectReason(output) {
                reasonLine(reason)
            }
        }
        if IOSSettingsSections.textApplies(s) {
            Toggle(IOSPDFOptions.alsoSaveTextLabel, isOn: alsoSaveText)
                .disabled(output.protect)
                .accessibilityHint(Text(IOSPDFOptions.alsoSaveTextHint))
                .accessibilityIdentifier("pdf.alsoSaveText")
            if output.protect {
                reasonLine(PDFA.notWithPasswordReason)
            }
        }
    }

    private func reasonLine(_ reason: String) -> some View {
        Label(reason, systemImage: "lock")
            .font(.caption)
            .foregroundStyle(Color.secondary)
    }

    private var pdfSize: Binding<PDFSizePreset> {
        let appState: AppState = state
        return Binding<PDFSizePreset>(
            get: { appState.settings.output.pdfSize },
            set: { (size: PDFSizePreset) in
                appState.settings.output.pdfSize = size
            })
    }

    private var archival: Binding<Bool> {
        let appState: AppState = state
        return Binding<Bool>(
            get: { IOSPDFOptions.archivalShown(appState.settings.output) },
            set: { (on: Bool) in
                var s: ScanSettings = appState.settings
                s.output = IOSPDFOptions.settingArchival(on, in: s.output)
                appState.settings = IOSShell.keepingKind(s)
            })
    }

    private var alsoSaveText: Binding<Bool> {
        let appState: AppState = state
        return Binding<Bool>(
            get: { appState.settings.output.alsoSaveText },
            set: { (on: Bool) in
                appState.settings.output.alsoSaveText = on
            })
    }

    private var protect: Binding<Bool> {
        let appState: AppState = state
        return Binding<Bool>(
            get: { appState.settings.output.protect },
            set: { (on: Bool) in
                var s: ScanSettings = appState.settings
                s.output = IOSPDFOptions.settingProtect(on, in: s.output)
                appState.settings = IOSShell.keepingKind(s)
            })
    }
}
#endif
