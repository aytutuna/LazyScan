#if os(iOS)
import LazyScanKit
import Foundation
import UIKit

/// The short texts of My computer and of Send to computer (the less-text rules: a title of five words at
/// most, a line of eight, buttons of two or three). Longer sentences are the Kit's (`CompanionText`).
public enum IOSCompanionText {
    public static var title: String { String(localized: "My computer") }
    public static var openComputer: String { String(localized: "Open My computer") }
    public static var pairTitle: String { String(localized: "Pair with a computer") }
    public static var installLine: String { String(localized: "1. Install Lazy Scan on your Mac or PC (alazy.app/scan).") }
    public static var openLine: String { String(localized: "2. On it, open Phone and pair a phone. Use the same Wi-Fi.") }
    public static var scanButton: String { String(localized: "Scan the code") }
    public static var pasteCaption: String { String(localized: "Or paste the pairing link") }
    public static var nearbyTitle: String { String(localized: "Computers nearby") }
    public static var codeFooter: String { String(localized: "Enter the code shown on the computer.") }
    public static var checkingCode: String { String(localized: "Checking the code") }
    public static var noComputers: String { String(localized: "No computers found") }
    public static var lookingForComputers: String { String(localized: "Looking for computers\u{2026}") }
    public static var nearbyHint: String { String(localized: "Opens the code field") }
    public static func codeLabel(_ name: String) -> String { L10n.t("Code on {0}", name) }
    public static func codeAnnouncement(_ name: String) -> String { L10n.t("Type the 6 digits shown on {0}", name) }
    public static func pairWith(_ name: String) -> String { L10n.t("Pair with {0}", name) }
    public static var textLabel: String { String(localized: "Enter pairing text") }
    public static var textPlaceholder: String { String(localized: "Pairing link") }
    public static var compareLine: String { String(localized: "Compare with the code on the computer") }
    /// The model word ("iPhone", "iPad") instead of "phone", here and in `waitingLine`.
    @MainActor public static var phoneNameLabel: String { String(localized: "Name of this \(UIDevice.current.model)") }
    public static var pairButton: String { String(localized: "Pair") }
    @MainActor public static var waitingLine: String { String(localized: "Accept this \(UIDevice.current.model) on the computer.") }
    public static var refreshButton: String { String(localized: "Refresh") }
    public static var sendAgainButton: String { String(localized: "Send again") }
    public static var removeButton: String { String(localized: "Remove") }
    public static var removeAllButton: String { String(localized: "Remove all") }
    public static var unpairButton: String { String(localized: "Unpair") }
    public static var pairAnotherButton: String { String(localized: "Pair another computer") }
    public static var notPaired: String { String(localized: "Not paired") }
    public static var checking: String { String(localized: "Checking\u{2026}") }
    public static var connected: String { String(localized: "Connected") }
    public static var nothingWaiting: String { String(localized: "Nothing waiting to be sent") }
    public static var cloudFolderLabel: String { String(localized: "Cloud folder") }
    /// The header of a computer's cloud folder while several are paired.
    public static func cloudFolderFor(_ computer: String) -> String { L10n.t("Cloud folder for {0}", computer) }
    public static var noCloudFolder: String { String(localized: "None") }
    public static var cloudFolderOutOfReach: String { String(localized: "Cannot be opened") }
    public static var chooseFolderButton: String { String(localized: "Choose\u{2026}") }
    public static var clearButton: String { String(localized: "Clear") }
    /// The scan screen's button and its question.
    public static var sendButton: String { String(localized: "Send to computer") }
    public static var sendQuestion: String { String(localized: "Send the pages to the computer") }
    public static var chooseComputerQuestion: String { String(localized: "Send to which computer?") }
    public static var newDocument: String { String(localized: "New document") }
    public static var intoOpenDocument: String { String(localized: "Into the open document") }
    /// Under After saving's Send to computer while it is dimmed.
    public static var sendNeedsPagesReason: String { String(localized: "Send to computer needs the pages collected before saving") }
    public static var sendNeedsPairingReason: String { String(localized: "Pair a computer in Options > My computer first") }

    /// The link's state in one line: "Connected · 3 pages queued there", or why not.
    public static func status(_ status: CompanionStatus) -> String {
        switch status {
        case .notPaired:
            return notPaired
        case .checking:
            return checking
        case .reachable(_, let queuedPages):
            if queuedPages == 0 { return connected }
            return L10n.plural(queuedPages, one: "Connected · {0} page queued there", other: "Connected · {0} pages queued there")
        case .unreachable(let reason):
            return reason
        case .unpaired(let desktopName):
            return CompanionText.unpairedMessage(desktopName)
        }
    }

