import Foundation

// "Why isn't my scanner listed?": what the app knows about finding scanners, gathered into one
// snapshot and turned into plain-language checks, each with the actions that help. The apps only
// read the system's state and link to the system's settings; they never change a service or a
// setting. Twin of windows/LazyScan.Core/Troubleshooter.cs (same checks, same text, same
// order). The Windows-only fields (the WIA service, TWAIN, addresses added by hand) are kept so
// both suites run the same fixtures; the Mac leaves them at their defaults.

/// Which app the snapshot comes from: the checks and their wording follow it.
public enum TroubleshootPlatform: String, Sendable {
    case windows
    case mac
    /// The iPhone and iPad app (never produced on Windows).
    case ios
}

/// The network the computer is on, as far as finding network scanners goes.
public enum NetworkStatus: String, Sendable {
    /// Not known (the Mac does not check).
    case unknown
    /// Not connected to any network.
    case offline
    /// Every connected network is public: Windows does not look for devices there.
    case publicNetwork
    case privateNetwork
    case domainNetwork
}

/// The state of a system service (on Windows, Windows Image Acquisition: stisvc).
public enum ServiceStatus: String, Sendable {
    /// Not known (not checked, or the system would not say).
    case unknown
    case running
    case starting
    case stopping
    case stopped
    case paused
    /// Stopped and set not to start.
    case disabled
    case notInstalled
}

/// Whether TWAIN can be used on the PC (Windows only).
public enum TwainStatus: String, Sendable {
    /// Not checked yet, or not a Windows snapshot.
    case unknown
    case available
    /// No TWAIN Data Source Manager (TWAINDSM.dll) is installed.
    case notInstalled
    /// The Data Source Manager is installed but would not open.
    case failed
}

/// The automatic search for scanners: on Windows the DNS-SD search for network (eSCL) scanners,
/// on the Mac ImageCaptureCore's device browser (USB, network and shared scanners).
public enum DiscoveryStatus: String, Sendable {
    /// Not known; no check is shown.
    case unknown
    /// Not running.
    case off
    /// Started; the first pass has not finished.
    case searching
    case running
    /// The system would not search.
    case unavailable
    /// The user turned off the app's access to the local network (iPhone and iPad: Local Network
    /// privacy). Windows never produces it.
    case denied
}

/// How a check came out. The order is not the display order (see `Troubleshooter.diagnose`).
public enum CheckStatus: String, CaseIterable, Sendable {
    case ok
    /// Advice that applies whatever the checks found.
    case tip
    case warning
    case problem
}

/// Something the troubleshooter offers to do; the app carries it out.
public enum TroubleshootAction: String, CaseIterable, Sendable {
    /// Look for scanners again.
    case refresh
    /// The "Add scanner by address" dialog (Windows only).
    case addByAddress
    /// Windows: Settings, Printers & scanners. Mac: System Settings, Printers & Scanners.
    case openScannerSettings
    /// Windows: Settings, Network & internet. Mac: System Settings, Network.
    case openNetworkSettings
    /// The Mac's Image Capture app, which shows every scanner macOS sees.
    case openImageCapture
    /// Copies the checks and the device diagnostics as text.
    case copyDiagnostics
    /// The app's own page in the Settings app (iPhone and iPad), where Local Network access is turned on.
    case openAppSettings
}

/// An address added by hand (Windows: escl-hosts.json) and whether a scanner answers there.
public struct ManualHostStatus: Equatable, Sendable {
    /// As the user would write it, e.g. "192.168.1.50" or "https://scanner.local".
    public var address: String
    /// A scanner answered and is listed.
    public var listed: Bool
    /// Why nothing is listed, in plain language; nil when listed or not checked yet.
    public var problem: String?
    /// `problem` in English, for the support report; the same text when it is not translated.
    public var reportProblem: String?

    public init(address: String, listed: Bool, problem: String? = nil, reportProblem: String? = nil) {
        self.address = address
        self.listed = listed
        self.problem = problem
        self.reportProblem = reportProblem ?? problem
    }
}

/// The last time connecting to a scanner, or scanning with it, failed.
public struct ScannerFailure: Equatable, Sendable {
    /// The scanner's name as listed.
    public var deviceName: String
    /// The error the user was shown.
    public var message: String
    /// The condition at the scanner behind it, when the connection could tell.
    public var problem: ScannerProblem?
    /// `message` in English, for the support report; the same text when it is not translated.
    public var reportMessage: String

