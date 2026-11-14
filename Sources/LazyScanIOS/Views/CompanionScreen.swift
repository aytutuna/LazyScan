#if os(iOS)
import LazyScanKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// My computer, a page of the Options sheet (`IOSCompanionModel`): with no computer paired, Pair with a computer
/// (the camera looking for its code, the computers nearby to pick and type the short code shown on one, the
/// code's text to paste instead, the check code to compare, the name the computer will list the phone
/// under, Pair); once paired, the computer's name and state
/// (checked when the screen opens, and on Refresh), Unpair (asked first), and the documents waiting to be
/// sent, each with its date and why it has not gone, removable by a swipe, with Send again and Remove all
/// (asked first), and those in the cloud folder the computer has not taken yet. For a computer that
/// handed out a sync key, the cloud folder (Choose…, Clear) documents go to when it cannot be reached. A
/// computer that no longer knows the phone is shown with pairing offered again. Local Network access that
/// is off is said with Open Settings. Documents left for a computer no longer paired have a line and a Remove
/// all of their own.
struct CompanionScreen: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var model: IOSCompanionModel
    @State private var choosingFolder: Bool = false
    @State private var confirmingUnpair: Bool = false
    @State private var confirmingRemoveAll: Bool = false
    @State private var confirmingRemoveOther: Bool = false
    @State private var scanning: Bool = false
    @State private var textExpanded: Bool = false
    @FocusState private var codeFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(state: AppState, browser: IOSCompanionBrowser?, network: IOSNetworkScanners?) {
        _model = StateObject(wrappedValue: IOSCompanionModel(state: state, browser: browser, network: network))
    }

    var body: some View {
        Form {
            if model.needsExplanation {
                Section {
                    ExplanationCard(title: IOSNetworkText.companionTitle, onContinue: model.continueAfterExplanation)
                }
            }
            if let desktop = state.companionDesktop {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(desktop.name)
                            .font(.headline)
                            .accessibilityIdentifier("companion.name")
                        Text(IOSCompanionText.status(state.companionStatus))
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                            .accessibilityIdentifier("companion.status")
                    }
                    .accessibilityElement(children: .combine)
                    if !model.needsPairing {
                        Button {
                            Task { await model.refresh() }
                        } label: {
                            Label(IOSCompanionText.refreshButton, systemImage: "arrow.clockwise")
                        }
                        .disabled(state.companionStatus == .checking || model.needsExplanation)
                        .accessibilityIdentifier("companion.refresh")
                    }
                    Button(role: .destructive) {
                        confirmingUnpair = true
                    } label: {
                        Label(IOSCompanionText.unpairButton, systemImage: "xmark.circle")
                    }
                    .disabled(model.isPairing)
                    .accessibilityIdentifier("companion.unpair")
                    .confirmationDialog(IOSCompanionText.unpairTitle(desktop.name), isPresented: $confirmingUnpair,
                                        titleVisibility: .visible) {
                        Button(IOSCompanionText.unpairButton, role: .destructive) {
                            Task { await model.unpair() }
                        }
                        .accessibilityIdentifier("companion.unpair.confirm")
                    } message: {
                        Text(IOSCompanionText.unpairMessage(waiting: state.companionOutboxCount))
                    }
                }
            }
            if model.needsPairing {
                pairSections
            }
            if state.companionDesktop != nil || state.companionOutboxCount > 0 {
                outboxSection
            }
            if state.companionOtherOutboxCount > 0 {
                otherOutboxSection
            }
            if model.offersCloudFolder && !model.needsPairing {
                cloudFolderSection
            }
            if let browser = model.browser {
                CompanionNetworkLine(browser: browser)
            }
        }
        .navigationTitle(IOSCompanionText.title)
        .onAppear {
            model.appear()
            takePairingCode()
        }
        .onChange(of: state.pendingPairingCode) { (_: String?, _: String?) in
            takePairingCode()
        }
        .onChange(of: state.companionOutboxCount) { (_: Int, _: Int) in
            model.lookAtCloudFolder()
        }
        .onChange(of: model.code == nil) { _, isEmpty in
            if isEmpty { textExpanded = false }
        }
        .onChange(of: model.nearbyCode) { _, _ in
            Task { await model.codeEdited() }
        }
        .onChange(of: model.isCheckingCode) { _, checking in
            if !checking && model.chosen != nil { codeFocused = true }
        }
        .onDisappear {
            model.disappear()
        }
    }

    private func takePairingCode() {
        guard let code = state.pendingPairingCode else { return }
        state.pendingPairingCode = nil
        if model.needsPairing {
            model.scanned(code)
        }
    }

    private var outboxSection: some View {
        Section {
            ForEach(model.waitingItems, id: \.id) { (item: PhoneOutboxItem) in
                waitingRow(item)
            }
            if model.sendableCount > 0 {
                Button(IOSCompanionText.sendAgainButton) {
                    Task { await model.sendAgain() }
                }
                .disabled(model.needsPairing)
                .accessibilityIdentifier("companion.sendAgain")
            }
            if state.companionOutboxCount > 0 {
                Button(IOSCompanionText.removeAllButton, role: .destructive) {
                    confirmingRemoveAll = true
                }
                .accessibilityIdentifier("companion.remove")
                .confirmationDialog(IOSCompanionText.removeAllTitle(state.companionOutboxCount),
                                    isPresented: $confirmingRemoveAll, titleVisibility: .visible) {
                    Button(IOSCompanionText.removeAllButton, role: .destructive) {
                        model.removeWaiting()
                    }
                    .accessibilityIdentifier("companion.remove.confirm")
                } message: {
                    Text(IOSCompanionText.removeAllMessage(state.companionOutboxCount, computer: state.companionDesktop?.name))
                }
            }
            if model.inCloudFolder > 0 {
                Text(IOSCompanionText.inCloudFolder(model.inCloudFolder))
                    .accessibilityIdentifier("companion.inCloudFolder")
            }
        } header: {
            Text(IOSCompanionText.waiting(model.sendableCount))
                .accessibilityIdentifier("companion.outbox")
        }
    }

    private func waitingRow(_ item: PhoneOutboxItem) -> some View {
        let name: String = URL(fileURLWithPath: item.fileName).deletingPathExtension().lastPathComponent
        let reason: String = waitingReason(item)
        let reasonColor: Color = item.refused ? Color.red : Color.secondary
        let reasonLines: Int? = dynamicTypeSize.isAccessibilitySize ? nil : 2
        let removeName: String = IOSCompanionText.removeDocument(name)
        return VStack(alignment: .leading, spacing: 2) {
            Text(name)
            if let created = item.created {
                Text(created.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
            if !reason.isEmpty {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(reasonColor)
                    .lineLimit(reasonLines)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("companion.outbox.row.\(item.id)")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                model.removeWaiting(id: item.id)
            } label: {
                Text(IOSCompanionText.removeButton)
            }
            .accessibilityLabel(Text(removeName))
        }
    }

    private func waitingReason(_ item: PhoneOutboxItem) -> String {
        if item.refused { return IOSCompanionText.notSent(item.lastError) }
        if item.inSyncFolder { return IOSCompanionText.inCloudFolderRow }
        return item.lastError
    }

    private var otherOutboxSection: some View {
        Section {
            Text(IOSCompanionText.forUnpairedComputer(state.companionOtherOutboxCount))
                .accessibilityIdentifier("companion.otherOutbox")
            Button(IOSCompanionText.removeAllButton, role: .destructive) {
                confirmingRemoveOther = true
            }
            .accessibilityIdentifier("companion.otherOutbox.remove")
            .confirmationDialog(IOSCompanionText.removeAllTitle(state.companionOtherOutboxCount),
                                isPresented: $confirmingRemoveOther, titleVisibility: .visible) {
                Button(IOSCompanionText.removeAllButton, role: .destructive) {
                    model.removeOtherWaiting()
                }
                .accessibilityIdentifier("companion.otherOutbox.remove.confirm")
            } message: {
                Text(IOSCompanionText.removeAllMessage(state.companionOtherOutboxCount, computer: nil))
            }
        }
    }

    private var cloudFolderSection: some View {
        Section {
            LabeledContent(IOSCompanionText.cloudFolderLabel) {
                Text(model.cloudFolderValue)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .accessibilityIdentifier("companion.cloudFolder")
            HStack {
                Button(IOSCompanionText.chooseFolderButton) {
                    choosingFolder = true
                }
                .accessibilityIdentifier("companion.cloudFolder.choose")
                if state.companionDesktop?.syncFolderBookmark != nil {
                    Spacer()
                    Button(IOSCompanionText.clearButton) {
                        model.clearCloudFolder()
                    }
                    .accessibilityIdentifier("companion.cloudFolder.clear")
                }
            }
            .buttonStyle(.borderless)
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [UTType.folder]) { (result: Result<URL, Error>) in
                switch result {
                case .success(let url):
                    model.chooseCloudFolder(url)
                case .failure(let error):
                    state.errorMessage = error.localizedDescription
                }
            }
        } footer: {
            Text(CompanionText.syncFolderLine)
        }
    }

    @ViewBuilder private var pairSections: some View {
        if model.code == nil {
            Section {
                steps
                if !model.needsExplanation {
                    PairingScannerView(started: scanning, onStart: { scanning = true }, onCode: { (value: String) in
                        model.scanned(value)
                    })
                }
            } header: {
                Text(IOSCompanionText.pairTitle)
            }
            if let browser = model.browser, !model.needsExplanation {
                CompanionNearbySection(browser: browser, model: model, codeFocused: $codeFocused)
            }
            Section {
                textField
                if let problem = model.problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(Color.red)
                        .accessibilityIdentifier("companion.problem")
                }
                pairButton
            } header: {
                Text(IOSCompanionText.pasteCaption)
                    .accessibilityIdentifier("companion.textCaption")
            }
        } else {
            pairedCodeSection
        }
    }

    private var pairedCodeSection: some View {
        Section {
            if let check = model.checkCode {
                VStack(alignment: .leading, spacing: 4) {
                    if let name = model.code?.name {
                        Text(IOSCompanionText.pairWith(name))
                            .font(.headline)
                            .accessibilityIdentifier("companion.pairWith")
                    }
                    Text(check)
                        .font(.title2.monospacedDigit())
                        .accessibilityIdentifier("companion.checkCode")
                    Text(IOSCompanionText.compareLine)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                }
                .accessibilityElement(children: .combine)
                TextField(IOSCompanionText.phoneNameLabel, text: $model.phoneName)
                    .textInputAutocapitalization(.words)
                    .disabled(model.isPairing)
                    .accessibilityLabel(Text(IOSCompanionText.phoneNameLabel))
                    .accessibilityIdentifier("companion.phoneName")
            }
            DisclosureGroup(IOSCompanionText.textLabel, isExpanded: $textExpanded) {
                textField
            }
            .disabled(model.isPairing)
            .accessibilityIdentifier("companion.textDisclosure")
            pairButton
        } header: {
            Text(IOSCompanionText.pairTitle)
        }
    }

    /// Pair, with the line that says the computer is asking its user while it waits.
    @ViewBuilder private var pairButton: some View {
        if model.isPairing {
            HStack(spacing: 8) {
                ProgressView()
                Text(IOSCompanionText.waitingLine)
                    .font(.footnote)
            }
            .accessibilityElement(children: .combine)
        }
        Button {
            Task { await model.pair() }
        } label: {
            Text(IOSCompanionText.pairButton)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.canPair)
        .accessibilityIdentifier("companion.pair")
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(IOSCompanionText.installLine)
                .accessibilityIdentifier("companion.step1")
            Text(IOSCompanionText.openLine)
                .accessibilityIdentifier("companion.step2")
        }
    }

    private var textField: some View {
        TextField(IOSCompanionText.textPlaceholder, text: $model.text, axis: .vertical)
            .lineLimit(1...4)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
            .disabled(model.isPairing || model.needsExplanation)
            .accessibilityLabel(Text(IOSCompanionText.textLabel))
            .accessibilityIdentifier("companion.text")
    }
}

