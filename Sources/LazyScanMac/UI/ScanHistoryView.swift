#if os(macOS)
import AppKit
import LazyScanKit
import SwiftUI
import UniformTypeIdentifiers

/// The "Scans" tab: every scan of this session, newest first, as preview cards. The card shows a
/// small preview; the page itself is in a temp file of the session (`ScanHistoryEntry.pageFile`), which
/// Add to queue and Save read.
struct ScanHistoryView: View {
    @EnvironmentObject var state: AppState

    /// Held by the window, which keeps its error alert back while the enlarged view is open.
    @Binding var enlarged: ScanHistoryEntry?
    /// The entry Add to queue just put in the queue, for two seconds.
    @State private var addedID: UUID?
    /// Entries whose page file turned out to be gone.
    @State private var goneIDs: Set<UUID> = []
    @State private var showsGone = false

    /// A window's alert cannot show over the enlarged view, which carries its own.
    private var windowGoneAlert: Binding<Bool> {
        Binding(get: { showsGone && enlarged == nil }, set: { showsGone = $0 })
    }

    var body: some View {
        Group {
            if state.scanHistory.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                        ForEach(state.scanHistory) { entry in
                            card(for: entry)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
        .modifier(GoneAlert(isShown: windowGoneAlert))
        .sheet(item: $enlarged) { entry in
            enlargedView(entry)
                .modifier(GoneAlert(isShown: $showsGone))
                .errorNoticeAlert()
                .environmentObject(state)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text("No scans yet this session")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Every scan appears here as it happens.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
    }

    private func card(for entry: ScanHistoryEntry) -> some View {
        HistoryCard(entry: entry, isAdded: addedID == entry.id, canAdd: !state.isBusy && !state.readsQueue,
                    isAvailable: isAvailable(entry),
                    onEnlarge: { enlarged = entry }, onAdd: { addToQueue(entry) }, onSave: { save(entry) })
    }

    private func enlargedView(_ entry: ScanHistoryEntry) -> some View {
        let canAdd: Bool = !state.isBusy && !state.readsQueue && isAvailable(entry)
        let addTitle: LocalizedStringKey = addedID == entry.id ? "Added" : "Add to queue"
        let caption: LocalizedStringKey = "\(entry.intent.label) · \(entry.dpi) dpi · \(Int(entry.pixelSize.width)) × \(Int(entry.pixelSize.height)) px · \(entry.date.formatted(date: .abbreviated, time: .standard))"
        return VStack(spacing: 12) {
            Image(decorative: entry.thumbnail, scale: 1)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
            HStack {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(addTitle) { addToQueue(entry) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canAdd)
                    .help(addHelp(for: entry))
                    .accessibilityHint(Text("Puts the page at the end of the queue"))
                Button("Save") { save(entry) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isAvailable(entry))
                    .help(saveHelp(for: entry))
                    .accessibilityHint(Text("Opens the save panel"))
                Button("Close") { enlarged = nil }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding()
        .frame(minWidth: 560, idealWidth: 760, minHeight: 460, idealHeight: 640)
    }

    private func isAvailable(_ entry: ScanHistoryEntry) -> Bool {
        entry.pageFile != nil && !goneIDs.contains(entry.id)
    }

    private func addHelp(for entry: ScanHistoryEntry) -> LocalizedStringKey {
        if !isAvailable(entry) { return "This page is no longer available" }
        if state.isBusy || state.readsQueue { return "Wait for the current scan to finish" }
        return "Put this page back in the page queue"
    }

    private func saveHelp(for entry: ScanHistoryEntry) -> LocalizedStringKey {
        isAvailable(entry) ? "Save this page as a file" : "This page is no longer available"
    }

    /// False, with the alert shown and the entry marked, when the page's file is gone.
    private func hasPage(_ entry: ScanHistoryEntry) -> Bool {
        if let file = entry.pageFile, FileManager.default.fileExists(atPath: file.path) { return true }
        goneIDs.insert(entry.id)
        showsGone = true
        return false
    }

    private func addToQueue(_ entry: ScanHistoryEntry) {
        guard isAvailable(entry), !state.isBusy, !state.readsQueue, hasPage(entry) else { return }
        state.addToQueue(entry)
        addedID = entry.id
        AccessibilityNotification.Announcement(String(localized: "Added to queue")).post()
        Task {
            try? await Task.sleep(for: .seconds(2))
            if addedID == entry.id { addedID = nil }
        }
    }

    private func save(_ entry: ScanHistoryEntry) {
        guard isAvailable(entry), hasPage(entry) else { return }
        let format = state.historySaveFormat
        let panel = NSSavePanel()
        panel.title = String(localized: "Save Scan")
        panel.message = String(localized: "Saves this page only.")
        if let type = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        panel.nameFieldStringValue = state.suggestedName + "." + format.fileExtension
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.saveHistoryPage(entry, to: url)
    }
}

/// The alert for a scan whose saved page is gone.
private struct GoneAlert: ViewModifier {
    @Binding var isShown: Bool

    func body(content: Content) -> some View {
        content.alert("Couldn't use this scan", isPresented: $isShown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The saved copy of this page is gone. Scan it again.")
        }
    }
}

private struct HistoryCard: View {
    let entry: ScanHistoryEntry
    let isAdded: Bool
    let canAdd: Bool
    let isAvailable: Bool
    let onEnlarge: () -> Void
    let onAdd: () -> Void
    let onSave: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    private var showsButtons: Bool { isHovering || isFocused }

    private var addTitle: LocalizedStringKey { isAdded ? "Added" : "Add to queue" }

    private var addHelp: LocalizedStringKey {
        if !isAvailable { return "This page is no longer available" }
        return canAdd ? "Put this page back in the page queue" : "Wait for the current scan to finish"
    }

    private var saveHelp: LocalizedStringKey {
        isAvailable ? "Save this page as a file" : "This page is no longer available"
    }

    private var time: String { entry.date.formatted(date: .omitted, time: .standard) }

    private var accessibilityName: String {
        String(localized: "\(entry.intent.label) scan, \(entry.dpi) dpi, \(time)")
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(decorative: entry.thumbnail, scale: 1)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .onTapGesture(perform: onEnlarge)
                .accessibilityLabel(Text("Enlarge scan"))
                .accessibilityAddTraits(.isButton)

            Text("\(entry.intent.label) · \(entry.dpi) dpi")
                .font(.caption)
            Text(time)
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Always laid out, so a card keeps its size; only shown while the pointer or focus is on it.
            HStack(spacing: 6) {
                Button(addTitle, action: onAdd)
                    .disabled(!canAdd || !isAvailable)
                    .help(addHelp)
                    .accessibilityHint(Text("Puts the page at the end of the queue"))
                Button("Save", action: onSave)
                    .disabled(!isAvailable)
                    .help(saveHelp)
                    .accessibilityHint(Text("Opens the save panel"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .opacity(showsButtons ? 1 : 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1))
        .onHover { isHovering = $0 }
        .focusable()
        .focused($isFocused)
        .onKeyPress(phases: .down) { press in handleKey(press) }
        .contextMenu {
            Button("Add to Queue", action: onAdd)
                .disabled(!canAdd || !isAvailable)
            Button("Save\u{2026}", action: onSave)
                .disabled(!isAvailable)
            Divider()
            Button("Enlarge", action: onEnlarge)
        }
        // The buttons show on hover; VoiceOver never hovers.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityName)
        .accessibilityActions {
            Button("Add to queue", action: onAdd)
            Button("Save", action: onSave)
            Button("Enlarge", action: onEnlarge)
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .return && press.modifiers == .command {
            onAdd()
            return .handled
        }
        if (press.key == .return || press.key == .space) && press.modifiers.isEmpty {
            onEnlarge()
            return .handled
        }
        return .ignored
    }
}
#endif
