#if os(macOS)
import AppKit
import LazyScanKit
import Foundation

/// The macOS implementation of `TroubleshooterService`: NSWorkspace for System Settings and Image
/// Capture, NSPasteboard.
@MainActor
public final class SystemTroubleshooterService: TroubleshooterService {
    /// System Settings, Printers & Scanners.
    public static let printersAndScannersURL = URL(string: "x-apple.systempreferences:com.apple.Print-Scanner-Settings.extension")!
    /// System Settings, Network.
    public static let networkSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")!
    /// System Settings, Privacy & Security, Local Network.
    public static let localNetworkSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")!
    /// Image Capture, which lists every scanner macOS sees.
    public static let imageCaptureBundleID = "com.apple.Image_Capture"

    public init() {}

    public func open(_ action: TroubleshootAction) throws {
        switch action {
        case .openScannerSettings:
            guard NSWorkspace.shared.open(Self.printersAndScannersURL) else {
                throw ScanError.exportFailed(L10n.t("System Settings did not open."))
            }
        case .openNetworkSettings:
            guard NSWorkspace.shared.open(Self.networkSettingsURL) else {
                throw ScanError.exportFailed(L10n.t("System Settings did not open."))
            }
        case .openAppSettings:
            guard NSWorkspace.shared.open(Self.localNetworkSettingsURL) else {
                throw ScanError.exportFailed(L10n.t("System Settings did not open."))
            }
        case .openImageCapture:
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.imageCaptureBundleID) else {
                throw ScanError.exportFailed(L10n.t("Image Capture was not found on this Mac."))
            }
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration(),
                                               completionHandler: nil)
        case .refresh, .addByAddress, .removeAddress, .copyDiagnostics:
            throw ScanError.unsupported("\(action.rawValue) does not open anything.")
        }
    }

    public func copy(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw ScanError.exportFailed(L10n.t("The text could not be put on the pasteboard."))
        }
    }
}
#endif