    /// "2 documents waiting to be sent".
    public static func waiting(_ count: Int) -> String {
        if count == 0 { return nothingWaiting }
        return L10n.plural(count, one: "{0} document waiting to be sent", other: "{0} documents waiting to be sent")
    }

    /// "Remove 2 documents?"
    public static func removeAllTitle(_ count: Int) -> String {
        L10n.plural(count, one: "Remove {0} document?", other: "Remove {0} documents?")
    }

    /// "They will not be sent to Office PC."; without a computer, "They will not be sent."
    public static func removeAllMessage(_ count: Int, computer: String?) -> String {
        guard let computer else {
            return L10n.plural(count, one: "It will not be sent.", other: "They will not be sent.")
        }
        return L10n.plural(count, one: "It will not be sent to {1}.", other: "They will not be sent to {1}.", computer)
    }

    public static func unpairTitle(_ computer: String) -> String {
        L10n.t("Unpair {0}?", computer)
    }

    /// The Unpair button's spoken name while several computers are paired.
    public static func unpairLabel(_ computer: String) -> String {
        L10n.t("Unpair {0}", computer)
    }

    /// What unpairing does, with the documents that stay when any wait.
    @MainActor public static func unpairMessage(waiting count: Int) -> String {
        let line: String = String(localized: "The computer will no longer take documents from this \(UIDevice.current.model).")
        if count == 0 { return line }
        let stays: String = L10n.plural(count, one: "{0} document waiting to be sent stays here until you pair it again.",
                                        other: "{0} documents waiting to be sent stay here until you pair it again.")
        return line + " " + stays
    }

    /// "Not sent: The package is larger than the computer accepts."
    public static func notSent(_ reason: String) -> String {
        L10n.t("Not sent: {0}", reason)
    }

    public static var inCloudFolderRow: String { String(localized: "In the cloud folder") }

    /// The swipe action's and the VoiceOver action's name.
    public static func removeDocument(_ name: String) -> String {
        L10n.t("Remove {0}", name)
    }

    /// "2 documents for a computer no longer paired": queued for it before another was paired.
    public static func forUnpairedComputer(_ count: Int) -> String {
        L10n.plural(count, one: "{0} document for a computer no longer paired", other: "{0} documents for a computer no longer paired")
    }

    /// "2 documents in the cloud folder": put there, not taken by the computer yet.
    public static func inCloudFolder(_ count: Int) -> String {
        L10n.plural(count, one: "{0} document in the cloud folder", other: "{0} documents in the cloud folder")
    }
}

/// One computer's cloud folder as last read (`IOSCompanionModel.lookAtCloudFolder`).
public struct IOSCloudFolder: Equatable {
    /// The computer handed out a sync key, so a cloud folder can be set.
    public var offered: Bool
    /// The folder's name; nil when none is set or it does not open now.
    public var name: String?
    /// The documents in the folder the computer has not taken yet.
    public var waiting: Int
}

/// My computer: pairing with a computer from its code (scanned, or its text entered, with the check code
/// to compare), then the paired computers' state, what waits to be sent to them, the cloud folder documents
/// go to when a computer cannot be reached (`IOSSyncFolder`, for one that handed out a sync key), and
/// unpairing. While the screen is shown the desktops on the network are browsed (`IOSCompanionBrowser`).
@MainActor
public final class IOSCompanionModel: ObservableObject {
    /// The pairing code's text, scanned or entered.
    @Published public var text: String = ""
    /// The name the computer lists this phone under. UIDevice's to begin with, which is only the model
    /// ("iPhone") for an app without the user-assigned device name entitlement, so it can be changed.
    @Published public var phoneName: String
    /// The desktop is asked (it asks its user first: up to two minutes).
    @Published public private(set) var isPairing: Bool = false
    /// Pair another computer is open: the pairing form shows beside the computers paired.
    @Published public var addingComputer: Bool = false
    /// Each paired computer's cloud folder, by desktop id.
    @Published public private(set) var cloudFolders: [String: IOSCloudFolder] = [:]

    /// The computer picked in the nearby list; its code row is open.
    @Published public private(set) var chosen: NearbyComputer?
    /// The digits typed in the code row; the sixth sends them (`codeEdited`).
    @Published public var nearbyCode: String = ""
    /// The code is with the computer.
    @Published public private(set) var isCheckingCode: Bool = false
    /// Why the last code did not give a pairing text.
    @Published public private(set) var codeProblem: String?

