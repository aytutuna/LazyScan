#if os(macOS)
import LazyScanKit
import SwiftUI

/// Slim bar under the preview canvas: current status, a busy spinner, and what can be done with
/// the files saved last (open, show in Finder, share, copy; open with and email in More). The
/// twin of the bar Windows shows after a save. The status shows at most six words, facts only
/// (`StatusLine`); VoiceOver reads the whole sentence.
struct StatusBarView: View {
    @EnvironmentObject var state: AppState
    @State private var statusBeforeBusy = ""

    /// The actions with their own button; the rest are in More.
    private static let barActions: [FileAction] = [.open, .reveal, .share, .copy]

    var body: some View {
        HStack(spacing: 8) {
            statusText
            if showsUndo {
                Button("Undo") {
                    state.undoRemove()
                    AccessibilityNotification.Announcement(state.statusMessage).post()
                }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(Color.accentColor)
                    .disabled(state.isBusy || state.readsQueue)
                    .help(L10n.plural(state.removedCount, one: "Put the page back", other: "Put the pages back"))
                    .accessibilityHint(Text(L10n.plural(state.removedCount, one: "Puts back the removed page", other: "Puts back the removed pages")))
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
    }

    private var showsUndo: Bool { state.canUndoRemove }

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
        let moreHelp: String = urls.count == 1
            ? String(localized: "More: open with, email and the other actions")
            : String(localized: "More: email and the other actions")
        return HStack(spacing: 10) {
            ForEach(offered.filter { Self.barActions.contains($0) }) { action in
                Button {
                    state.runFileAction(action, urls: urls)
                } label: {
                    Label(action.label, systemImage: action.systemImage)
                }
                .labelStyle(.iconOnly)
                .help(action.hint(fileCount: urls.count))
            }
            Menu {
                ForEach(offered) { action in
                    Button {
                        state.runFileAction(action, urls: urls)
                    } label: {
                        Label(action.label, systemImage: action.systemImage)
                    }
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
}
#endif
