#if os(iOS)
import LazyScanKit
import SwiftUI

/// The iPhone's library, out of the capture path: the saved files or this session's scans, picked with a
/// segmented control in the navigation bar, a back control at its leading corner (`onClose`) and Settings
/// in its toolbar (`onOpenSettings`, Command-comma). The iPad's sidebar lists them on their own.
struct LibraryScreen: View {
    /// Opens Settings; nil where it is offered elsewhere.
    var onOpenSettings: (() -> Void)?
    let onClose: () -> Void
    @State private var part: LibraryPart = .saved

    var body: some View {
        Group {
            switch part {
            case .saved:
                SavedFilesScreen()
            case .history:
                HistoryScreen()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onClose()
                } label: {
                    Label("Close", systemImage: "chevron.backward")
                        .labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("library.back")
            }
            ToolbarItem(placement: .principal) {
                Picker(IOSSettingsText.libraryLabel, selection: $part) {
                    Text(IOSSettingsText.savedLabel).tag(LibraryPart.saved)
                    Text(IOSSettingsText.historyLabel).tag(LibraryPart.history)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .accessibilityIdentifier("library.part")
            }
            ToolbarItem(placement: .topBarTrailing) {
                settingsButton
            }
        }
    }

    @ViewBuilder
    private var settingsButton: some View {
        if let open = onOpenSettings {
            Button {
                open()
            } label: {
                Label(IOSSettingsText.title, systemImage: "gearshape")
            }
            .keyboardShortcut(IOSShortcuts.settings.keyboardShortcut)
            .accessibilityIdentifier("library.settings")
        }
    }
}

/// The library over the scan screen, slid in from the leading edge (`.move(edge: .leading)`, which Arabic
/// mirrors). A push cannot come from that side. A drag toward the leading edge starting in a strip at the
/// trailing edge, below the bar, closes it following the finger; elsewhere a drag belongs to the list's
/// scrolling, its row swipes and the segmented control.
struct LibraryPanel: View {
    var onOpenSettings: () -> Void
    /// Closes without an animation; the panel animates the ways out itself.
    let onClose: () -> Void
    @Environment(\.layoutDirection) private var direction: LayoutDirection
    @State private var pull: CGFloat = 0

    /// The sign of a horizontal movement toward the leading edge.
    private var toward: CGFloat {
        direction == .rightToLeft ? 1 : -1
    }

    var body: some View {
        GeometryReader { (proxy: GeometryProxy) in
            ZStack(alignment: .trailing) {
                NavigationStack {
                    LibraryScreen(onOpenSettings: onOpenSettings, onClose: closeSliding)
                }
                .offset(x: pull * toward)
                Color.clear
                    .frame(width: 24)
                    .padding(.top, proxy.safeAreaInsets.top + 52)
                    .contentShape(Rectangle())
                    .gesture(drag(width: proxy.size.width))
            }
            .background(Color(uiColor: .systemBackground))
        }
        .ignoresSafeArea()
        .accessibilityAction(.escape) {
            closeSliding()
        }
    }

    private func closeSliding() {
        withAnimation {
            onClose()
        }
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { (value: DragGesture.Value) in
                pull = max(0, value.translation.width * toward)
            }
            .onEnded { (value: DragGesture.Value) in
                let ahead: CGFloat = value.predictedEndTranslation.width * toward
                if pull > width / 3 || ahead > width / 2 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        pull = width
                    } completion: {
                        onClose()
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        pull = 0
                    }
                }
            }
    }
}

enum LibraryPart: Hashable {
    case saved
    case history
}
#endif
