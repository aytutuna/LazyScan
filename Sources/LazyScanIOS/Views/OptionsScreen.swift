#if os(iOS)
import LazyScanKit
import SwiftUI

/// The Options sheet, the same on both tabs: a short list like the system Settings app, in a navigation stack
/// of its own with Done always at the top. The Type (a menu of the kinds the tab offers, `IOSShell.cameraKinds`
/// on the camera; picking one goes to `onType`, which asks what a kind's pick does) comes first, then a row
/// for each page that applies to what is being scanned (`IOSOptionsPage.listed`: Save as, Look, Pages, Separate
/// documents, File name and folder, After saving, and the tab's own, Scanner or Camera), each with its current
/// value, and last Share now, Presets, My computer and Help and about. A page opens from its row, and the
/// value on the row follows the setting when the page is left. The sheet opens at half height, so the picture
/// stays in view while a setting is changed. While an import, a scan or a save runs the settings pages say so
/// and stay as they are.
struct OptionsScreen: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var importer: IOSImportSession
    @AppStorage(IOSShell.scanModeKey) private var mode: IOSScanMode = .camera
    @AppStorage(IOSAfterSave.email.key) private var emails: Bool = false
    @AppStorage(IOSAfterSave.print.key) private var prints: Bool = false
    @AppStorage(IOSAfterSave.send.key) private var sends: Bool = false
    @AppStorage(IOSCameraLens.megapixelsKey) private var chosenMegapixels: Int = 0
    @AppStorage(IOSShell.startModeKey) private var startMode: IOSScanMode = .camera
    let blocked: Bool
    /// Browses the computers on the network for My computer; nil when the app does not (`-demoScanner`).
    let companion: IOSCompanionBrowser?
    let onType: (IOSScanKind) -> Void
    let onAction: (OptionsAction) -> Void
    /// Runs once a preset's settings are in use: the sheet closes.
    let onPresetApplied: @MainActor () -> Void
    let onTroubleshoot: () -> Void
    let onDone: () -> Void
    /// Told when My computer is open: its pairing scanner needs the camera.
    let onPairing: (Bool) -> Void
    @State private var path: [IOSOptionsPage] = []

    var body: some View {
        NavigationStack(path: $path) {
            list
                .navigationTitle(ScanOptionGroup.options.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    doneItem
                }
                .navigationDestination(for: IOSOptionsPage.self) { (page: IOSOptionsPage) in
                    pageView(page)
                        .toolbar {
                            doneItem
                        }
                }
        }
        .onAppear {
            showPendingPairing()
        }
        .onChange(of: state.pendingPairingCode) { (_: String?, _: String?) in
            showPendingPairing()
        }
        .onChange(of: path) { (_: [IOSOptionsPage], pages: [IOSOptionsPage]) in
            onPairing(pages.last == .computer)
        }
    }

    /// A pairing code is waiting: My computer opens to take it.
    private func showPendingPairing() {
        guard state.pendingPairingCode != nil, path != [.computer] else { return }
        path = [.computer]
    }

    private var camera: Bool {
        mode == .camera
    }

    private var list: some View {
        let current: IOSScanKind = IOSShell.shownKind(state.settings)
        let kinds: [IOSScanKind] = camera ? IOSShell.cameraKinds : IOSScanKind.allCases
        let tiles: [IOSKindTile] = IOSShell.kindTiles(state.taskCards, current: current, order: kinds)
        let pages: [IOSOptionsPage] = IOSOptionsPage.listed(state.settings, camera: camera,
                                                             pageCount: state.scannedPages.count,
                                                             photoSizes: IOSCameraLens.choices(IOSCameraLens.offered).count)
        return Form {
            Section {
                typeMenu(tiles, current: current)
            } footer: {
                if let line = IOSShell.unavailableKindsLine(tiles) {
                    Text(line)
                        .accessibilityIdentifier("kinds.unavailable")
                }
            }
            Section {
                ForEach(pages) { (page: IOSOptionsPage) in
                    row(page)
                }
            }
            Section {
                Picker(String(localized: "Start screen"), selection: $startMode) {
                    ForEach(IOSScanMode.allCases) { (option: IOSScanMode) in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("options.startScreen")
            } footer: {
                Text(String(localized: "The screen Lazy Scan opens on."))
            }
            Section {
                ForEach(IOSOptionsPage.more) { (page: IOSOptionsPage) in
                    row(page)
                }
            } footer: {
                if state.isBusy {
                    Text(IOSSettingsText.busyReason)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var doneItem: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button(IOSSettingsText.doneLabel) {
                onDone()
            }
            .accessibilityIdentifier("options.done")
        }
    }

    private func row(_ page: IOSOptionsPage) -> some View {
        NavigationLink(value: page) {
            LabeledContent(page.title) {
                Text(value(of: page))
                    .lineLimit(1)
            }
        }
        // Presets cannot be applied while a scan or a save runs.
        .disabled(page == .presets && state.isBusy)
        .accessibilityIdentifier(page.identifier)
    }

    /// What the row says about its page now.
    private func value(of page: IOSOptionsPage) -> String {
        let s: ScanSettings = state.settings
        switch page {
        case .saveAs:
            return IOSOptionsPage.saveAsValue(s)
        case .look:
            return IOSOptionsPage.lookValue(s, camera: camera)
        case .pages:
            return IOSOptionsPage.pagesValue(s, camera: camera)
        case .separate:
            return IOSOptionsPage.separateValue(s)
        case .afterSaving:
            var checked: Set<IOSAfterSave> = []
            for (action, on) in [(IOSAfterSave.email, emails), (IOSAfterSave.print, prints), (IOSAfterSave.send, sends)] where on {
                checked.insert(action)
            }
            return IOSAfterSave.summary(checked: checked, then: s.output.afterSave)
        case .scanner:
            return state.selectedDeviceID == nil ? IOSNetworkText.noScannerPicked : InspectorSections.scannerSummary(s)
        case .camera:
            let offered: [IOSPhotoSize] = IOSCameraLens.offered
            guard let size = IOSCameraLens.photoSize(offered, megapixels: chosenMegapixels) else { return "" }
            return IOSCameraText.sizeLabel(size)
        case .shareNow:
            return IOSCameraText.pageCount(state.scannedPages.count)
        case .computer:
            return state.companionDesktop?.name ?? IOSCompanionText.notPaired
        case .fileName:
            return s.namingTemplate
        case .presets, .help, .about, .licences:
            return ""
        }
    }

    @ViewBuilder
    private func pageView(_ page: IOSOptionsPage) -> some View {
        switch page {
        case .saveAs:
            SaveAsPage()
        case .look:
            LookPage()
        case .pages:
            PagesPage()
        case .separate:
            SeparatePage()
        case .fileName:
            NamingEditorScreen(model: IOSNamingModel(state: state))
        case .afterSaving:
            AfterSavingPage()
        case .scanner:
            ScannerPage()
        case .camera:
            CameraPage()
        case .shareNow:
            ShareNowPage(blocked: blocked, onAction: onAction)
        case .presets:
            PresetsScreen(onApplied: onPresetApplied)
        case .computer:
            CompanionScreen(state: state, browser: companion)
        case .help:
            HelpPage(onTroubleshoot: onTroubleshoot)
        case .about:
            AboutScreen()
        case .licences:
            LicencesScreen()
        }
    }

    private func title(_ kind: IOSScanKind) -> String {
        camera ? kind.cameraTitle : kind.title
    }

    private func typeMenu(_ tiles: [IOSKindTile], current: IOSScanKind) -> some View {
        Menu {
            ForEach(tiles) { (tile: IOSKindTile) in
                let kind: IOSScanKind = tile.kind
                let available: Bool = tile.availability.isAvailable
                Button {
                    onType(kind)
                } label: {
                    if tile.isCurrent {
                        Label(title(kind), systemImage: "checkmark")
                    } else {
                        Text(title(kind))
                    }
                }
                .disabled(!available)
                .accessibilityHint(Text(available ? kind.subtitle : String(localized: "\(kind.subtitle). Not available: \(tile.availability.reason ?? "")")))
                .accessibilityIdentifier("type.\(kind.rawValue)")
            }
        } label: {
            HStack(spacing: 8) {
                Text("Type")
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 8)
                Text(title(current))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .disabled(blocked || importer.isImporting)
        .accessibilityLabel(Text("Type"))
        .accessibilityValue(Text(title(current)))
        .accessibilityIdentifier("options.type")
    }
}

/// What the Share now rows ask the scan screen to do once the sheet has closed.
enum OptionsAction {
    case saveAsNew
    case addToPDF
    case email
    case print
    case share
    case send
}
#endif