    public init(deviceName: String, message: String, problem: ScannerProblem? = nil, reportMessage: String? = nil) {
        self.deviceName = deviceName
        self.message = message
        self.problem = problem
        self.reportMessage = reportMessage ?? message
    }
}

/// Everything the troubleshooter looks at, read at one moment. The app fills in the system's
/// state and the scanners listed; each connection that conforms to `ScannerBackendDiagnostics`
/// adds what it knows. Fields left at their defaults (unknown, empty) produce no check.
public struct DiscoverySnapshot: Equatable, Sendable {
    public var platform: TroubleshootPlatform
    /// The scanners listed, one per row, the demo scanner included.
    public var devices: [ScannerInfo]
    public var network: NetworkStatus
    /// Windows Image Acquisition (stisvc); Windows only.
    public var wiaService: ServiceStatus
    public var twain: TwainStatus
    /// The TWAIN drivers (data sources) the 64-bit Windows app can use.
    public var twainDriverCount: Int
    /// TWAIN driver files installed only for 32-bit apps (paths or file names).
    public var thirtyTwoBitOnlyDrivers: [String]
    /// Why the 32-bit TWAIN helper (Windows) does not reach `thirtyTwoBitOnlyDrivers`, as
    /// sentences about the helper ("It …") with what to do; nil when not known. Never set on the Mac.
    public var thirtyTwoBitHelperProblem: String?
    /// `thirtyTwoBitHelperProblem` in English, for the support report; the same text when it is not translated.
    public var thirtyTwoBitHelperReportProblem: String?
    public var discovery: DiscoveryStatus
    /// Why the search is unavailable, as the system put it; nil otherwise.
    public var discoveryDetail: String?
    /// Network scanners the automatic search found (Windows); unused on the Mac.
    public var discoveredCount: Int
    public var manualHosts: [ManualHostStatus]
    public var lastFailure: ScannerFailure?

    public init(platform: TroubleshootPlatform = .windows, devices: [ScannerInfo] = [],
                network: NetworkStatus = .unknown, wiaService: ServiceStatus = .unknown,
                twain: TwainStatus = .unknown, twainDriverCount: Int = 0,
                thirtyTwoBitOnlyDrivers: [String] = [], thirtyTwoBitHelperProblem: String? = nil,
                thirtyTwoBitHelperReportProblem: String? = nil, discovery: DiscoveryStatus = .unknown,
                discoveryDetail: String? = nil, discoveredCount: Int = 0,
                manualHosts: [ManualHostStatus] = [], lastFailure: ScannerFailure? = nil) {
        self.platform = platform
        self.devices = devices
        self.network = network
        self.wiaService = wiaService
        self.twain = twain
        self.twainDriverCount = twainDriverCount
        self.thirtyTwoBitOnlyDrivers = thirtyTwoBitOnlyDrivers
        self.thirtyTwoBitHelperProblem = thirtyTwoBitHelperProblem
        self.thirtyTwoBitHelperReportProblem = thirtyTwoBitHelperReportProblem
        self.discovery = discovery
        self.discoveryDetail = discoveryDetail
        self.discoveredCount = discoveredCount
        self.manualHosts = manualHosts
        self.lastFailure = lastFailure
    }

    /// The scanners listed other than the demo scanner.
    public var listedScannerCount: Int { devices.filter { !$0.isDemo }.count }

    /// The snapshot with the texts the backends worded in the UI language replaced by their English twins.
    var forReport: DiscoverySnapshot {
        var english = self
        english.thirtyTwoBitHelperProblem = thirtyTwoBitHelperReportProblem ?? thirtyTwoBitHelperProblem
        english.manualHosts = manualHosts.map { host in
            var copy = host
            copy.problem = host.reportProblem
            return copy
        }
        if let failure = lastFailure { english.lastFailure?.message = failure.reportMessage }
        return english
    }
}

/// One line of the troubleshooter: what was checked, how it came out, what to do.
public struct TroubleshootCheck: Equatable, Sendable {
    /// Stable identifier ("network", "wiaService", "manualHost:192.168.1.50", ...).
    public let id: String
    public let status: CheckStatus
    /// Six words at most.
    public let title: String
    /// What it means or what to do, in one line of fifteen words at most.
    public let detail: String
    /// The rest of the explanation, behind "More help"; empty when the detail says it all.
    public let more: String
    /// Buttons offered with it, in order.
    public let actions: [TroubleshootAction]

