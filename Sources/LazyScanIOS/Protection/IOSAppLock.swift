#if os(iOS)
import Foundation
import LocalAuthentication

/// How the device can check its owner: Face ID, Touch ID, or the passcode alone.
public enum IOSLockMethod: Equatable, Sendable {
    case faceID
    case touchID
    case passcode

    /// The Options switch's label.
    public var switchLabel: String {
        switch self {
        case .faceID: return String(localized: "Require Face ID")
        case .touchID: return String(localized: "Require Touch ID")
        case .passcode: return String(localized: "Require passcode")
        }
    }
}

/// What asking the device came to. `unavailable` is a device with no passcode set.
public enum IOSAuthResult: Equatable, Sendable {
    case success
    case cancelled
    case failed
    case unavailable
}

/// Asks the device's owner to prove it; the lock's tests use one of their own.
public protocol IOSLockAuthenticator: Sendable {
    var method: IOSLockMethod { get }
    func authenticate(reason: String) async -> IOSAuthResult
}

/// Face ID or Touch ID, with the device passcode as the fallback.
public struct IOSDeviceAuthenticator: IOSLockAuthenticator {
    public init() {}

    public var method: IOSLockMethod {
        let context = LAContext()
        var probe: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &probe) else { return .passcode }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .passcode
        }
    }

    public func authenticate(reason: String) async -> IOSAuthResult {
        let context = LAContext()
        var probe: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &probe) else { return .unavailable }
        do {
            let proved: Bool = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            return proved ? .success : .failed
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .systemCancel, .appCancel: return .cancelled
            case .passcodeNotSet: return .unavailable
            default: return .failed
            }
        } catch {
            return .failed
        }
    }
}

/// The optional lock on the Library and the pages kept: locked at launch and whenever the app goes to the
/// background while the switch is on, open only after the device has been asked. A cancel leaves it locked,
/// a failure says so (`failed`). A device whose passcode was removed since opens without asking, so nobody
/// is locked out of their own scans.
@MainActor
public final class IOSAppLock: ObservableObject {
    public enum State: Equatable {
        case locked
        case unlocking
        case failed
        case unlocked
    }

    /// The user's defaults key of the switch.
    public static let key = "lock.required"

    @Published public private(set) var state: State
    @Published public private(set) var enabled: Bool
    private let defaults: UserDefaults
    private let authenticator: any IOSLockAuthenticator
    /// The next time the cover is up and the app is active, the prompt comes by itself; after a cancel it
    /// waits for the Unlock button.
    private var promptDue: Bool
    /// Counts prompts and backgroundings, so a late answer to an earlier prompt is dropped.
    private var attempt: Int = 0

    public init(defaults: UserDefaults = .standard, authenticator: any IOSLockAuthenticator = IOSDeviceAuthenticator()) {
        self.defaults = defaults
        self.authenticator = authenticator
        let on: Bool = defaults.bool(forKey: IOSAppLock.key)
        enabled = on
        state = on ? .locked : .unlocked
        promptDue = on
    }

    public var isLocked: Bool {
        enabled && state != .unlocked
    }

    public var method: IOSLockMethod {
        authenticator.method
    }

    /// Turns the lock on once the device has been asked; the answer says why it stayed off.
    public func enable() async -> IOSAuthResult {
        let result: IOSAuthResult = await authenticator.authenticate(reason: String(localized: "Turn on the lock"))
        if result == .success {
            enabled = true
            state = .unlocked
            defaults.set(true, forKey: IOSAppLock.key)
        }
        return result
    }

    /// Turning it off while locked asks first, since Options can be open under the cover.
    public func disable() async {
        if isLocked {
            await unlock()
        }
        guard !isLocked else { return }
        enabled = false
        state = .unlocked
        defaults.set(false, forKey: IOSAppLock.key)
    }

    public func didEnterBackground() {
        guard enabled else { return }
        attempt += 1
        state = .locked
        promptDue = true
    }

    /// Asks the device unless a prompt was already made since the app last opened.
    public func promptIfDue() async {
        guard promptDue else { return }
        promptDue = false
        await unlock()
    }

    public func unlock() async {
        guard enabled, state == .locked || state == .failed else { return }
        attempt += 1
        let mine: Int = attempt
        state = .unlocking
        let result: IOSAuthResult = await authenticator.authenticate(reason: String(localized: "Unlock Lazy Scan"))
        // Leaving the app while the prompt was up locked it again.
        guard attempt == mine, state == .unlocking else { return }
        switch result {
        case .success, .unavailable: state = .unlocked
        case .cancelled: state = .locked
        case .failed: state = .failed
        }
    }
}
#endif
