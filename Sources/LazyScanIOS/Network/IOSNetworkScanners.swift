#if os(iOS)
import LazyScanKit
import Foundation
import UIKit

/// The short texts of the network scanner screens (the less-text rules: a title of five words at most, a
/// line of eight, buttons of two).
public enum IOSNetworkText {
    /// The explanation card shown before the first search, so the system's Local Network prompt is understood.
    public static var explanationTitle: String { String(localized: "Find scanners on your Wi-Fi") }
    public static var explanationLine: String { String(localized: "Lazy Scan talks only to devices on your network.") }
    public static var explanationButton: String { String(localized: "Continue") }
    /// Local Network access is off: the one-line reason, with the Settings button.
    public static var deniedLine: String { String(localized: "Local Network access is off.") }
    public static var settingsButton: String { String(localized: "Open Settings") }
    /// The scanner picker.
    public static var pickerTitle: String { String(localized: "Scanners") }
    public static var noScanner: String { String(localized: "No scanner found") }
    /// The Scanner row in printer mode before its scanner is picked or found.
    public static var noScannerPicked: String { String(localized: "No scanner") }
    public static var troubleshoot: String { String(localized: "Troubleshoot") }
    public static var addButton: String { String(localized: "Add by address") }
    /// The demo scanner's line in the picker, under its name.
    public static var demoLine: String { String(localized: "Try scanning without a scanner") }
    public static var removeAddress: String { String(localized: "Remove address") }
    public static var searching: String { String(localized: "Looking for scanners…") }
    /// Opens the scanner picked again after connecting to it failed.
    public static var retry: String { String(localized: "Try again") }
    /// Adding a scanner by address (the Windows dialog's wording).
    public static var addTitle: String { String(localized: "Add a network scanner") }
    public static var addLine: String { String(localized: "Enter the scanner's IP address or name.") }
    public static var addPlaceholder: String { String(localized: "e.g. 192.168.1.50 or scanner.local") }
    public static var addHelp: String { String(localized: "Most network scanners appear on their own. The address is on the scanner's screen or its network settings page. Forms: 192.168.1.50, scanner.local, 192.168.1.50:8080, https://192.168.1.50.") }
    public static var add: String { String(localized: "Add") }
    public static var networkOff: String { String(localized: "Network scanners are off in demo mode.") }
    /// A changed certificate (the Windows dialog's wording, shortened).
    public static var certificateTitle: String { String(localized: "Scanner certificate changed") }
    public static var certificateLine: String { String(localized: "Trust it only if you know why it changed.") }
    public static var trustedBefore: String { String(localized: "Trusted before") }
    public static var newFingerprint: String { String(localized: "New fingerprint") }
    public static var trustNew: String { String(localized: "Trust the new certificate") }
    public static var notTrusted: String { String(localized: "The scanner was not added, because its certificate was not trusted.") }

    /// "Connecting to 192.168.1.50…"
    public static func connecting(_ address: ScannerAddress) -> String {
        let host: String = "\(address)"
        return String(localized: "Connecting to \(host)\u{2026}")
    }
}

/// The iPhone's and iPad's network scanners: the eSCL connection (`EsclScannerBackend`) with its search
/// (`EsclDiscovery` over NWBrowser and dnssd), the addresses added by hand and the trusted certificates
/// (escl-hosts.json and escl-trust.json in Application Support's Lazy Scan/Network folder, which is
/// kept out of backups: pinned keys belong to this device), and what the screens need around it:
/// - the explanation card before the first search (`needsExplanation`, kept in the user's defaults once
///   read), so the system's Local Network prompt comes when the user expects it;
/// - searching only while the app is in front (UIApplication's background and foreground notifications);
/// - the question about a changed certificate (`certificateQuestion`), answered by the screens.
/// The app makes one only when launched without `-demoScanner`; tests make theirs with a search of stand-ins.
@MainActor
public final class IOSNetworkScanners: ObservableObject {
    /// The user's defaults key: the explanation card was read (Continue).
    public static let explainedKey = "localNetworkExplained"

