#if os(macOS)
import AppKit
import LazyScanKit
import SwiftUI

/// UserDefaults key of the Phone window's "Show Lazy Scan in the menu bar" switch.
let keepReceivingKey = "keepReceivingInBackground"

/// The menu bar item's menu: whether phones can send, and the way back to the window or out of the app.
struct BackgroundMenu: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    private var receiving: Bool {
        state.companionHostStatus.state == .listening
            && state.companionHostStatus.networks.contains { $0.trust != .notTrusted }
    }

    var body: some View {
        let status = receiving ? String(localized: "Receiving from phone") : String(localized: "Not receiving")
        Text(status)
        Divider()
        Button("Open Lazy Scan") { showWindow() }
        Button("Quit Lazy Scan") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showWindow() {
        if NSApp.isHidden { NSApp.unhide(nil) }
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized) }) {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }
}
#endif
