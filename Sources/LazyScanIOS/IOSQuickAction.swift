#if os(iOS)
import LazyScanKit
import SwiftUI
import UIKit

/// An item of the Home Screen icon's long-press menu (Info.plist's UIApplicationShortcutItems): a kind of
/// scan to open the camera on, or the saved files.
public enum IOSQuickAction: String, CaseIterable, Sendable {
    case document
    case receipts
    case idCard
    case saved

    /// The prefix of the types the Info.plist items carry.
    static let typePrefix = "com.lazyscan.lazyscan.quick."

    public init?(shortcutType: String) {
        guard shortcutType.hasPrefix(IOSQuickAction.typePrefix),
              let action = IOSQuickAction(rawValue: String(shortcutType.dropFirst(IOSQuickAction.typePrefix.count)))
        else { return nil }
        self = action
    }

    /// The kind the camera opens on; nil for the saved files.
    public var kind: IOSScanKind? {
        switch self {
        case .document: return .document
        case .receipts: return .receipts
        case .idCard: return .idCard
        case .saved: return nil
        }
    }
}

/// The item chosen on the icon, waiting for the root view: set at a cold launch by the app delegate and
/// while the app runs by the scene delegate.
@MainActor
public final class IOSQuickActions: ObservableObject {
    public static let shared: IOSQuickActions = IOSQuickActions()

    @Published public var pending: IOSQuickAction?

    func receive(_ item: UIApplicationShortcutItem) {
        pending = IOSQuickAction(shortcutType: item.type)
    }
}

@MainActor
final class IOSAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem {
            IOSQuickActions.shared.receive(item)
        }
        let configuration: UISceneConfiguration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = IOSSceneDelegate.self
        return configuration
    }
}

@MainActor
final class IOSSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        IOSQuickActions.shared.receive(shortcutItem)
        completionHandler(true)
    }
}
#endif
