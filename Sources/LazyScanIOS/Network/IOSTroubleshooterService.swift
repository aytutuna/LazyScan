#if os(iOS)
import LazyScanKit
import Foundation
import Network
import UIKit

/// What the iPhone's troubleshooter can read about the network: whether it is on Wi-Fi or a wired network.
@MainActor
public protocol IOSNetworkStatusReading: AnyObject {
    /// `.privateNetwork` on Wi-Fi or a wired network (iOS has no public and private networks), `.offline`
    /// without one (cellular only included), `.unknown` until the system has said.
    var status: NetworkStatus { get }
}

/// `NWPathMonitor` on the main queue: watches the network path, reads nothing else and sends nothing.
@MainActor
public final class IOSNetworkPath: IOSNetworkStatusReading {
    public private(set) var status: NetworkStatus = .unknown
    private let monitor: NWPathMonitor = NWPathMonitor()

    public init() {
        monitor.pathUpdateHandler = { [weak self] (path: NWPath) -> Void in
            // availableInterfaces, not usesInterfaceType: a Wi-Fi network without internet is not the default route
            let types: [NWInterface.InterfaceType] = path.availableInterfaces.map { (interface: NWInterface) -> NWInterface.InterfaceType in
                interface.type
            }
            let wifi: Bool = types.contains(NWInterface.InterfaceType.wifi)
            let wired: Bool = types.contains(NWInterface.InterfaceType.wiredEthernet)
            let status: NetworkStatus = IOSNetworkPath.status(wifi: wifi, wired: wired)
            MainActor.assumeIsolated {
                self?.status = status
            }
        }
        monitor.start(queue: DispatchQueue.main)
    }

    /// The troubleshooter's network for a path: a Wi-Fi or wired network is where scanners are found, with or
    /// without internet on it.
    public nonisolated static func status(wifi: Bool, wired: Bool) -> NetworkStatus {
        if wifi || wired {
            return .privateNetwork
        }
        return .offline
    }
}

/// The iPhone's and iPad's `TroubleshooterService`: opens the app's page in Settings (where Local Network
/// access is turned on; the only system page an app may open), copies the diagnostics to the pasteboard
/// when the user asks, and fills in the network the troubleshooter checks. It never changes a setting.
@MainActor
public final class IOSTroubleshooterService: TroubleshooterService {
    private let openURL: @MainActor (URL) -> Void
    private let pasteboard: UIPasteboard
    private let network: (any IOSNetworkStatusReading)?

    /// The app's: UIApplication opens Settings, the general pasteboard, the network path.
    public convenience init() {
        self.init(openURL: { (url: URL) -> Void in
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }, pasteboard: UIPasteboard.general, network: IOSNetworkPath())
    }

    /// Tests pass their own opener, pasteboard and network.
    public init(openURL: @escaping @MainActor (URL) -> Void, pasteboard: UIPasteboard,
                network: (any IOSNetworkStatusReading)?) {
        self.openURL = openURL
        self.pasteboard = pasteboard
        self.network = network
    }

    public func open(_ action: TroubleshootAction) throws {
        switch action {
        case .openAppSettings:
            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                throw ScanError.exportFailed(L10n.t("Settings did not open."))
            }
            openURL(url)
        case .refresh, .addByAddress, .openScannerSettings, .openNetworkSettings, .openImageCapture, .copyDiagnostics:
            throw ScanError.unsupported("\(action.rawValue) does not open anything here.")
        }
    }

    public func copy(_ text: String) throws {
        pasteboard.string = text
    }

    public func addSystemStatus(to snapshot: DiscoverySnapshot) -> DiscoverySnapshot {
        guard let network else { return snapshot }
        var updated: DiscoverySnapshot = snapshot
        updated.network = network.status
        return updated
    }
}
#endif
