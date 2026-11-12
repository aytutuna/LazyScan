import Foundation

// Twin of windows/LazyScan.Core/Companion/CompanionTroubleshooter.cs ("Why can't my phone
// connect?"): the same checks, order and Windows text in the troubleshooter's form (TroubleshootCheck).
// As in Troubleshooter.swift, the snapshot says which app it comes from and the Mac's text names the Mac;
// the Windows Firewall fields are kept so both suites run the same cases, and the Mac leaves them at
// their defaults (no check).

/// Whether the desktop receives from phones, or why not (C#: in CompanionHost.cs).
public enum CompanionListenState: String, Equatable, Sendable {
    /// No phone is paired and no pairing code is shown: nothing listens.
    case off
    /// Not connected to any network.
    case offline
    /// Connected, but to no network the desktop receives on.
    case noTrustedNetwork
    case listening
    /// Listening failed (see `CompanionSnapshot.listenError`).
    case failed
    /// Another instance of the app receives (set by the app, never by the host).
    case elsewhere
}

/// What Windows Firewall does with the app's connections (Windows only; C#: CompanionFirewall.cs).
public enum CompanionFirewallVerdict: String, Equatable, Sendable {
    /// The rules could not be read, or not a Windows snapshot.
    case unknown
    /// The firewall is off for the current network's profile.
    case off
    /// A rule lets the app receive on the current profile.
    case allowed
    /// A rule blocks the app on the current profile (often from a cancelled firewall prompt).
    case blocked
    /// No rule for the app yet: Windows asks the first time the app listens.
    case willAsk
}

/// A connected network and whether the desktop receives on it.
public struct CompanionNetworkState: Equatable {
    public var network: CompanionNetwork
    public var trust: NetworkTrust

    public init(network: CompanionNetwork, trust: NetworkTrust) {
        self.network = network
        self.trust = trust
    }
}

/// Everything the phone checks look at, read at one moment.
public struct CompanionSnapshot: Equatable {
    public var platform: TroubleshootPlatform
    public var networks: [CompanionNetworkState]
    public var listen: CompanionListenState
    /// The port listened on; 0 when not listening.
    public var port: Int
    /// Why listening failed, as the system put it; nil otherwise.
    public var listenError: String?
    public var firewall: CompanionFirewallVerdict
    /// The names of the firewall rules that block the app.
    public var blockingRules: [String]
    /// The Mac refused to advertise because Local Network access is off for the app (Mac only).
    public var localNetworkDenied: Bool
    public var pairedCount: Int
    public var pairingOpen: Bool
    /// A cloud sync folder is chosen (C2).
    public var syncFolderChosen: Bool
    /// How long since a paired phone last reached this desktop; nil when none is paired.
    public var phonesQuietFor: TimeInterval?

    public init(platform: TroubleshootPlatform = .windows, networks: [CompanionNetworkState] = [],
                listen: CompanionListenState = .off, port: Int = 0, listenError: String? = nil,
                firewall: CompanionFirewallVerdict = .unknown, blockingRules: [String] = [],
                localNetworkDenied: Bool = false, pairedCount: Int = 0, pairingOpen: Bool = false,
                syncFolderChosen: Bool = false, phonesQuietFor: TimeInterval? = nil) {
        self.platform = platform
        self.networks = networks
        self.listen = listen
        self.port = port
        self.listenError = listenError
        self.firewall = firewall
        self.blockingRules = blockingRules
        self.localNetworkDenied = localNetworkDenied
        self.pairedCount = pairedCount
        self.pairingOpen = pairingOpen
        self.syncFolderChosen = syncFolderChosen
        self.phonesQuietFor = phonesQuietFor
    }
}

public enum CompanionTroubleshooter {
    /// How long no paired phone may go unseen before the cloud folder is suggested.
    public static let quietTime: TimeInterval = 3 * 24 * 60 * 60

