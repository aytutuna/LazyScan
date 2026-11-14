#if os(macOS)
import LazyScanKit
import SwiftUI

/// Slim bar under the preview canvas: current status, a busy spinner, and what can be done with
/// the files saved last (open, show in Finder, share, add more pages, copy; open with and email in
/// More). The twin of the bar Windows shows after a save. The status shows at most six words,
/// facts only (`StatusLine`); VoiceOver reads the whole sentence.
struct StatusBarView: View {
    @EnvironmentObject var state: AppState
    @State private var statusBeforeBusy = ""

    /// Called once the saved PDF is the target of the next scan, so the window can show the scanner.
    let onAddPages: () -> Void

    /// The actions with their own button; the rest are in More.
    private static let barActions: [FileAction] = [.open, .reveal, .share, .addPages, .copy]

    /// What is left of them on a narrow bar.
    private static let narrowBarActions: [FileAction] = [.open]

    /// How Send to phone shows on the bar: its name beside the icon, or the icon alone.
    private enum SendStyle {
        case named
        case iconOnly
    }

    var body: some View {
        HStack(spacing: 8) {
            statusText
            if showsUndo {
                Button("Undo") {
                    if state.canUndoSave {
                        state.undoSave()
                    } else {
                        state.undoRemove()
                        AccessibilityNotification.Announcement(state.statusMessage).post()
                    }
                }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(Color.accentColor)
                    .disabled(state.isBusy || state.readsQueue)
                    .help(undoHelp)
                    .accessibilityHint(Text(undoHint))
                    .accessibilityIdentifier(undoIdentifier)
            }
            if showsHeldCopy {
                heldCopyActions
            }
            if state.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            Spacer(minLength: 16)
            if !state.lastSavedURLs.isEmpty {
                savedActions
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .onChange(of: state.isBusy) { (_: Bool, busy: Bool) in
            if busy {
                statusBeforeBusy = state.statusMessage
            } else if !state.statusMessage.isEmpty, state.statusMessage != statusBeforeBusy {
                AccessibilityNotification.Announcement(state.statusMessage).post()
            }
        }
        .onChange(of: state.phoneSends) { (old: [PhoneSend], sends: [PhoneSend]) in
            if let changed = sends.first(where: { s in !old.contains(s) }) {
                AccessibilityNotification.Announcement(changed.message).post()
            }
        }
    }

    private var showsUndo: Bool { state.canUndoSave || state.canUndoRemove }

    private var undoIdentifier: String { state.canUndoSave ? "save.undo" : "pages.undo" }

    private var showsHeldCopy: Bool { state.copyIsKept && !state.copyPages.isEmpty && !state.isBusy }

    /// A copy that did not print is still here: print it again on the same printer, or pick another.
    private var heldCopyActions: some View {
        HStack(spacing: 8) {
            Button("Print Again") {
                state.printHeldCopyAgain()
            }
                .foregroundStyle(Color.accentColor)
                .help(String(localized: "Print the copy again on the same printer"))
                .accessibilityHint(Text("Prints the copy again on the same printer"))
            Button("Choose Another Printer…") {
                state.printHeldCopy()
            }
                .help(String(localized: "Pick a printer and print the copy"))
                .accessibilityLabel(Text("Choose Another Printer"))
                .accessibilityHint(Text("Opens the print panel to pick a printer"))
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    private var undoHelp: String {
        if state.canUndoSave {
            return state.undoSaveRestoresPDF
                ? String(localized: "Put the pages back and restore the PDF as it was")
                : String(localized: "Put the pages back and delete the saved files")
        }
        if state.removedByReorder { return String(localized: "Put the pages back as they were") }
        return L10n.plural(state.removedCount, one: "Put the page back", other: "Put the pages back")
    }

    private var undoHint: String {
        if state.canUndoSave { return String(localized: "Puts the pages back, deleting the saved files or restoring the PDF they were added to. Files already shared or sent stay where they went.") }
        if state.removedByReorder { return String(localized: "Puts back the pages as they were before the spreads were updated") }
        return L10n.plural(state.removedCount, one: "Puts back the removed page", other: "Puts back the removed pages")
    }

    /// The status in six words at most: empty while a review shows its own title, "Saved" while the
    /// saved files' actions show (with any warning a setting changed for the scanner adds).
    private var shownStatus: String {
        let idle: Bool = !state.isBusy
        let device: String? = state.devices.first(where: { $0.id == state.selectedDeviceID })?.name
        let reviewShown: Bool = idle && (state.showPhotoReview || state.showIdCardReview)
        let savedShown: Bool = idle && !state.lastSavedURLs.isEmpty
        return StatusLine.shown(state.statusMessage, state.statusDetail, deviceName: device, reviewShown: reviewShown, savedShown: savedShown)
    }

    /// The status, and after a save the file's name beside it (middle-truncated, the full path as
    /// help); several files read as one phrase with the folder's name. VoiceOver reads the sentence.
    private var statusText: some View {
        let urls: [URL] = state.lastSavedURLs
        let showsSaved: Bool = !state.isBusy && !state.showPhotoReview && !state.showIdCardReview && !urls.isEmpty
        let single: Bool = urls.count == 1
        let folder: URL? = urls.first?.deletingLastPathComponent()
        let plainSaved: Bool = shownStatus == L10n.t("Saved")
        let path: String = single ? urls[0].path : (folder?.path ?? "")
        let help: String = state.copyPrintFailure ?? (showsSaved ? path : "")
        let label: String = state.copyPrintFailure ?? state.statusMessage
        return HStack(spacing: 6) {
            if showsSaved && !single && plainSaved, let folder {
                Text(savedFilesPhrase(urls.count, folder: folder.lastPathComponent))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(shownStatus)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }
            if showsSaved && single {
                Text(urls[0].lastPathComponent)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .draggable(urls[0])
            }
        }
        .help(help)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(label))
    }

    private func savedFilesPhrase(_ count: Int, folder: String) -> String {
        if folder.isEmpty {
            return L10n.plural(count, one: "Saved {0} file", other: "Saved {0} files")
        }
        return L10n.plural(count, one: "Saved {0} file in {1}", other: "Saved {0} files in {1}", folder)
    }

    private var savedActions: some View {
        let urls = state.lastSavedURLs
        let offered = state.savedFileActions
        // Open with is in the menu for one saved file only (`SaveActions.offered`).
        let phone: PairedDevice? = state.phoneToSendTo
        let moreHelp: String = urls.count == 1
            ? String(localized: "More: open with, email and the other actions")
            : String(localized: "More: email and the other actions")
        return HStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                barRow(Self.barActions, offered: offered, urls: urls, phone: phone, send: .named)
                barRow(Self.barActions, offered: offered, urls: urls, phone: phone, send: .iconOnly)
                barRow(Self.narrowBarActions, offered: offered, urls: urls, phone: nil, send: .iconOnly)
            }
            Menu {
                ForEach(offered) { action in
                    Button {
                        run(action, urls: urls)
                    } label: {
                        Label(title(of: action), systemImage: action.systemImage)
                    }
                }
                if let phone {
                    Button {
                        state.sendToPhone(urls, device: phone)
                    } label: {
                        Label(L10n.t("Send to {0}", phone.name), systemImage: "paperplane")
                    }
                    .disabled(state.isBusy || state.isWaitingToSend(to: phone))
                    .accessibilityIdentifier("saved.menu.sendToPhone")
                }
            } label: {
                Label("More actions", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(moreHelp)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    private func barRow(_ actions: [FileAction], offered: [FileAction], urls: [URL], phone: PairedDevice?,
                        send: SendStyle) -> some View {
        HStack(spacing: 10) {
            if let phone {
                sendButton(phone, urls: urls, style: send)
                    .accessibilityIdentifier("saved.sendToPhone")
            }
            barButtons(actions, offered: offered, urls: urls)
        }
    }

    private func sendButton(_ phone: PairedDevice, urls: [URL], style: SendStyle) -> some View {
        let title: String = L10n.t("Send to {0}", phone.name)
        let waiting: Bool = state.isWaitingToSend(to: phone)
        let help: String = waiting
            ? L10n.t("Waiting for {0} to fetch the last file.", phone.name)
            : L10n.plural(urls.count, one: "Send this file to your phone. It is fetched the next time Lazy Scan is open on the phone.",
                          other: "Send these files to your phone. They are fetched the next time Lazy Scan is open on the phone.")
        let appState: AppState = state
        return Button {
            appState.sendToPhone(urls, device: phone)
        } label: {
            Label(title, systemImage: "paperplane")
                .labelStyle(SendLabelStyle(iconOnly: style == .iconOnly))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 160)
        }
        .disabled(state.isBusy || waiting)
        .help(help)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(help))
    }

    private func barButtons(_ actions: [FileAction], offered: [FileAction], urls: [URL]) -> some View {
        HStack(spacing: 10) {
            ForEach(offered.filter { actions.contains($0) }) { action in
                Button {
                    run(action, urls: urls)
                } label: {
                    Label(title(of: action), systemImage: action.systemImage)
                }
                .labelStyle(.iconOnly)
                .help(action.hint(fileCount: urls.count))
                .accessibilityHint(Text(action.hint(fileCount: urls.count)))
                .accessibilityIdentifier("saved.\(action.rawValue.lowercased())")
            }
        }
        .fixedSize()
    }

    /// Title case on the Mac, where the Kit's label is a sentence.
    private func title(of action: FileAction) -> String {
        action == .addPages ? String(localized: "Add More Pages") : action.label
    }

    private func run(_ action: FileAction, urls: [URL]) {
        guard action == .addPages, let url = urls.first else {
            state.runFileAction(action, urls: urls)
            return
        }
        let appState: AppState = state
        let switchToScanner: () -> Void = onAddPages
        Task { @MainActor in
            if await appState.addMorePages(to: url) {
                switchToScanner()
            }
        }
    }
}

/// The title and icon together, or the icon alone.
private struct SendLabelStyle: LabelStyle {
    let iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            configuration.icon
        } else {
            HStack(spacing: 4) {
                configuration.icon
                configuration.title
            }
        }
    }
}

extension AppState {
    /// The phone Send to phone goes to: the one seen last, with "Phone" for a name it never gave. Nil when
    /// none is paired.
    var phoneToSendTo: PairedDevice? {
        let devices: [PairedDevice] = companionService?.devices.devices ?? []
        guard var phone = devices.max(by: { ($0.lastSeen ?? .distantPast) < ($1.lastSeen ?? .distantPast) }) else { return nil }
        if phone.name.isEmpty { phone.name = String(localized: "Phone") }
        return phone
    }

    /// The last file sent to `phone` has not been fetched yet.
    func isWaitingToSend(to phone: PairedDevice) -> Bool {
        phoneSends.last(where: { $0.phoneName == phone.name })?.fetched == false
    }

    /// Puts the saved files in the phone's outbox; a file that cannot be copied stops the rest and shows the alert.
    func sendToPhone(_ urls: [URL], device phone: PairedDevice) {
        for url in urls {
            if !sendToPhone(url, to: phone) {
                errorMessage = L10n.t("Could not send {0} to {1}: {2}", url.lastPathComponent, phone.name, statusMessage)
                return
            }
        }
    }
}
#endif