    public init(id: String, status: CheckStatus, title: String, detail: String, more: String = "",
                actions: [TroubleshootAction]) {
        self.id = id
        self.status = status
        self.title = title
        self.detail = detail
        self.more = more
        self.actions = actions
    }

    /// The detail and the more help as one text, for VoiceOver and the copied diagnostics.
    public var fullDetail: String {
        more.isEmpty ? detail : detail + " " + more
    }
}

/// A connection that can tell the troubleshooter about itself. Optional, so `ScannerBackend`
/// does not change. Twin of C# `IScannerBackendDiagnostics` (`AddStatus`, `Rescan`), with the C#
/// `IBackendDiagnostics.DiagnosticsReport` (devices.txt) as `diagnosticsReport`.
@MainActor
public protocol ScannerBackendDiagnostics: AnyObject {
    /// The snapshot with what this connection knows filled in.
    func addStatus(to snapshot: DiscoverySnapshot) -> DiscoverySnapshot
    /// Look for scanners again now (the troubleshooter's Refresh). Never changes system settings.
    func rescan()
    /// What this connection found, as lines for devices.txt and Copy diagnostics; nil when it has
    /// nothing to add (the default).
    var diagnosticsReport: String? { get }
}

extension ScannerBackendDiagnostics {
    public var diagnosticsReport: String? { nil }
}

public enum Troubleshooter {

    /// The checks for `snapshot`: problems first, then warnings, then what is fine, then the tips
    /// that always apply; within each, in this order: the last failure, the network, the WIA
    /// service, TWAIN, 32-bit TWAIN drivers, the automatic search (or the local network access it
    /// was refused), the addresses added by hand, then the tips. The iPhone and iPad get their own
    /// wording and tips, never the Windows or Mac checks.
    public static func diagnose(_ snapshot: DiscoverySnapshot) -> [TroubleshootCheck] {
        let windows = snapshot.platform == .windows
        // The phone adds network scanners by address too (Mac: ImageCaptureCore finds them).
        let addsByAddress: Bool = windows || snapshot.platform == .ios
        var checks: [TroubleshootCheck] = []

        if let failure = snapshot.lastFailure { checks.append(failureCheck(failure, platform: snapshot.platform)) }
        if let network = networkCheck(snapshot) { checks.append(network) }
        if windows, let wia = wiaServiceCheck(snapshot.wiaService) { checks.append(wia) }
        if windows, let twain = twainCheck(snapshot) { checks.append(twain) }
        if windows, !snapshot.thirtyTwoBitOnlyDrivers.isEmpty {
            checks.append(thirtyTwoBitCheck(snapshot.thirtyTwoBitOnlyDrivers, helperProblem: snapshot.thirtyTwoBitHelperProblem))
        }
        if let discovery = discoveryCheck(snapshot) { checks.append(discovery) }
        if addsByAddress {
            for host in snapshot.manualHosts where !host.listed {
                checks.append(TroubleshootCheck(
                    id: "manualHost:\(host.address)", status: .warning,
                    title: L10n.t("No scanner answers at {0}", host.address),
                    detail: L10n.t("Check that it is on and its address hasn't changed."),
                    more: joinSentences(host.problem, L10n.t("Its network settings page or control panel shows the current address. The app tries the address again every minute.")),
                    actions: [.refresh]))
            }
        }
        checks.append(contentsOf: tips(snapshot.platform))

        // A stable sort: problems, warnings, what is fine, tips.
        return checks.enumerated()
            .sorted { lhs, rhs in
                let left = rank(lhs.element.status)
                let right = rank(rhs.element.status)
                return left != right ? left < right : lhs.offset < rhs.offset
            }
            .map { $0.element }
    }

    /// "No scanner found", "1 scanner found", "3 scanners found" (the demo scanner does not count).
    public static func headline(_ snapshot: DiscoverySnapshot) -> String {
        let count = snapshot.listedScannerCount
        if count == 0 { return L10n.t("No scanner found") }
        return L10n.plural(count, one: "{0} scanner found", other: "{0} scanners found")
    }

