#if os(iOS)
import LazyScanKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// My computer, a page of the Options sheet (`IOSCompanionModel`): with no computer paired, Pair with a computer
/// (the camera looking for its code, the computers nearby to pick and type the short code shown on one, the
/// code's text to paste instead, the check code to compare, the name the computer will list the phone
/// under, Pair); once paired, each computer's name and state
/// (all checked when the screen opens, and on Refresh), Unpair (asked first), Pair another computer, which
/// opens the pairing form again, and the documents waiting to be
/// sent, each with its date, its computer when several are paired, and why it has not gone, removable by a
/// swipe, with Send again and Remove all
/// (asked first), and those in the cloud folders the computers have not taken yet. For a computer that
/// handed out a sync key, its cloud folder (Choose…, Clear) documents go to when it cannot be reached. A
/// computer that no longer knows the phone is shown with pairing offered again. Local Network access that
/// is off is said with Open Settings. Documents left for a computer no longer paired have a line and a Remove
/// all of their own.
struct CompanionScreen: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var model: IOSCompanionModel
    @State private var choosingFolder: Bool = false
    /// The computer the cloud folder being picked is for.
    @State private var folderDesktop: PairedDesktop?
    /// The computer Unpair was tapped for, until it is answered.
    @State private var unpairing: PairedDesktop?
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
            ForEach(state.companionDesktops, id: \.id) { (desktop: PairedDesktop) in
                computerSection(desktop)
            }
            if state.companionDesktops.count > 1 {
                Section {
                    if model.canRefresh {
                        refreshButton
                    }
                    if model.offersPairAnother {
                        pairAnotherButton
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
            ForEach(state.companionDesktops, id: \.id) { (desktop: PairedDesktop) in
                if model.offersCloudFolder(of: desktop) && model.pairedIds.contains(desktop.id) {
                    cloudFolderSection(desktop)
                }
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
        .confirmationDialog(IOSCompanionText.unpairTitle(unpairing?.name ?? ""), isPresented: unpairShown,
                            titleVisibility: .visible, presenting: unpairing) { (desktop: PairedDesktop) in
            Button(IOSCompanionText.unpairButton, role: .destructive) {
                Task { await model.unpair(desktop) }
            }
            .accessibilityIdentifier("companion.unpair.confirm" + identifierSuffix(desktop))
        } message: { (desktop: PairedDesktop) in
            Text(IOSCompanionText.unpairMessage(waiting: waitingCount(for: desktop)))
        }
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [UTType.folder]) { (result: Result<URL, Error>) in
            switch result {
            case .success(let url):
                if let desktop = folderDesktop {
                    model.chooseCloudFolder(url, for: desktop)
                }
            case .failure(let error):
                state.errorMessage = error.localizedDescription
            }
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
        if !model.needsPairing {
            model.addingComputer = true
        }
        model.scanned(code)
    }

    /// With several computers paired, an identifier names the computer it is for.
    private func identifierSuffix(_ desktop: PairedDesktop) -> String {
        state.companionDesktops.count > 1 ? "." + desktop.id : ""
    }

    private func waitingCount(for desktop: PairedDesktop) -> Int {
        state.companionWaiting.filter { (item: PhoneOutboxItem) -> Bool in item.desktopId == desktop.id }.count
    }

    private var unpairShown: Binding<Bool> {
        let asked: Binding<PairedDesktop?> = $unpairing
        return Binding<Bool>(
            get: { asked.wrappedValue != nil },
            set: { (isShown: Bool) in
                if !isShown { asked.wrappedValue = nil }
            })
    }

    /// A computer's name and state, with Unpair; with one computer paired, Refresh and Pair another computer
    /// are in the same section.
    private func computerSection(_ desktop: PairedDesktop) -> some View {
        let suffix: String = identifierSuffix(desktop)
        let single: Bool = state.companionDesktops.count == 1
        let status: CompanionStatus = state.companionStatuses[desktop.id] ?? CompanionStatus.notPaired
        let unpairName: String = single ? IOSCompanionText.unpairButton : IOSCompanionText.unpairLabel(desktop.name)
        return Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(desktop.name)
                    .font(.headline)
                    .accessibilityIdentifier("companion.name" + suffix)
                Text(IOSCompanionText.status(status))
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                    .accessibilityIdentifier("companion.status" + suffix)
            }
            .accessibilityElement(children: .combine)
            if single && model.canRefresh {
                refreshButton
            }
            Button(role: .destructive) {
                unpairing = desktop
            } label: {
                Label(IOSCompanionText.unpairButton, systemImage: "xmark.circle")
            }
            .disabled(model.isPairing)
            .accessibilityLabel(Text(unpairName))
            .accessibilityIdentifier("companion.unpair" + suffix)
            if single && model.offersPairAnother {
                pairAnotherButton
            }
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await model.refresh() }
        } label: {
            Label(IOSCompanionText.refreshButton, systemImage: "arrow.clockwise")
        }
        .disabled(model.isChecking || model.needsExplanation)
        .accessibilityIdentifier("companion.refresh")
    }

    private var pairAnotherButton: some View {
        Button {
            model.addingComputer.toggle()
        } label: {
            Label(IOSCompanionText.pairAnotherButton, systemImage: "plus.circle")
        }
        .disabled(model.isPairing)
        .accessibilityIdentifier("companion.pairAnother")
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
                .disabled(!model.canRefresh)
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
                    Text(IOSCompanionText.removeAllMessage(state.companionOutboxCount, computer: removeAllComputer))
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

    /// The computer the documents waiting are for, named once only one is paired.
    private var removeAllComputer: String? {
        state.companionDesktops.count == 1 ? state.companionDesktop?.name : nil
    }

    private func waitingRow(_ item: PhoneOutboxItem) -> some View {
        let name: String = URL(fileURLWithPath: item.fileName).deletingPathExtension().lastPathComponent
        let computer: String? = state.companionDesktops.count > 1
            ? state.companionDesktops.first { (desktop: PairedDesktop) -> Bool in desktop.id == item.desktopId }?.name : nil
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
            if let computer {
                Text(computer)
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

    /// A computer's cloud folder; with several computers paired its header names the computer.
    @ViewBuilder private func cloudFolderSection(_ desktop: PairedDesktop) -> some View {
        if state.companionDesktops.count > 1 {
            Section {
                cloudFolderRows(desktop)
            } header: {
                Text(IOSCompanionText.cloudFolderFor(desktop.name))
            } footer: {
                Text(CompanionText.syncFolderLine)
            }
        } else {
            Section {
                cloudFolderRows(desktop)
            } footer: {
                Text(CompanionText.syncFolderLine)
            }
        }
    }

    @ViewBuilder private func cloudFolderRows(_ desktop: PairedDesktop) -> some View {
        let suffix: String = identifierSuffix(desktop)
        LabeledContent(IOSCompanionText.cloudFolderLabel) {
            Text(model.cloudFolderValue(of: desktop))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .accessibilityIdentifier("companion.cloudFolder" + suffix)
        HStack {
            Button(IOSCompanionText.chooseFolderButton) {
                folderDesktop = desktop
                choosingFolder = true
            }
            .accessibilityIdentifier("companion.cloudFolder.choose" + suffix)
            if desktop.syncFolderBookmark != nil {
                Spacer()
                Button(IOSCompanionText.clearButton) {
                    model.clearCloudFolder(of: desktop)
                }
                .accessibilityIdentifier("companion.cloudFolder.clear" + suffix)
            }
        }
        .buttonStyle(.borderless)
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
                CompanionNearbySection(browser: browser, model: model, paired: model.pairedIds, codeFocused: $codeFocused)
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
    /// The computers paired already, left out of the list.
    let paired: Set<String>
    var codeFocused: FocusState<Bool>.Binding
    @State private var waited: Bool = false

    private var computers: [NearbyComputer] {
        browser.computers.filter { (computer: NearbyComputer) -> Bool in !paired.contains(computer.id) }
    }

    private var showsCode: Bool {
        computers.contains { (computer: NearbyComputer) -> Bool in computer.id == model.chosen?.id }
    }

    var body: some View {
        if !browser.accessDenied {
            Section {
                if computers.isEmpty {
                    emptyRow
                }
                ForEach(computers) { (computer: NearbyComputer) in
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
