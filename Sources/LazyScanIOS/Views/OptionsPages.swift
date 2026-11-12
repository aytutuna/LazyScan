#if os(iOS)
import LazyScanKit
import SwiftUI

/// A page of the Options sheet. While an import runs the settings cannot be changed: its pages belong to the
/// task and format it started with. The same holds while a scan or a save runs, which also keeps a preset from
/// being applied; a line says so at the top. `locks` is false for the pages whose rows keep their own rules.
struct OptionsForm<Content: View>: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var importer: IOSImportSession
    let title: String
    let locks: Bool
    private let content: Content

    init(title: String, locks: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.locks = locks
        self.content = content()
    }

    var body: some View {
        let working: Bool = locks && (importer.isImporting || state.isBusy)
        Form {
            if working {
                Section {
                    ReasonLine(text: importer.isImporting ? IOSSettingsText.importingReason : IOSSettingsText.busyReason)
                }
            }
            content
                .disabled(working)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Save as: the format, One PDF per page, and the PDF's choices while a save writes one. The format is any for
/// Photos and Receipts, an image format for the Text kind's held page, a PDF or an image for the ID card.
struct SaveAsPage: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(IOSShell.scanModeKey) private var mode: IOSScanMode = .camera

    var body: some View {
        let s: ScanSettings = state.settings
        OptionsForm(title: IOSSettingsText.saveAsLabel) {
            if offersName {
                Section {
                    TextField("Name", text: name, prompt: Text("Scan name"))
                        .submitLabel(.done)
                        .autocorrectionDisabled()
                        .accessibilityHint(Text("The file name for this save. The File name setting is unchanged."))
                        .accessibilityIdentifier("options.saveName")
                } header: {
                    Text("Name")
                } footer: {
                    Text("Used for this save only.")
                }
            }
            Section {
                Picker("Format", selection: format) {
                    ForEach(formats) { (choice: OutputFormat) in
                        Text(choice.label).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("options.format")
                if IOSShell.offersSave(s, pageCount: state.scannedPages.count) && !IOSShell.separatesDocuments(s)
                    && IOSShell.exportFormat(s) == OutputFormat.pdf {
                    Toggle(IOSShell.eachPageTitle(s, camera: mode == IOSScanMode.camera), isOn: eachPage)
                        .accessibilityIdentifier("options.eachPage")
                }
                PDFOptionsSection()
            }
        }
    }

    /// A name can be typed when Save writes one new file from the queue: not into a PDF picked, as pictures, or
    /// as several documents.
    private var offersName: Bool {
        let s: ScanSettings = state.settings
        return IOSShell.offersSave(s, pageCount: state.scannedPages.count) && !state.scannedPages.isEmpty
            && state.appendTarget == nil && !IOSShell.savesImages(s) && !state.queueSavePlan.isSplit
    }

    /// The suggested name until something else is typed; the template is not written.
    private var name: Binding<String> {
        let appState: AppState = state
        return Binding<String>(
            get: { appState.pendingName ?? appState.suggestedName },
            set: { (text: String) in
                appState.pendingName = text == appState.suggestedName ? nil : text
            })
    }

    /// Every format for documents, Photos and Receipts (the format Options saves them in), the image formats
    /// for the Text kind's held page (saved as a picture); the ID card is saved as a PDF or an image.
    private var formats: [OutputFormat] {
        if IOSSettingsSections.offersEveryFormat(state.settings) {
            return OutputFormat.offered(for: ScanIntent.document)
        }
        if state.activeTask == ScanTask.quickScan && !state.settings.documentMultiPage {
            return OutputFormat.offered(for: ScanIntent.photo)
        }
        let offered: [OutputFormat] = OutputFormat.offered(for: state.settings.intent)
        guard InspectorSections.savesPageFormat(state.settings) else { return offered }
        var list: [OutputFormat] = []
        for choice in offered where choice.pageFormat == choice {
            list.append(choice)
        }
        return list
    }

    private var format: Binding<OutputFormat> {
        let appState: AppState = state
        return Binding<OutputFormat>(
            get: { IOSSettingsSections.shownFormat(appState.settings) },
            set: { (choice: OutputFormat) in
                var s: ScanSettings = appState.settings
                s.format = choice
                appState.settings = IOSShell.keepingKind(s)
            })
    }

    private var eachPage: Binding<Bool> {
        let appState: AppState = state
        return Binding<Bool>(
            get: { IOSShell.savesEachPage(appState.settings) },
            set: { (on: Bool) in
                appState.settings = IOSShell.settingEachPage(on, in: appState.settings)
            })
    }
}

/// Look: the filter new pages get on the camera tab, which is the drawer's Colour group too, then the
/// adjustments.
struct LookPage: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(IOSShell.scanModeKey) private var mode: IOSScanMode = .camera

    var body: some View {
        OptionsForm(title: IOSSettingsText.lookLabel) {
            if mode == IOSScanMode.camera && IOSShell.offersFilters(state.settings) {
                Section {
                    CaptureFilterPicker(identifier: "options.filter")
                }
            }
            Section {
                AdjustmentSettingsRows()
            }
        }
    }
}

/// Pages: how a book is taken, whether the pages are collected before saving, and what is done to them, which
/// needs them collected.
struct PagesPage: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(IOSShell.scanModeKey) private var mode: IOSScanMode = .camera

    var body: some View {
        let camera: Bool = mode == IOSScanMode.camera
        OptionsForm(title: IOSSettingsText.pagesLabel) {
            if state.activeTask == ScanTask.book {
                Section {
                    TaskWayPicker(includesRightToLeft: false)
                } header: {
                    Text("Book")
                }
            }
            Section {
                CollectPagesRow(camera: camera)
                PageSettingsRows(camera: camera)
            }
        }
    }
}

/// Separate documents: the switch for the Document kind, and Split into documents, the way the queue is cut.
struct SeparatePage: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let s: ScanSettings = state.settings
        OptionsForm(title: IOSSettingsText.separateLabel) {
            if IOSShell.shownKind(s) == IOSScanKind.document {
                Section {
                    SeparateToggle()
                }
            }
            if InspectorSections.shown(s).contains(InspectorSections.split) {
                Section {
                    SplitSettingsRows()
                } header: {
                    Text(InspectorSections.title(InspectorSections.split))
                }
            }
        }
    }
}