    /// "2 problems and 1 warning found.", or that nothing stops scanners from appearing.
    public static func summary(_ checks: [TroubleshootCheck]) -> String {
        let problems = checks.filter { $0.status == .problem }.count
        let warnings = checks.filter { $0.status == .warning }.count
        if problems == 0 && warnings == 0 {
            return L10n.t("Nothing here stops scanners from appearing. The tips below cover the usual causes.")
        }
        let problemText = L10n.plural(problems, one: "{0} problem", other: "{0} problems")
        let warningText = L10n.plural(warnings, one: "{0} warning", other: "{0} warnings")
        if problems > 0 && warnings > 0 { return L10n.t("{0} and {1} found.", problemText, warningText) }
        return L10n.t("{0} found.", problems > 0 ? problemText : warningText)
    }

    /// The troubleshooter's one-line headline: what is listed, then how many problems and warnings
    /// there are ("No scanner found · 2 problems, 1 warning"); just what is listed when there are none.
    public static func overview(_ snapshot: DiscoverySnapshot, checks: [TroubleshootCheck]) -> String {
        let problems: Int = checks.filter { $0.status == .problem }.count
        let warnings: Int = checks.filter { $0.status == .warning }.count
        var parts: [String] = []
        if problems > 0 { parts.append(L10n.plural(problems, one: "{0} problem", other: "{0} problems")) }
        if warnings > 0 { parts.append(L10n.plural(warnings, one: "{0} warning", other: "{0} warnings")) }
        let line: String = headline(snapshot)
        if parts.isEmpty { return line }
        return line + " \u{00B7} " + (parts.count == 2 ? L10n.t("{0}, {1}", parts[0], parts[1]) : parts[0])
    }

    /// The button text for an action.
    public static func label(_ action: TroubleshootAction, platform: TroubleshootPlatform) -> String {
        switch action {
        case .refresh: return L10n.t("Refresh")
        case .addByAddress: return L10n.t("Add by address…")
        case .openScannerSettings:
            return platform == .windows ? L10n.t("Scanner settings") : L10n.t("Printers & Scanners")
        case .openNetworkSettings: return L10n.t("Network settings")
        case .openImageCapture: return L10n.t("Image Capture")
        case .copyDiagnostics: return L10n.t("Copy diagnostics")
        case .openAppSettings: return L10n.t("Open Settings")
        }
    }

    /// The status as a word, for screen readers and the copied text: "OK", "Tip", "Warning", "Problem".
    public static func statusLabel(_ status: CheckStatus) -> String {
        switch status {
        case .ok: return L10n.t("OK")
        case .tip: return L10n.t("Tip")
        case .warning: return L10n.t("Warning")
        case .problem: return L10n.t("Problem")
        }
    }

    /// The checks as plain text, for the pasteboard and the device diagnostics file: the heading,
    /// the headline and summary, then one "Status: title" line per check with its detail
    /// indented below, and its more help (when it has some) on the line after. Always English: it
    /// is pasted into support requests. The texts the backends stored in the snapshot come in their
    /// English twins (`DiscoverySnapshot.forReport`). Error text the system words itself (a URLError's
    /// description) stays as the system gave it.
    public static func report(_ snapshot: DiscoverySnapshot) -> String {
        L10n.english {
            let checks = diagnose(snapshot.forReport)
            var text = "Why isn't my scanner listed?\n"
            text += headline(snapshot) + ". " + summary(checks) + "\n"
            for check in checks {
                text += statusLabel(check.status) + ": " + check.title + "\n"
                text += "  " + check.detail + "\n"
                if !check.more.isEmpty { text += "  " + check.more + "\n" }
            }
            return text
        }
    }

    /// The network status of a computer connected to these networks: none is offline; a public
    /// network among them wins, since a VPN or other private adapter says nothing about the
    /// Wi-Fi the scanner is on.
    public static func combineNetworks(_ connected: [NetworkStatus]) -> NetworkStatus {
        let all = connected.filter { $0 != .unknown && $0 != .offline }
        if all.isEmpty { return connected.contains(.unknown) ? .unknown : .offline }
        if all.contains(.publicNetwork) { return .publicNetwork }
        if all.contains(.domainNetwork) { return .domainNetwork }
        return .privateNetwork
    }