    public let backend: EsclScannerBackend
    /// The explanation card has not been read yet: nothing is searched for or checked until it is.
    @Published public private(set) var needsExplanation: Bool
    /// A certificate that changed since it was trusted, waiting for the user's answer; nil otherwise.
    @Published public private(set) var certificateQuestion: EsclCertificateError?
    /// Bumped when the search's state changes, so the screens read `accessDenied` again.
    @Published public private(set) var revision: Int = 0

    private let defaults: UserDefaults
    private let center: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private var answer: CheckedContinuation<Bool, Never>?

    /// The app's: the files in Application Support, the system's search, UIKit's background time, the
    /// standard user defaults and notification center.
    public convenience init() {
        let folder: URL = IOSNetworkScanners.filesFolder()
        let discovery: EsclDiscovery = EsclDiscovery(makeBrowser: { (secure: Bool) -> any EsclServiceBrowsing in
            EsclNWBrowser(secure: secure)
        }, resolver: EsclDnssdResolver())
        let backend: EsclScannerBackend = EsclScannerBackend(trust: EsclTrustStore(directory: folder),
                                                             hosts: EsclHostList(directory: folder),
                                                             discovery: discovery,
                                                             background: UIKitBackgroundActivity())
        self.init(backend: backend, defaults: UserDefaults.standard, center: NotificationCenter.default)
    }

    /// Wraps `backend` (tests: with a search of stand-ins), with the explanation flag in `defaults` and the
    /// app's background and foreground notifications from `center`.
    public init(backend: EsclScannerBackend, defaults: UserDefaults, center: NotificationCenter) {
        self.backend = backend
        self.defaults = defaults
        self.center = center
        let explained: Bool = defaults.bool(forKey: IOSNetworkScanners.explainedKey)
        self.needsExplanation = !explained
        if !explained {
            backend.holdNetwork()
        }
        backend.confirmCertificate = { [weak self] (certificate: EsclCertificateError) async -> Bool in
            guard let self else { return false }
            return await self.ask(certificate)
        }
        backend.onDiscoveryChanged = { [weak self] in
            self?.revision += 1
        }
        observe(UIApplication.didEnterBackgroundNotification) { [weak self] in
            self?.backend.suspendBrowsing()
        }
        observe(UIApplication.willEnterForegroundNotification) { [weak self] in
            self?.backend.resumeBrowsing()
        }
    }

    /// Application Support/Lazy Scan/Network, created and kept out of backups.
    public static func filesFolder() -> URL {
        let base: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        var folder: URL = base.appendingPathComponent("Lazy Scan", isDirectory: true)
            .appendingPathComponent("Network", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var values: URLResourceValues = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        return folder
    }

    /// The user read the explanation card: the search starts (and with it the system's prompt).
    public func continueAfterExplanation() {
        defaults.set(true, forKey: IOSNetworkScanners.explainedKey)
        needsExplanation = false
        backend.allowNetwork()
    }

    /// Local Network access is off for the app, as far as the system has said.
    public var accessDenied: Bool {
        backend.discoveryStatus == .denied
    }

    /// A connection was refused for Local Network access (`IOSLocalNetworkProbe`).
    public func reportDenied() {
        backend.discovery?.reportDenied()
    }

    // MARK: A changed certificate

    /// Waits for the user's answer about `certificate` (`answerCertificate`); a question still open is
    /// answered no first.
    private func ask(_ certificate: EsclCertificateError) async -> Bool {
        if let open = answer {
            answer = nil
            open.resume(returning: false)
        }
        certificateQuestion = certificate
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            answer = continuation
        }
    }

    /// The user's answer about `certificateQuestion`: true trusts the new certificate.
    public func answerCertificate(_ trust: Bool) {
        certificateQuestion = nil
        guard let open = answer else { return }
        answer = nil
        open.resume(returning: trust)
    }

    private func observe(_ name: Notification.Name, _ handler: @escaping @MainActor () -> Void) {
        let observer: NSObjectProtocol = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                handler()
            }
        }
        observers.append(observer)
    }
}
#endif