/// The computers seen on the network, one row each; the one tapped opens a row for the short code shown on
/// it, and the sixth digit sends it. Not drawn while Local Network access is off (the line below the form
/// says why).
private struct CompanionNearbySection: View {
    @ObservedObject var browser: IOSCompanionBrowser
    @ObservedObject var model: IOSCompanionModel
    var codeFocused: FocusState<Bool>.Binding
    @State private var waited: Bool = false

    private var showsCode: Bool {
        browser.computers.contains { (computer: NearbyComputer) -> Bool in computer.id == model.chosen?.id }
    }

    var body: some View {
        if !browser.accessDenied {
            Section {
                if browser.computers.isEmpty {
                    emptyRow
                }
                ForEach(browser.computers) { (computer: NearbyComputer) in
                    computerRow(computer)
                    if model.chosen?.id == computer.id {
                        codeRows(computer)
                    }
                }
            } header: {
                Text(IOSCompanionText.nearbyTitle)
                    .accessibilityIdentifier("companion.nearby")
            } footer: {
                if showsCode {
                    Text(IOSCompanionText.codeFooter)
                }
            }
        }
    }

    private var emptyRow: some View {
        HStack(spacing: 8) {
            if waited {
                Text(IOSCompanionText.noComputers)
            } else {
                ProgressView()
                Text(IOSCompanionText.lookingForComputers)
            }
        }
        .foregroundStyle(Color.secondary)
        .task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            waited = true
        }
    }

    private func computerRow(_ computer: NearbyComputer) -> some View {
        let isChosen: Bool = model.chosen?.id == computer.id
        let symbol: String = isChosen ? "checkmark" : "chevron.right"
        let tint: Color = isChosen ? Color.accentColor : Color.secondary
        let traits: AccessibilityTraits = isChosen ? AccessibilityTraits.isSelected : AccessibilityTraits()
        return Button {
            model.choose(computer)
            codeFocused.wrappedValue = true
        } label: {
            HStack {
                Text(computer.name)
                    .foregroundStyle(Color.primary)
                Spacer()
                Image(systemName: symbol)
                    .foregroundStyle(tint)
            }
        }
        .disabled(model.isCheckingCode && !isChosen)
        .accessibilityHint(Text(IOSCompanionText.nearbyHint))
        .accessibilityAddTraits(traits)
        .accessibilityIdentifier("companion.nearby.row.\(computer.id)")
    }

    @ViewBuilder private func codeRows(_ computer: NearbyComputer) -> some View {
        let label: String = IOSCompanionText.codeLabel(computer.name)
        LabeledContent(label) {
            TextField("", text: $model.nearbyCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.body.monospacedDigit())
                .multilineTextAlignment(.trailing)
                .focused(codeFocused)
                .disabled(model.isCheckingCode)
                .accessibilityLabel(Text(label))
                .accessibilityIdentifier("companion.code")
        }
        if model.isCheckingCode {
            HStack(spacing: 8) {
                ProgressView()
                Text(IOSCompanionText.checkingCode)
                    .font(.footnote)
            }
            .accessibilityElement(children: .combine)
        }
        if let problem = model.codeProblem {
            Text(problem)
                .font(.footnote)
                .foregroundStyle(Color.red)
                .accessibilityIdentifier("companion.code.problem")
        }
    }
}

/// Local Network access is off: the one line, with Open Settings.
private struct CompanionNetworkLine: View {
    @ObservedObject var browser: IOSCompanionBrowser

    var body: some View {
        if browser.accessDenied {
            Section {
                Text(IOSNetworkText.companionDeniedLine)
                    .accessibilityIdentifier("companion.denied")
                Button(IOSNetworkText.settingsButton) {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
                .accessibilityIdentifier("companion.settings")
            }
        }
    }
}
#endif