    /// What a failed connection or scan tells the troubleshooter; nil for errors that say nothing
    /// about reaching the scanner (cancelled, saving, unsupported settings). Twin of C# `FailureFrom`.
    public static func failure(deviceName: String, error: Error) -> ScannerFailure? {
        if error is CancellationError { return nil }
        if let scanError = error as? ScanError {
            switch scanError {
            case .cancelled, .exportFailed, .unsupported:
                return nil
            case .deviceUnavailable, .sessionFailed, .scanFailed, .scannerProblem:
                return ScannerFailure(deviceName: deviceName,
                                      message: scanError.errorDescription ?? error.localizedDescription,
                                      problem: scanError.problem, reportMessage: scanError.reportDescription)
            }
        }
        if let certificate = error as? EsclCertificateError {
            return ScannerFailure(deviceName: deviceName, message: certificate.message,
                                  reportMessage: L10n.english { certificate.message })
        }
        return ScannerFailure(deviceName: deviceName, message: error.localizedDescription)
    }

    // MARK: - The checks

    private static func rank(_ status: CheckStatus) -> Int {
        switch status {
        case .problem: return 0
        case .warning: return 1
        case .ok: return 2
        case .tip: return 3
        }
    }

    /// The system that searches the network, in the discovery check's more help.
    private static func searchingSystem(_ platform: TroubleshootPlatform) -> String {
        platform == .ios ? "iOS" : "Windows"
    }

    private static func failureCheck(_ failure: ScannerFailure, platform: TroubleshootPlatform) -> TroubleshootCheck {
        let name = failure.deviceName
        if failure.problem == .busy {
            let more: String
            switch platform {
            case .windows: more = L10n.t("A scanner works with one app at a time; Windows Scan or the maker's app may be using it. Wait until the scanner has finished, then choose it again.")
            case .ios: more = L10n.t("A scanner works with one app at a time; another device or app may be using it. Wait until the scanner has finished, then choose it again.")
            case .mac: more = L10n.t("A scanner works with one app at a time; Image Capture or the maker's app may be using it. Wait until the scanner has finished, then choose it again.")
            }
            return TroubleshootCheck(
                id: "lastFailure", status: .problem, title: L10n.t("{0} is busy", name),
                detail: L10n.t("Close other apps using it, then choose it again."),
                more: more, actions: [.refresh])
        }
        if let problem = failure.problem {
            return TroubleshootCheck(
                id: "lastFailure", status: .problem, title: L10n.t("{0}: {1}", ScannerProblems.title(problem), name),
                detail: ScannerProblems.advice(problem), actions: [.refresh])
        }
        return TroubleshootCheck(
            id: "lastFailure", status: .warning, title: L10n.t("Could not connect to {0}", name),
            detail: L10n.t("Check that it is on, awake and connected."),
            more: joinSentences(failure.message, platform == .ios
                                    ? L10n.t("It must be on the same network as this device.")
                                    : platform == .windows
                                    ? L10n.t("It must be connected by its cable or to the same network as this PC.")
                                    : L10n.t("It must be connected by its cable or to the same network as this Mac.")),
            actions: [.refresh])
    }

    private static func networkCheck(_ snapshot: DiscoverySnapshot) -> TroubleshootCheck? {
        if snapshot.platform == .ios { return phoneNetworkCheck(snapshot.network) }
        let windows = snapshot.platform == .windows
        switch snapshot.network {
        case .offline:
            return TroubleshootCheck(
                id: "network", status: .problem, title: L10n.t("Not connected to a network"),
                detail: L10n.t("Connect to the network the scanner is on, then select Refresh."),
                more: windows
                    ? L10n.t("This PC is not on a network, so network scanners can't be found. Scanners connected by USB are not affected.")
                    : L10n.t("This Mac is not on a network, so network scanners can't be found. Scanners connected by USB are not affected."),
                actions: [.openNetworkSettings, .refresh])
        case .publicNetwork:
            let more = windows
                ? L10n.t("If this is your home or office network, set it to Private in network settings. You can also add the scanner by its address.")
                : L10n.t("If this is your home or office network, set it to Private in network settings.")
            return TroubleshootCheck(
                id: "network", status: .warning, title: L10n.t("Network set to Public"),
                detail: L10n.t("Windows won't find network scanners on a Public network."),
                more: more,
                actions: windows ? [.openNetworkSettings, .addByAddress] : [.openNetworkSettings])
        case .privateNetwork, .domainNetwork:
            return TroubleshootCheck(
                id: "network", status: .ok, title: L10n.t("Connected to a private network"),
                detail: L10n.t("Network scanners on this network can be found."), actions: [])
        case .unknown:
            return nil
        }
    }

