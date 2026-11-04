#if os(iOS)
import LazyScanKit
import Foundation
import UIKit

/// The short texts of My computer and of Send to computer (the less-text rules: a title of five words at
/// most, a line of eight, buttons of two or three). Longer sentences are the Kit's (`CompanionText`).
public enum IOSCompanionText {
    public static var title: String { String(localized: "My computer") }
    public static var pairTitle: String { String(localized: "Pair with a computer") }
    public static var pairLine: String { String(localized: "On the computer, choose Pair a phone.") }
    public static var textLabel: String { String(localized: "Enter pairing text") }
    public static let textPlaceholder = "lazyscan://pair?\u{2026}"
    public static var compareLine: String { String(localized: "Compare with the code on the computer") }
    /// The model word ("iPhone", "iPad") instead of "phone", here and in `waitingLine`.
    @MainActor public static var phoneNameLabel: String { String(localized: "Name of this \(UIDevice.current.model)") }
    public static var pairButton: String { String(localized: "Pair") }
    @MainActor public static var waitingLine: String { String(localized: "Accept this \(UIDevice.current.model) on the computer.") }
    public static var refreshButton: String { String(localized: "Refresh") }
    public static var sendAgainButton: String { String(localized: "Send again") }
    public static var removeButton: String { String(localized: "Remove") }
    public static var unpairButton: String { String(localized: "Unpair") }
    public static var notPaired: String { String(localized: "Not paired") }
    public static var checking: String { String(localized: "Checking\u{2026}") }
    public static var connected: String { String(localized: "Connected") }
    public static var nothingWaiting: String { String(localized: "Nothing waiting to be sent") }
    public static var cloudFolderLabel: String { String(localized: "Cloud folder") }
    public static var noCloudFolder: String { String(localized: "None") }
    public static var cloudFolderOutOfReach: String { String(localized: "Cannot be opened") }
    public static var chooseFolderButton: String { String(localized: "Choose\u{2026}") }
    public static var clearButton: String { String(localized: "Clear") }
    /// The scan screen's button and its question.
    public static var sendButton: String { String(localized: "Send to computer") }
    public static var sendQuestion: String { String(localized: "Send the pages to the computer") }
    public static var newDocument: String { String(localized: "New document") }
    public static var intoOpenDocument: String { String(localized: "Into the open document") }
    /// Under After saving's Send to computer while it is dimmed.
    public static var sendNeedsPagesReason: String { String(localized: "Send to computer needs the pages collected before saving") }
    public static var sendNeedsPairingReason: String { String(localized: "Pair a computer in Settings > My computer first") }

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

    /// "2 documents for a computer no longer paired": queued for it before another was paired.
    public static func forUnpairedComputer(_ count: Int) -> String {
        L10n.plural(count, one: "{0} document for a computer no longer paired", other: "{0} documents for a computer no longer paired")
    }

    /// "2 documents in the cloud folder": put there, not taken by the computer yet.
    public static func inCloudFolder(_ count: Int) -> String {
        L10n.plural(count, one: "{0} document in the cloud folder", other: "{0} documents in the cloud folder")
    }
}

/// My computer: pairing with a computer from its code (scanned, or its text entered, with the check code
/// to compare), then the paired computer's state, what waits to be sent to it, the cloud folder documents
/// go to when it cannot be reached (`IOSSyncFolder`, for a computer that handed out a sync key), and
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
    /// The paired computer handed out a sync key, so a cloud folder can be set (`AppState.canUseSyncFolder`).
    @Published public private(set) var offersCloudFolder: Bool = false
    /// The cloud folder's name; nil when none is set or it does not open now.
    @Published public private(set) var cloudFolderName: String?
    /// The documents in the cloud folder the computer has not taken yet.
    @Published public private(set) var inCloudFolder: Int = 0

    public let state: AppState
    public let browser: IOSCompanionBrowser?

    public init(state: AppState, browser: IOSCompanionBrowser?) {
        self.state = state
        self.browser = browser
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

    /// Pairing is offered: no computer is paired, or the paired one no longer knows this phone.
    public var needsPairing: Bool {
        if state.companionDesktop == nil { return true }
        if case .unpaired = state.companionStatus { return true }
        return false
    }

    public var canPair: Bool {
        code != nil && !isPairing
    }

    /// The cloud folder row's value: the folder's name, "None", or "Cannot be opened" for one set that
    /// does not open now.
    public var cloudFolderValue: String {
        if let name = cloudFolderName { return name }
        return state.companionDesktop?.syncFolderBookmark == nil
            ? IOSCompanionText.noCloudFolder : IOSCompanionText.cloudFolderOutOfReach
    }

    /// The camera read a pairing code.
    public func scanned(_ value: String) {
        text = value
    }

    /// The screen is shown: browsing starts, and the paired desktop is checked (to the end, even when the
    /// screen goes first).
    public func appear() {
        browser?.begin()
        lookAtCloudFolder()
        guard state.companionDesktop != nil else { return }
        let appState: AppState = state
        Task { @MainActor in
            await appState.checkDesktop()
        }
    }

    public func disappear() {
        browser?.end()
    }

    public func refresh() async {
        await state.checkDesktop()
    }

    /// Pairs with the code in `text` under `phoneName`; once paired, what the desktop holds for the phone
    /// is taken while the app is in front.
    public func pair() async {
        guard canPair else { return }
        isPairing = true
        await state.pairDesktop(uri: entered, phoneName: phoneName.trimmingCharacters(in: .whitespacesAndNewlines))
        isPairing = false
        if case .reachable = state.companionStatus {
            text = ""
            state.pullFromDesktop()
        }
        lookAtCloudFolder()
    }

    public func sendAgain() async {
        await state.drainOutbox()
        lookAtCloudFolder()
    }

    /// `folder`, picked in Files, becomes the cloud folder.
    public func chooseCloudFolder(_ folder: URL) {
        do {
            let bookmark: Data = try IOSSyncFolder.bookmark(of: folder)
            state.setSyncFolder(bookmark: bookmark)
        } catch {
            state.errorMessage = error.localizedDescription
        }
        lookAtCloudFolder()
    }

    public func clearCloudFolder() {
        state.setSyncFolder(bookmark: nil)
        IOSSyncFolder.close()
        lookAtCloudFolder()
    }

    /// Reads again whether a cloud folder can be set, its name and what waits in it.
    public func lookAtCloudFolder() {
        offersCloudFolder = state.canUseSyncFolder
        guard let folder = state.openSyncFolder() else {
            cloudFolderName = nil
            inCloudFolder = 0
            return
        }
        cloudFolderName = folder.lastPathComponent
        inCloudFolder = IOSSyncFolder.waitingCount(in: folder)
    }

    public func removeWaiting() {
        state.clearOutbox()
    }

    public func removeOtherWaiting() {
        state.clearOtherOutbox()
    }

    public func unpair() async {
        await state.unpairDesktop()
        IOSSyncFolder.close()
        lookAtCloudFolder()
    }

    private var entered: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