/// The Scanner's Source, Sides, Resolution and Color (`ScannerSettingsRows`).
struct ScannerPage: View {
    var body: some View {
        OptionsForm(title: IOSOptionsPage.scanner.title) {
            Section {
                ScannerSettingsRows()
            }
        }
    }
}

/// Camera: the size photos are taken at, on this device only (`CameraSettingsRows`).
struct CameraPage: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        OptionsForm(title: IOSSettingsText.cameraTitle, locks: false) {
            Section {
                CameraSettingsRows(offered: IOSCameraLens.offered)
            }
            .disabled(state.isBusy)
        }
    }
}

/// After saving: what runs each time Save writes a document (`AfterSaveSection`).
struct AfterSavingPage: View {
    var body: some View {
        OptionsForm(title: IOSAfterSave.title, locks: false) {
            AfterSaveSection()
        }
    }
}

/// Share now: the actions on the pages queued now. Adding them to a PDF picked in Files (or going back to
/// saving new files), Share, Email, Print, with a computer paired sending them to it, and last sharing them
/// as a Lazy Scan file. Each action closes the sheet first (`onAction`), since what it opens cannot show over it; they
/// are dimmed while nothing is queued or a share or a send reads the queue (`blocked`). What runs on every
/// save is After saving's.
struct ShareNowPage: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var importer: IOSImportSession
    let blocked: Bool
    let onAction: (OptionsAction) -> Void

    var body: some View {
        OptionsForm(title: IOSSettingsText.shareNowLabel, locks: false) {
            Section {
                if state.scannedPages.isEmpty {
                    ReasonLine(text: String(localized: "No pages yet"))
                }
                actions
            } footer: {
                Text("Uses the pages in the stack now. After saving is for the saves to come.")
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        let canSave: Bool = SavePlan.make(state.scannedPages, options: state.settings.document).pageCount > 0
        let idle: Bool = !blocked && !importer.isImporting
        if IOSShell.offersPDFOptions(state.settings) || state.appendTarget != nil {
            appendRows(canSave: canSave && idle)
        }
        Button {
            onAction(.share)
        } label: {
            Label("Share\u{2026}", systemImage: "square.and.arrow.up")
        }
        .disabled(!canSave || !idle)
        .accessibilityIdentifier("save.share")
        Button {
            onAction(.email)
        } label: {
            Label("Email\u{2026}", systemImage: "envelope")
        }
        .disabled(!canSave || !idle)
        .accessibilityIdentifier("save.email")
        let printName: LocalizedStringKey = state.lazyPrintInstalled ? "Lazy Print" : "Print\u{2026}"
        Button {
            onAction(.print)
        } label: {
            Label(printName, systemImage: "printer")
        }
        .disabled(!canSave || !idle)
        .accessibilityIdentifier("save.print")
        if IOSShell.offersSendToComputer(state.settings, status: state.companionStatus) {
            Button {
                onAction(.send)
            } label: {
                Label(IOSCompanionText.sendButton, systemImage: "laptopcomputer")
            }
            .disabled(state.scannedPages.isEmpty || !idle)
            .accessibilityIdentifier("send.computer")
            if state.companionOutboxCount > 0 {
                Button(IOSCompanionText.waiting(state.companionOutboxCount)) {}
                    .disabled(true)
                    .accessibilityIdentifier("send.waiting")
            }
        }
        Button {
            onAction(.sharePackage)
        } label: {
            Label(IOSShell.sharePackageLabel, systemImage: "shippingbox")
        }
        .disabled(state.scannedPages.isEmpty || !idle)
        .accessibilityIdentifier("share.package")
    }

    /// Add to an existing PDF, as a new PDF again while one is picked (After saving's steps included, as Save
    /// runs them), and going back to saving new files. Word and text queues save their own format once the
    /// target is cleared.
    @ViewBuilder
    private func appendRows(canSave: Bool) -> some View {
        if state.settings.format.queueFormat == .pdf, state.appendTarget != nil {
            Button {
                onAction(.saveAsNew)
            } label: {
                Label(PDFAppender.saveAsNewLabel, systemImage: "doc.badge.arrow.up")
            }
            .disabled(!canSave)
            .accessibilityIdentifier("save.new")
        }
        Button {
            onAction(.addToPDF)
        } label: {
            Label(PDFAppender.buttonLabel, systemImage: "doc.badge.plus")
        }
        .disabled(!canSave)
        .accessibilityHint(Text(PDFAppender.buttonHint))
        .accessibilityIdentifier("append.button")
        if let target = state.appendTarget {
            Button {
                state.clearAppendTarget()
            } label: {
                Label(ScanScreen.clearTargetLabel(target), systemImage: "xmark.circle")
            }
            .accessibilityIdentifier("append.target.clear")
        }
    }
}

/// Help and about: Troubleshoot (over the sheet, `onTroubleshoot`), the ruler test page where a printer is
/// installed, About and Licences.
struct HelpPage: View {
    @EnvironmentObject private var state: AppState
    let onTroubleshoot: () -> Void

    var body: some View {
        OptionsForm(title: IOSSettingsText.helpLabel, locks: false) {
            Section {
                if state.hasPrinter {
                    Button {
                        state.printRulerPage()
                    } label: {
                        Label(IOSSettingsText.rulerLabel, systemImage: "ruler")
                    }
                    .disabled(state.isBusy)
                    .accessibilityHint(Text(IOSSettingsText.rulerHint))
                    .accessibilityIdentifier("settings.ruler")
                }
                Button {
                    onTroubleshoot()
                } label: {
                    Label(IOSSettingsText.troubleshootLabel, systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("settings.troubleshoot")
                NavigationLink(value: IOSOptionsPage.about) {
                    Label(IOSSettingsText.aboutLabel, systemImage: "info.circle")
                }
                .accessibilityIdentifier("settings.about")
                NavigationLink(value: IOSOptionsPage.licences) {
                    Label(IOSSettingsText.licencesLabel, systemImage: "doc.text")
                }
                .accessibilityIdentifier("about.licences")
            }
        }
    }
}
#endif