    /// The checks: problems first, then warnings, then what is fine, then tips (each group in this order).
    public static func diagnose(_ snapshot: CompanionSnapshot) -> [TroubleshootCheck] {
        let pc = snapshot.platform == .windows
        var checks: [TroubleshootCheck] = []
        if let listen = listenCheck(snapshot, pc: pc) { checks.append(listen) }
        for state in snapshot.networks {
            checks.append(networkCheck(state, platform: snapshot.platform, pc: pc))
        }
        if let firewall = firewallCheck(snapshot) { checks.append(firewall) }
        if snapshot.localNetworkDenied { checks.append(localNetworkCheck()) }
        if let syncFolder = syncFolderCheck(snapshot, pc: pc) { checks.append(syncFolder) }
        checks.append(TroubleshootCheck(
            id: "phoneIsolation", status: .tip, title: L10n.t("Phone cannot connect on the same Wi-Fi?"),
            detail: pc ? L10n.t("Some networks, often at schools, hotels and on guest Wi-Fi, keep devices from reaching each other even on the same Wi-Fi. The phone's connection check then says so. Connect this PC to your phone's hotspot instead, or send the document from the phone's share sheet.") : L10n.t("Some networks, often at schools, hotels and on guest Wi-Fi, keep devices from reaching each other even on the same Wi-Fi. The phone's connection check then says so. Connect this Mac to your phone's hotspot instead, or send the document from the phone's share sheet."),
            actions: []))
        var ranked: [(check: TroubleshootCheck, index: Int)] = []
        for (index, check) in checks.enumerated() {
            ranked.append((check, index))
        }
        ranked.sort { (rank($0.check.status), $0.index) < (rank($1.check.status), $1.index) }
        var ordered: [TroubleshootCheck] = []
        for pair in ranked {
            ordered.append(pair.check)
        }
        return ordered
    }

    /// "Receiving from phones (Home Wi-Fi).", or why not.
    public static func headline(_ snapshot: CompanionSnapshot) -> String {
        var trusted: [String] = []
        var untrusted: [String] = []
        for state in snapshot.networks {
            if state.trust == .notTrusted {
                untrusted.append(state.network.name)
            } else {
                trusted.append(state.network.name)
            }
        }
        switch snapshot.listen {
        case .listening:
            if snapshot.localNetworkDenied { return L10n.t("Phones cannot find this Mac: Local Network access is off.") }
            return L10n.t("Receiving from phones ({0}).", joinNames(trusted))
        case .off: return L10n.t("No phone is paired yet.")
        case .offline: return L10n.t("Not connected to a network.")
        case .noTrustedNetwork: return L10n.t("Not receiving from phones ({0}).", joinNames(untrusted))
        case .failed: return L10n.t("Could not start receiving from phones.")
        case .elsewhere: return L10n.t("Another Lazy Scan window receives from phones.")
        }
    }

    /// "2 problems and 1 warning found.", or that nothing stops phones from connecting.
    public static func summary(_ checks: [TroubleshootCheck]) -> String {
        let problems = checks.filter { $0.status == .problem }.count
        let warnings = checks.filter { $0.status == .warning }.count
        if problems == 0 && warnings == 0 { return L10n.t("Nothing here stops a paired phone from connecting.") }
        let problemText = L10n.plural(problems, one: "{0} problem", other: "{0} problems")
        let warningText = L10n.plural(warnings, one: "{0} warning", other: "{0} warnings")
        if problems > 0 && warnings > 0 { return L10n.t("{0} and {1} found.", problemText, warningText) }
        return L10n.t("{0} found.", problems > 0 ? problemText : warningText)
    }

