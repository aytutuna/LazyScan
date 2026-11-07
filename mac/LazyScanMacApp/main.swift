import AppKit
import LazyScanMac

// The Mac app of the App Store build. Everything it does is in the package (Sources/LazyScanMac and the shared
// LazyScanKit); this target only starts it, as Sources/LazyScan does for `swift build`.
NSApplication.shared.setActivationPolicy(.regular)
LazyScanApp.main()