    /// The iPhone's and iPad's network: Wi-Fi or a wired network, or none (cellular only counts as
    /// none, since scanners are not found there). iOS has no public or private networks.
    private static func phoneNetworkCheck(_ network: NetworkStatus) -> TroubleshootCheck? {
        switch network {
        case .offline:
            return TroubleshootCheck(
                id: "network", status: .problem, title: L10n.t("Not connected to Wi-Fi"),
                detail: L10n.t("Join the scanner's Wi-Fi network, then tap Refresh."),
                more: L10n.t("Network scanners are found only on Wi-Fi or a wired network. The camera works without one."),
                actions: [.refresh])
        case .publicNetwork, .privateNetwork, .domainNetwork:
            return TroubleshootCheck(
                id: "network", status: .ok, title: L10n.t("Connected to a local network"),
                detail: L10n.t("Network scanners on this network can be found."), actions: [])
        case .unknown:
            return nil
        }
    }

    /// The app may not use the local network (iPhone and iPad: Local Network privacy turned off for
    /// it), so it can neither find scanners nor reach the addresses added by hand. The same check on
    /// every platform, though only the iPhone and iPad report it.
    private static func localNetworkDeniedCheck() -> TroubleshootCheck {
        TroubleshootCheck(
            id: "localNetwork", status: .problem, title: L10n.t("Local Network access is off"),
            detail: L10n.t("Turn on Local Network for Lazy Scan in Settings."),
            more: L10n.t("Without it, the app can't find or reach scanners on your network. Scanners appear as soon as it's on. If it's on already, turn it off and on again."),
            actions: [.openAppSettings])
    }

    private static func wiaServiceCheck(_ status: ServiceStatus) -> TroubleshootCheck? {
        switch status {
        case .running:
            return TroubleshootCheck(
                id: "wiaService", status: .ok, title: L10n.t("Scanner service is on"),
                detail: L10n.t("Windows Image Acquisition (WIA), which most scanners use, is on."), actions: [])
        case .starting:
            return TroubleshootCheck(
                id: "wiaService", status: .warning, title: L10n.t("Scanner service is starting"),
                detail: L10n.t("Wait a moment, then select Refresh."),
                more: L10n.t("Windows Image Acquisition (WIA), which most scanners use, is starting."),
                actions: [.refresh])
        case .stopped, .stopping, .paused:
            return TroubleshootCheck(
                id: "wiaService", status: .warning, title: L10n.t("Scanner service is not running"),
                detail: L10n.t("Restarting the PC usually starts it again."),
                more: L10n.t("Windows Image Acquisition (WIA), which most scanners use, is not running, so those scanners can't appear. To start it now, someone with administrator rights can start Windows Image Acquisition (WIA) in Services."),
                actions: [.refresh])
        case .disabled:
            return TroubleshootCheck(
                id: "wiaService", status: .problem, title: L10n.t("Scanner service is turned off"),
                detail: L10n.t("An administrator can set it to Automatic in Services."),
                more: L10n.t("Windows Image Acquisition (WIA), which most scanners use, is disabled, so those scanners can't appear. Someone with administrator rights can set its startup type to Automatic in Services, then restart the PC."),
                actions: [.refresh])
        case .notInstalled:
            return TroubleshootCheck(
                id: "wiaService", status: .problem, title: L10n.t("Scanner service is missing"),
                detail: L10n.t("Scanners with a TWAIN driver and network scanners can still work."),
                more: L10n.t("This copy of Windows has no Windows Image Acquisition (WIA) service, which most scanners use."),
                actions: [.addByAddress])
        case .unknown:
            return nil
        }
    }

    private static func twainCheck(_ snapshot: DiscoverySnapshot) -> TroubleshootCheck? {
        switch snapshot.twain {
        case .available:
            let detail: String
            let count = snapshot.twainDriverCount
            if count == 0 {
                detail = L10n.t("No 64-bit TWAIN scanner driver is installed. Most scanners work without one.")
            } else {
                detail = L10n.plural(count, one: "{0} TWAIN scanner driver is installed.", other: "{0} TWAIN scanner drivers are installed.")
            }
            return TroubleshootCheck(id: "twain", status: .ok, title: L10n.t("TWAIN is installed"), detail: detail, actions: [])
        case .notInstalled:
            return TroubleshootCheck(
                id: "twain", status: snapshot.listedScannerCount == 0 ? .warning : .tip, title: L10n.t("TWAIN is not installed"),
                detail: L10n.t("Some scanners need their maker's 64-bit TWAIN driver."),
                more: L10n.t("Some scanners, often document scanners, work only through their maker's TWAIN driver, which also installs TWAIN. If yours is one of them, install the maker's 64-bit TWAIN driver, then restart Lazy Scan."),
                actions: [])
        case .failed:
            return TroubleshootCheck(
                id: "twain", status: .warning, title: L10n.t("TWAIN did not start"),
                detail: L10n.t("Restart Lazy Scan; if that fails, reinstall the maker's TWAIN driver."),
                more: L10n.t("TWAIN is installed but would not open, so scanners that use a TWAIN driver are not listed."),
                actions: [.refresh])
        case .unknown:
            return nil
        }
    }