    private static func listenCheck(_ snapshot: CompanionSnapshot, pc: Bool) -> TroubleshootCheck? {
        switch snapshot.listen {
        case .failed:
            return TroubleshootCheck(
                id: "phoneListening", status: .problem, title: L10n.t("Lazy Scan could not start receiving"),
                detail: joinSentences(snapshot.listenError,
                                      pc ? L10n.t("Close other copies of Lazy Scan, then select Refresh. Restarting the PC also helps.") : L10n.t("Close other copies of Lazy Scan, then select Refresh. Restarting the Mac also helps.")),
                actions: [.refresh])
        case .offline:
            return TroubleshootCheck(
                id: "phoneListening", status: .problem, title: L10n.t("Not connected to a network"),
                detail: pc ? L10n.t("This PC is not on a network, so phones cannot reach it. Connect to the same Wi-Fi as your phone, or to your phone's hotspot.") : L10n.t("This Mac is not on a network, so phones cannot reach it. Connect to the same Wi-Fi as your phone, or to your phone's hotspot."),
                actions: [.openNetworkSettings, .refresh])
        case .elsewhere:
            return TroubleshootCheck(
                id: "phoneListening", status: .warning, title: L10n.t("Another Lazy Scan window receives from phones"),
                detail: L10n.t("Documents from phones go to the Lazy Scan window that was opened first. Close it to receive here."),
                actions: [.refresh])
        case .off where !snapshot.pairingOpen:
            return TroubleshootCheck(
                id: "phoneListening", status: .tip, title: L10n.t("No phone is paired"),
                detail: pc ? L10n.t("Choose Pair a phone and scan the code with Lazy Scan on your phone. Until a phone is paired, this PC does not listen for phones.") : L10n.t("Choose Pair a phone and scan the code with Lazy Scan on your phone. Until a phone is paired, this Mac does not listen for phones."),
                actions: [])
        case .listening:
            let detail: String
            switch snapshot.pairedCount {
            case 0: detail = L10n.t("Listening on port {0} while the pairing code is shown.", String(snapshot.port))
            default: detail = L10n.plural(snapshot.pairedCount, one: "Listening on port {1}. {0} phone is paired.",
                                          other: "Listening on port {1}. {0} phones are paired.", String(snapshot.port))
            }
            return TroubleshootCheck(id: "phoneListening", status: .ok, title: L10n.t("Ready for phones"), detail: detail, actions: [])
        default:
            return nil
        }
    }

    private static func networkCheck(_ state: CompanionNetworkState, platform: TroubleshootPlatform,
                                      pc: Bool) -> TroubleshootCheck {
        let network = state.network
        let id = "phoneNetwork:\(network.id)"
        let name = network.name.isEmpty ? L10n.t("this network") : network.name
        switch state.trust {
        case .privateNetwork:
            return TroubleshootCheck(
                id: id, status: .ok, title: L10n.t("{0} is a private network", name),
                detail: pc ? L10n.t("Paired phones on this network can send documents to this PC.") : L10n.t("Paired phones on this network can send documents to this Mac."), actions: [])
        case .approved:
            return TroubleshootCheck(
                id: id, status: .ok, title: L10n.t("Receiving allowed: {0}", name),
                detail: pc ? L10n.t("Paired phones on this network can send documents to this PC.") : L10n.t("Paired phones on this network can send documents to this Mac."), actions: [])
        case .notTrusted:
            guard platform == .windows else {
                return TroubleshootCheck(
                    id: id, status: .warning, title: L10n.t("Not receiving: {0}", name),
                    detail: L10n.t("Lazy Scan listens for phones only on networks you allow. If {0} is a network you trust, such as your home Wi-Fi, turn on Allow receiving on this network.", name),
                    actions: [])
            }
            return TroubleshootCheck(
                id: id, status: .warning, title: L10n.t("Not receiving: {0}", name),
                detail: network.category == .domainNetwork
                    ? L10n.t("Windows treats {0} as a work network, so Lazy Scan does not listen for phones there. If it is your home network, set it to Private in Windows network settings. On a network you trust but cannot change, such as your school's Wi-Fi, turn on Allow receiving on this network.", name)
                    : L10n.t("Windows treats {0} as a public network, so Lazy Scan does not listen for phones there. If it is your home network, set it to Private in Windows network settings. On a network you trust but cannot change, such as your school's Wi-Fi, turn on Allow receiving on this network.", name),
                actions: [.openNetworkSettings])
        }
    }