    /// The explanation card has not been read yet: nothing is browsed or checked until it is.
    @Published public private(set) var needsExplanation: Bool

    public let state: AppState
    public let browser: IOSCompanionBrowser?
    private let network: IOSNetworkScanners?
    private var isShown: Bool = false
    private var isBrowsing: Bool = false

    /// `network` holds whether the explanation card was read (the scanner picker's); nil: no card.
    public init(state: AppState, browser: IOSCompanionBrowser?, network: IOSNetworkScanners? = nil) {
        self.state = state
        self.browser = browser
        self.network = network
        needsExplanation = network?.needsExplanation ?? false
        phoneName = UIDevice.current.name
    }

    /// The pairing code in `text`; nil while there is none or it cannot be used.
    public var code: PairingUri? {
        try? PairingUri.parse(entered)
    }

    /// Why `text` is not a pairing code (`PairingUri`'s messages); nil while it is empty or one.
    public var problem: String? {
        guard !entered.isEmpty else { return nil }
        do {
            _ = try PairingUri.parse(entered)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// The code's check code as shown ("004 213"), to compare with the computer's; nil without a code.
    public var checkCode: String? {
        guard let fingerprint = code?.fingerprintBytes else { return nil }
        return SpkiFingerprint.formatCheckCode(SpkiFingerprint.checkCode(fingerprint))
    }

    /// Pairing is offered: no computer is paired, one no longer knows this phone, or another is being added.
    public var needsPairing: Bool {
        state.companionDesktops.isEmpty || addingComputer || hasUnpaired
    }

    /// A paired computer no longer knows this phone.
    public var hasUnpaired: Bool {
        state.companionDesktops.contains { (desktop: PairedDesktop) -> Bool in
            if case .unpaired? = state.companionStatuses[desktop.id] { return true }
            return false
        }
    }

    /// The ids of the computers that are paired and know this phone, left out of the nearby list.
    public var pairedIds: Set<String> {
        Set(state.companionDesktops.filter { (desktop: PairedDesktop) -> Bool in
            if case .unpaired? = state.companionStatuses[desktop.id] { return false }
            return true
        }.map(\.id))
    }

    /// Refresh has a computer to check.
    public var canRefresh: Bool {
        !pairedIds.isEmpty
    }

    /// Pair another computer is offered: some are paired, and all of them know this phone.
    public var offersPairAnother: Bool {
        !state.companionDesktops.isEmpty && !hasUnpaired
    }

    /// A computer's link is being checked.
    public var isChecking: Bool {
        state.companionStatuses.values.contains(.checking)
    }

    /// Whether a cloud folder can be set for `desktop`.
    public func offersCloudFolder(of desktop: PairedDesktop) -> Bool {
        cloudFolders[desktop.id]?.offered ?? false
    }

    /// The cloud folder of `desktop`, as its row says: the folder's name, "None", or "Cannot be opened" for
    /// one set that does not open now.
    public func cloudFolderValue(of desktop: PairedDesktop) -> String {
        if let name = cloudFolders[desktop.id]?.name { return name }
        return desktop.syncFolderBookmark == nil ? IOSCompanionText.noCloudFolder : IOSCompanionText.cloudFolderOutOfReach
    }

    /// The documents in every cloud folder the computers have not taken yet.
    public var inCloudFolder: Int {
        cloudFolders.values.reduce(0) { (total: Int, folder: IOSCloudFolder) -> Int in total + folder.waiting }
    }

    public var canPair: Bool {
        code != nil && !isPairing && !needsExplanation
    }

    /// The camera read a pairing code.
    public func scanned(_ value: String) {
        text = value
    }

    /// A computer of the nearby list was tapped: its code row opens, here or instead of another's.
    public func choose(_ computer: NearbyComputer) {
        guard !isCheckingCode else { return }
        chosen = computer
        nearbyCode = ""
        codeProblem = nil
        UIAccessibility.post(notification: .announcement, argument: IOSCompanionText.codeAnnouncement(computer.name))
    }

    /// The code row's text changed: only the digits stay, and the sixth is sent to the chosen computer. Its
    /// answer is the pairing text a scan would give (`scanned`), or why not.
    public func codeEdited() async {
        let digits: String = String(nearbyCode.filter { $0.isASCII && $0.isNumber }.prefix(PairingSession.codeDigitCount))
        guard digits == nearbyCode else {
            nearbyCode = digits
            return
        }
        guard digits.count == PairingSession.codeDigitCount, let computer = chosen, !isCheckingCode else { return }
        isCheckingCode = true
        codeProblem = nil
        do {
            let found: String = try await state.fetchPairingText(code: digits, addresses: computer.addresses, port: computer.port)
            chosen = nil
            nearbyCode = ""
            scanned(found)
        } catch {
            nearbyCode = ""
            codeProblem = error.localizedDescription
            UIAccessibility.post(notification: .announcement, argument: error.localizedDescription)
        }
        isCheckingCode = false
    }

    /// The screen is shown: browsing starts, and the paired desktops are checked (to the end, even when the
    /// screen goes first), once the explanation card is read.
    public func appear() {
        isShown = true
        needsExplanation = network?.needsExplanation ?? false
        lookAtCloudFolder()
        startBrowsing()
    }

    public func disappear() {
        isShown = false
        guard isBrowsing else { return }
        isBrowsing = false
        browser?.end()
    }

    /// The card's Continue: the system's prompt follows, and the browsing the card held back starts.
    public func continueAfterExplanation() {
        network?.continueAfterExplanation()
        needsExplanation = false
        startBrowsing()
    }

    private func startBrowsing() {
        guard isShown, !needsExplanation, !isBrowsing else { return }
        isBrowsing = true
        browser?.begin()
        guard !state.companionDesktops.isEmpty else { return }
        let appState: AppState = state
        Task { @MainActor in
            await appState.checkDesktop()
        }
    }

    public func refresh() async {
        await state.checkDesktop()
    }

    /// Pairs with the code in `text` under `phoneName`; once paired, what the desktop holds for the phone
    /// is taken while the app is in front. A code the desktop refused for good is cleared, so the camera
    /// shows again; one that could not be tried (unreachable) stays for a retry.
    public func pair() async {
        guard canPair else { return }
        isPairing = true
        let before: Date? = state.companionDesktop?.pairedAt
        let codeUsedUp: Bool = await state.pairDesktop(uri: entered, phoneName: phoneName.trimmingCharacters(in: .whitespacesAndNewlines))
        isPairing = false
        // A pairing that went through is the one paired last, with a new pairing time.
        if state.companionDesktop?.pairedAt != before {
            text = ""
            addingComputer = false
            state.pullFromDesktop()
        } else if codeUsedUp {
            text = ""
        }
        lookAtCloudFolder()
    }

    public func sendAgain() async {
        await state.drainOutbox()
        lookAtCloudFolder()
    }

    /// `folder`, picked in Files, becomes the cloud folder of `desktop`.
    public func chooseCloudFolder(_ folder: URL, for desktop: PairedDesktop) {
        do {
            let bookmark: Data = try IOSSyncFolder.bookmark(of: folder)
            state.setSyncFolder(bookmark: bookmark, for: desktop)
        } catch {
            state.errorMessage = error.localizedDescription
        }
        lookAtCloudFolder()
    }

    public func clearCloudFolder(of desktop: PairedDesktop) {
        state.setSyncFolder(bookmark: nil, for: desktop)
        IOSSyncFolder.close()
        lookAtCloudFolder()
    }

    /// Reads again, for each paired computer, whether a cloud folder can be set, its name and what waits in it.
    public func lookAtCloudFolder() {
        var folders: [String: IOSCloudFolder] = [:]
        for desktop in state.companionDesktops {
            var folder: IOSCloudFolder = IOSCloudFolder(offered: state.canUseSyncFolder(for: desktop), name: nil, waiting: 0)
            if let opened = state.openSyncFolder(for: desktop) {
                folder.name = opened.lastPathComponent
                folder.waiting = IOSSyncFolder.waitingCount(in: opened)
            }
            folders[desktop.id] = folder
        }
        cloudFolders = folders
    }

    /// The documents waiting for the paired computers, refused ones included.
    public var waitingItems: [PhoneOutboxItem] {
        state.companionWaiting
    }

    /// How many of them will be sent: the refused ones are not.
    public var sendableCount: Int {
        state.companionWaiting.filter { !$0.refused }.count
    }

    public func removeWaiting() {
        state.clearOutbox()
    }

    public func removeWaiting(id: String) {
        state.removeWaiting(id: id)
    }

    public func removeOtherWaiting() {
        state.clearOtherOutbox()
    }

    public func unpair(_ desktop: PairedDesktop) async {
        await state.unpairDesktop(desktop)
        if state.companionDesktops.isEmpty { addingComputer = false }
        IOSSyncFolder.close()
        lookAtCloudFolder()
    }

    private var entered: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