    /// Drivers the 32-bit helper does not reach, with why when the app knows (`helperProblem`).
    private static func thirtyTwoBitCheck(_ drivers: [String], helperProblem: String?) -> TroubleshootCheck {
        let names = drivers.map { path -> String in
            let name: String
            if let separator = path.lastIndex(where: { $0 == "/" || $0 == "\\" }) {
                name = String(path[path.index(after: separator)...])
            } else {
                name = path
            }
            return name
        }
        let problem = (helperProblem ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let known = !problem.isEmpty
        let reach: String
        if known {
            reach = L10n.t("Lazy Scan reaches such drivers through its 32-bit TWAIN helper.")
        } else {
            reach = L10n.plural(names.count, one: "Lazy Scan reaches such drivers through its 32-bit TWAIN helper, which has not listed it yet.",
                                other: "Lazy Scan reaches such drivers through its 32-bit TWAIN helper, which has not listed them yet.")
        }
        let installed: String = L10n.plural(names.count, one: "“{1}” is installed only for 32-bit apps.",
                                            other: "“{1}” are installed only for 32-bit apps.", names.joined(separator: ", "))
        return TroubleshootCheck(
            id: "twain32", status: .problem,
            title: L10n.plural(names.count, one: "A TWAIN driver is 32-bit only", other: "{0} TWAIN drivers are 32-bit only"),
            detail: installed,
            more: joinSentences(known ? joinSentences(reach, problem) : reach,
                                L10n.t("A 64-bit (x64) driver from the maker, where there is one, works without the helper. Many scanners also work through Windows Image Acquisition (WIA) once the maker's full driver package is installed.")),
            actions: [])
    }

    private static func discoveryCheck(_ snapshot: DiscoverySnapshot) -> TroubleshootCheck? {
        if snapshot.discovery == .denied { return localNetworkDeniedCheck() }
        var reason = (snapshot.discoveryDetail ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        while reason.hasSuffix(".") { reason.removeLast() }
        if snapshot.platform == .mac {
            switch snapshot.discovery {
            case .searching, .running:
                return TroubleshootCheck(
                    id: "discovery", status: .ok, title: L10n.t("Looking for scanners"),
                    detail: L10n.t("Scanners appear here as macOS finds them."),
                    more: L10n.t("macOS looks for scanners connected by USB, on the network and shared by other Macs."),
                    actions: [])
            case .off, .unavailable:
                return TroubleshootCheck(
                    id: "discovery", status: .warning, title: L10n.t("Not looking for scanners"),
                    detail: L10n.t("Select Refresh to start the search again."),
                    more: reason.isEmpty ? L10n.t("The search for scanners is not running.")
                                         : L10n.t("The search for scanners is not running ({0}).", reason),
                    actions: [.refresh])
            case .unknown, .denied:
                return nil
            }
        }
        switch snapshot.discovery {
        case .searching:
            return TroubleshootCheck(
                id: "discovery", status: .ok, title: L10n.t("Looking for network scanners"),
                detail: L10n.t("Scanners on the network appear as they answer."),
                more: L10n.t("The search has just started."),
                actions: [.addByAddress])
        case .running:
            let found: String
            let count = snapshot.discoveredCount
            if count == 0 {
                found = L10n.t("No network scanner has been found on this network yet.")
            } else {
                found = L10n.plural(count, one: "{0} network scanner found.", other: "{0} network scanners found.")
            }
            return TroubleshootCheck(
                id: "discovery", status: .ok, title: L10n.t("Looking for network scanners"),
                detail: found,
                more: L10n.t("A scanner that doesn't appear can be added by its address."),
                actions: [.addByAddress])
        case .unavailable:
            return TroubleshootCheck(
                id: "discovery", status: .warning, title: L10n.t("Network search is not working"),
                detail: L10n.t("You can still add a network scanner by its address."),
                more: reason.isEmpty ? L10n.t("{0} could not search the network for scanners.", searchingSystem(snapshot.platform))
                                     : L10n.t("{0} could not search the network for scanners ({1}).", searchingSystem(snapshot.platform), reason),
                actions: [.addByAddress, .refresh])
        case .off, .unknown, .denied:
            return nil
        }
    }

    private static func tips(_ platform: TroubleshootPlatform) -> [TroubleshootCheck] {
        if platform == .ios {
            return phoneTips()
        }
        var tips: [TroubleshootCheck] = []
        if platform == .windows {
            tips.append(TroubleshootCheck(
                id: "usb", status: .tip, title: L10n.t("Connected by USB?"),
                detail: L10n.t("Connect it directly (no hub) and install the maker's driver."),
                more: L10n.t("Windows lists a USB scanner only after its driver is installed. Get it from the maker's website, then select Refresh. Scanner settings show whether Windows sees it."),
                actions: [.openScannerSettings, .refresh]))
        } else {
            tips.append(TroubleshootCheck(
                id: "usb", status: .tip, title: L10n.t("Connected by USB?"),
                detail: L10n.t("Connect it directly (no hub) and install the maker's macOS driver."),
                more: L10n.t("macOS lists a USB scanner only when it can scan without a driver or its maker's driver is installed. If Image Capture doesn't show it either, macOS doesn't see it."),
                actions: [.openImageCapture, .refresh]))
            tips.append(TroubleshootCheck(
                id: "networkScanner", status: .tip, title: L10n.t("Scanner on the network?"),
                detail: L10n.t("The Mac and the scanner must be on the same network."),
                more: L10n.t("If macOS asked whether Lazy Scan may find devices on your local network, allow it in System Settings, Privacy & Security, Local Network. A network printer with a scanner added in Printers & Scanners also appears here."),
                actions: [.openScannerSettings]))
            tips.append(TroubleshootCheck(
                id: "sharing", status: .tip, title: L10n.t("Shared by another Mac?"),
                detail: L10n.t("Turn on Scanner Sharing in that Mac's Sharing settings."),
                more: L10n.t("It's in System Settings, General, Sharing. Both Macs must be on the same network."),
                actions: []))
        }
        tips.append(TroubleshootCheck(
            id: "otherApps", status: .tip, title: L10n.t("Still not listed?"),
            detail: L10n.t("Wake the scanner and close other scanning apps."),
            more: platform == .windows
                ? L10n.t("Press a button on the scanner. Close Windows Scan or the maker's app. Some scanners work only with their maker's app.")
                : L10n.t("Press a button on the scanner. Close Image Capture or the maker's app. Some scanners work only with their maker's app."),
            actions: [.refresh]))
        return tips
    }

    /// The iPhone's and iPad's tips: network scanners only (they can't use USB scanners), with the
    /// address as the way round a network that hides them.
    private static func phoneTips() -> [TroubleshootCheck] {
        var tips: [TroubleshootCheck] = []
        tips.append(TroubleshootCheck(
            id: "networkScanner", status: .tip, title: L10n.t("Scanner on the network?"),
            detail: L10n.t("This device and the scanner must be on the same Wi-Fi."),
            more: L10n.t("Guest networks and some VPNs hide scanners. Try adding the scanner by its address."),
            actions: [.addByAddress]))
        tips.append(TroubleshootCheck(
            id: "usb", status: .tip, title: L10n.t("Connected by USB?"),
            detail: L10n.t("Use its Wi-Fi connection; iPhone and iPad can't use USB scanners."),
            more: L10n.t("Most scanners that print or copy also join Wi-Fi. The scanner's manual shows how."),
            actions: []))
        tips.append(TroubleshootCheck(
            id: "otherApps", status: .tip, title: L10n.t("Still not listed?"),
            detail: L10n.t("Wake the scanner and close other scanning apps."),
            more: L10n.t("Press a button on the scanner. Close scanning apps on other devices. Some scanners work only with Windows (WSD) or their maker's app."),
            actions: [.refresh]))
        return tips
    }

    /// The first text as a sentence, then the second; the first may be missing.
    private static func joinSentences(_ first: String?, _ second: String) -> String {
        var head = (first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if head.isEmpty { return second }
        if let last = head.last, !".!?".contains(last) { head += "." }
        return head + " " + second
    }
}