    private static func firewallCheck(_ snapshot: CompanionSnapshot) -> TroubleshootCheck? {
        let wanted = snapshot.listen == .listening || snapshot.listen == .noTrustedNetwork
        switch snapshot.firewall {
        case .blocked:
            var quoted: [String] = []
            for rule in snapshot.blockingRules {
                quoted.append(rule)
            }
            return TroubleshootCheck(
                id: "phoneFirewall", status: .problem, title: L10n.t("Windows Firewall blocks Lazy Scan"),
                detail: quoted.isEmpty
                    ? L10n.t("A Windows Firewall rule stops phones from reaching Lazy Scan on this network. This happens when the firewall's question was cancelled or the network type was not ticked. Someone with administrator rights can open Windows Defender Firewall with Advanced Security (wf.msc), select Inbound Rules and delete the rules for Lazy Scan that block it. Windows then asks again.")
                    : L10n.t("A Windows Firewall rule stops phones from reaching Lazy Scan on this network. This happens when the firewall's question was cancelled or the network type was not ticked. Someone with administrator rights can open Windows Defender Firewall with Advanced Security (wf.msc), select Inbound Rules and delete “{0}” that block it. Windows then asks again.", quoted.joined(separator: ", ")),
                actions: [.refresh])
        case .willAsk where wanted:
            let approvedPublic = snapshot.networks.contains { $0.trust == .approved && $0.network.category != .privateNetwork }
            return TroubleshootCheck(
                id: "phoneFirewall", status: .tip, title: L10n.t("Windows Firewall will ask once"),
                detail: approvedPublic
                    ? L10n.t("When Lazy Scan starts receiving, Windows Firewall asks whether to allow it. Choose Allow, with Public networks ticked for the networks you allowed that Windows treats as public. Cancel blocks phones until the rule it makes is removed.")
                    : L10n.t("When Lazy Scan starts receiving, Windows Firewall asks whether to allow it. Choose Allow. Cancel blocks phones until the rule it makes is removed."),
                actions: [])
        case .allowed:
            return TroubleshootCheck(
                id: "phoneFirewall", status: .ok, title: L10n.t("Windows Firewall allows Lazy Scan"),
                detail: L10n.t("Phones on the networks you receive on can reach this PC."), actions: [])
        default:
            return nil
        }
    }

    private static func localNetworkCheck() -> TroubleshootCheck {
        TroubleshootCheck(
            id: "phoneLocalNetwork", status: .problem, title: L10n.t("Local Network access is off"),
            detail: L10n.t("macOS stops Lazy Scan from announcing this Mac to phones. Turn on Lazy Scan in Local Network settings."),
            more: L10n.t("Open System Settings, Privacy & Security, Local Network, turn on Lazy Scan, then quit Lazy Scan and open it again. A paired phone still reaches this Mac at its last address until that address changes."),
            actions: [.openAppSettings])
    }

    private static func syncFolderCheck(_ snapshot: CompanionSnapshot, pc: Bool) -> TroubleshootCheck? {
        guard snapshot.pairedCount > 0, !snapshot.syncFolderChosen, let quiet = snapshot.phonesQuietFor,
              quiet >= quietTime else { return nil }
        return TroubleshootCheck(
            id: "phoneSyncFolder", status: .tip, title: pc ? L10n.t("Phone has not reached this PC lately?") : L10n.t("Phone has not reached this Mac lately?"),
            detail: pc
                ? L10n.plural(Int(quiet / (24 * 60 * 60)),
                              one: "No paired phone has connected for {0} day. If the phone and this PC are often on a network that keeps devices apart, choose a cloud folder above, one synced by OneDrive or iCloud Drive. The phone then puts documents there when it cannot reach this PC, and they are added here.",
                              other: "No paired phone has connected for {0} days. If the phone and this PC are often on a network that keeps devices apart, choose a cloud folder above, one synced by OneDrive or iCloud Drive. The phone then puts documents there when it cannot reach this PC, and they are added here.")
                : L10n.plural(Int(quiet / (24 * 60 * 60)),
                              one: "No paired phone has connected for {0} day. If the phone and this Mac are often on a network that keeps devices apart, choose a cloud folder above, one synced by OneDrive or iCloud Drive. The phone then puts documents there when it cannot reach this Mac, and they are added here.",
                              other: "No paired phone has connected for {0} days. If the phone and this Mac are often on a network that keeps devices apart, choose a cloud folder above, one synced by OneDrive or iCloud Drive. The phone then puts documents there when it cannot reach this Mac, and they are added here."),
            actions: [])
    }

    private static func rank(_ status: CheckStatus) -> Int {
        switch status {
        case .problem: return 0
        case .warning: return 1
        case .ok: return 2
        case .tip: return 3
        }
    }

    private static func joinNames(_ names: [String]) -> String {
        switch names.count {
        case 0: return L10n.t("this network")
        case 1: return names[0]
        default: return L10n.t("{0} and {1}", names.dropLast().joined(separator: ", "), names[names.count - 1])
        }
    }

    private static func joinSentences(_ first: String?, _ second: String) -> String {
        var head = first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if head.isEmpty { return second }
        if let last = head.last, !".!?".contains(last) { head += "." }
        return "\(head) \(second)"
    }
}
