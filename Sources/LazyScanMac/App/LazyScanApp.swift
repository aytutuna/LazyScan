#if os(macOS)
import AppKit
import LazyScanKit
import LazyScanModel
import SwiftUI
import SystemConfiguration

public struct LazyScanApp: App {
    @StateObject private var state = AppState.makeForMac()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    public init() {
        // No tabs: each would be another window over the same state.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    public var body: some Scene {
        WindowGroup("Lazy Scan") {
            // Minimum size lives on ContentView (700x560) — an outer minimum here
            // would override it and force an oversized window on small screens.
            ContentView()
                .environmentObject(state)
                .onAppear {
                    delegate.state = state
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .commands {
            // No File > New Window: a second window on the same state would show each sheet and alert twice.
            CommandGroup(replacing: .newItem) {}
            // File > Import from iPhone or iPad: Continuity Camera, taken by ContentView's importsItemProviders.
            ImportFromDevicesCommands()
            // Help > Lazy Scan Help: no help book is registered, so the default item only says help isn't available.
            CommandGroup(replacing: .help) {
                Link("Lazy Scan Help", destination: URL(string: "https://scan.alazy.app/#support")!)
            }
        }
    }
}

extension AppState {
    /// The Mac app's state: ImageCaptureCore's scanners and the demo scanner, with the Mac's file
    /// actions, troubleshooter links, printing and app lifecycle, the corner model for imported photos
    /// when it is in the build (`FastViTCornerModel`), the password dialog of a protected
    /// PDF (`PDFPasswordWindow`), the question before adding pages to a signed or PDF/A file, and the
    /// phone link's pieces (the keychain identity, the interfaces, DNS-SD, the phones' sync keys in the
    /// keychain), started when a phone is paired. The save folder and the cloud folder are opened through
    /// their bookmarks, which the sandboxed build needs.
    @MainActor
    static func makeForMac() -> AppState {
        let backends: [any ScannerBackend] = [ICScannerBackend(), AppState.makeDemoBackend()]
        let state = AppState(backends: backends,
                             fileActions: SystemFileActions(),
                             troubleshooterService: SystemTroubleshooterService(),
                             printService: SystemPrintService(),
                             lifecycle: AppKitLifecycle(),
                             keepsQueue: true, discardsQueueAtQuit: true)
        // The spool earlier builds kept in the temporary folder.
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("LazyScan-pages", isDirectory: true))
        state.cornerModel = FastViTCornerModel.isAvailable ? FastViTCornerModel.shared : nil
        state.resolveDestinationBookmark = { MacBookmarkedFolder.saveFolder.resolve($0) }
        state.openBookmarkedFolder()
        state.askPDFPassword = { PDFPasswordWindow.ask() }
        state.confirmAppend = { AppState.confirmAppendAlert($0) }
        let computerName = SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "Mac"
        let hostName = SCDynamicStoreCopyLocalHostName(nil) as String? ?? "Mac"
        var companion = CompanionServiceOptions(settingsDirectory: CompanionService.settingsFolder,
                                                dataDirectory: CompanionService.dataFolder(),
                                                identity: CompanionCertificateStore(hostName: hostName),
                                                networks: MacNetworkSource(), desktopName: computerName)
        companion.advertiser = MacDnsSdAdvertiser()
        companion.syncKeyStore = MacCompanionSyncKeys()
        companion.resolveSyncFolder = { MacBookmarkedFolder.syncFolder.resolve($0, mounting: $1) }
        state.setUpCompanionHost(companion)
        return state
    }
}
#endif
