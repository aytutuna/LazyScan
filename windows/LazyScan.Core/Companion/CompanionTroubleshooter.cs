namespace LazyScan.Core;

// "Why can't my phone connect?": the phone window's checks, in the troubleshooter's form
// (TroubleshootCheck). C# only for now: the networks, firewall and listening they look at are
// Windows'; the Mac server gets its own when it is built.

/// <summary>A connected network and whether the desktop receives on it.</summary>
public sealed record CompanionNetworkState(CompanionNetwork Network, NetworkTrust Trust);

/// <summary>Everything the phone checks look at, read at one moment.</summary>
public sealed record CompanionSnapshot
{
    public IReadOnlyList<CompanionNetworkState> Networks { get; init; } = [];
    public CompanionListenState Listen { get; init; }
    /// <summary>The port listened on; 0 when not listening.</summary>
    public int Port { get; init; }
    /// <summary>Why listening failed, as the system put it; null otherwise.</summary>
    public string? ListenError { get; init; }
    public CompanionFirewallVerdict Firewall { get; init; }
    /// <summary>The names of the firewall rules that block the app.</summary>
    public IReadOnlyList<string> BlockingRules { get; init; } = [];
    public int PairedCount { get; init; }
    public bool PairingOpen { get; init; }
    /// <summary>A cloud sync folder is chosen (C2).</summary>
    public bool SyncFolderChosen { get; init; }
    /// <summary>How long since a paired phone last reached this desktop; null when none is paired.</summary>
    public TimeSpan? PhonesQuietFor { get; init; }
}

public static class CompanionTroubleshooter
{
    /// <summary>How long no paired phone may go unseen before the cloud folder is suggested.</summary>
    public static readonly TimeSpan QuietTime = TimeSpan.FromDays(3);

    /// <summary>The checks: problems first, then warnings, then what is fine, then tips (each group in this order).</summary>
    public static IReadOnlyList<TroubleshootCheck> Diagnose(CompanionSnapshot snapshot)
    {
        var checks = new List<TroubleshootCheck>();
        if (ListenCheck(snapshot) is { } listen) checks.Add(listen);
        foreach (var state in snapshot.Networks) checks.Add(NetworkCheck(state));
        if (FirewallCheck(snapshot) is { } firewall) checks.Add(firewall);
        if (SyncFolderCheck(snapshot) is { } syncFolder) checks.Add(syncFolder);
        checks.Add(new TroubleshootCheck(
            "phoneIsolation", CheckStatus.Tip, Loc.T("Phone cannot connect on the same Wi-Fi?"),
            Loc.T("Some networks, often at schools, hotels and on guest Wi-Fi, keep devices from reaching each other even on the same Wi-Fi. The phone's connection check then says so. Connect this PC to your phone's hotspot instead, or send the document from the phone's share sheet."),
            []));
        return [.. checks.Select((check, index) => (check, index))
                         .OrderBy(pair => Rank(pair.check.Status))
                         .ThenBy(pair => pair.index)
                         .Select(pair => pair.check)];
    }

    /// <summary>"Networks receiving from phones: Home Wi-Fi.", or why not.</summary>
    public static string Headline(CompanionSnapshot snapshot)
    {
        var trusted = snapshot.Networks.Where(n => n.Trust != NetworkTrust.NotTrusted).Select(n => n.Network.Name).ToList();
        var untrusted = snapshot.Networks.Where(n => n.Trust == NetworkTrust.NotTrusted).Select(n => n.Network.Name).ToList();
        return snapshot.Listen switch
        {
            CompanionListenState.Listening => Loc.T("Networks receiving from phones: {0}.", JoinNames(trusted)),
            CompanionListenState.Off => Loc.T("No phone is paired yet."),
            CompanionListenState.Offline => Loc.T("Not connected to a network."),
            CompanionListenState.NoTrustedNetwork => Loc.T("Networks not receiving from phones: {0}.", JoinNames(untrusted)),
            CompanionListenState.Failed => Loc.T("Could not start receiving from phones."),
            CompanionListenState.Elsewhere => Loc.T("Another Lazy Scan window receives from phones."),
            _ => "",
        };
    }

    /// <summary>"2 problems and 1 warning found.", or that nothing stops phones from connecting.</summary>
    public static string Summary(IReadOnlyList<TroubleshootCheck> checks)
    {
        int problems = checks.Count(check => check.Status == CheckStatus.Problem);
        int warnings = checks.Count(check => check.Status == CheckStatus.Warning);
        if (problems == 0 && warnings == 0) return Loc.T("Nothing here stops a paired phone from connecting.");
        string problemText = Loc.Plural(problems, "{0} problem", "{0} problems");
        string warningText = Loc.Plural(warnings, "{0} warning", "{0} warnings");
        if (problems > 0 && warnings > 0) return Loc.T("{0} and {1} found.", problemText, warningText);
        return Loc.T("{0} found.", problems > 0 ? problemText : warningText);
    }

    private static TroubleshootCheck? ListenCheck(CompanionSnapshot snapshot) => snapshot.Listen switch
    {
        CompanionListenState.Failed => new TroubleshootCheck(
            "phoneListening", CheckStatus.Problem, Loc.T("Lazy Scan could not start receiving"),
            JoinSentences(snapshot.ListenError,
                          Loc.T("Close other copies of Lazy Scan, then select Refresh. Restarting the PC also helps.")),
            [TroubleshootAction.Refresh]),
        CompanionListenState.Offline => new TroubleshootCheck(
            "phoneListening", CheckStatus.Problem, Loc.T("Not connected to a network"),
            Loc.T("This PC is not on a network, so phones cannot reach it. Connect to the same Wi-Fi as your phone, or to your phone's hotspot."),
            [TroubleshootAction.OpenNetworkSettings, TroubleshootAction.Refresh]),
        CompanionListenState.Elsewhere => new TroubleshootCheck(
            "phoneListening", CheckStatus.Warning, Loc.T("Another Lazy Scan window receives from phones"),
            Loc.T("Documents from phones go to the Lazy Scan window that was opened first. Close it to receive here."),
            [TroubleshootAction.Refresh]),
        CompanionListenState.Off when !snapshot.PairingOpen => new TroubleshootCheck(
            "phoneListening", CheckStatus.Tip, Loc.T("No phone is paired"),
            Loc.T("Choose Pair a phone and scan the code with Lazy Scan on your phone. Until a phone is paired, this PC does not listen for phones."),
            []),
        CompanionListenState.Listening => new TroubleshootCheck(
            "phoneListening", CheckStatus.Ok, Loc.T("Ready for phones"),
            snapshot.PairedCount switch
            {
                0 => Loc.T("Listening on port {0} while the pairing code is shown.", snapshot.Port.ToString()),
                int count => Loc.Plural(count, "Listening on port {1}. {0} phone is paired.", "Listening on port {1}. {0} phones are paired.",
                    snapshot.Port.ToString()),
            },
            []),
        _ => null,
    };

    private static TroubleshootCheck NetworkCheck(CompanionNetworkState state)
    {
        var network = state.Network;
        string id = $"phoneNetwork:{network.Id}";
        string name = network.Name.Length > 0 ? network.Name : Loc.T("this network");
        return state.Trust switch
        {
            NetworkTrust.Private => new TroubleshootCheck(
                id, CheckStatus.Ok, Loc.T("{0} is a private network", name),
                Loc.T("Paired phones on this network can send documents to this PC."), []),
            NetworkTrust.Approved => new TroubleshootCheck(
                id, CheckStatus.Ok, Loc.T("Receiving allowed: {0}", name),
                Loc.T("Paired phones on this network can send documents to this PC."), []),
            _ => new TroubleshootCheck(
                id, CheckStatus.Warning, Loc.T("Not receiving: {0}", name),
                network.Category == CompanionNetworkCategory.Domain
                    ? Loc.T("Windows treats {0} as a work network, so Lazy Scan does not listen for phones there. If it is your home network, set it to Private in Windows network settings. On a network you trust but cannot change, such as your school's Wi-Fi, turn on Allow receiving on this network.", name)
                    : Loc.T("Windows treats {0} as a public network, so Lazy Scan does not listen for phones there. If it is your home network, set it to Private in Windows network settings. On a network you trust but cannot change, such as your school's Wi-Fi, turn on Allow receiving on this network.", name),
                [TroubleshootAction.OpenNetworkSettings]),
        };
    }

    private static TroubleshootCheck? FirewallCheck(CompanionSnapshot snapshot)
    {
        bool wanted = snapshot.Listen is CompanionListenState.Listening or CompanionListenState.NoTrustedNetwork;
        switch (snapshot.Firewall)
        {
            case CompanionFirewallVerdict.Blocked:
                return new TroubleshootCheck(
                    "phoneFirewall", CheckStatus.Problem, Loc.T("Windows Firewall blocks Lazy Scan"),
                    snapshot.BlockingRules.Count == 0
                        ? Loc.T("A Windows Firewall rule stops phones from reaching Lazy Scan on this network. This happens when the firewall's question was cancelled or the network type was not ticked. Someone with administrator rights can open Windows Defender Firewall with Advanced Security (wf.msc), select Inbound Rules and delete the rules for Lazy Scan that block it. Windows then asks again.")
                        : Loc.T("A Windows Firewall rule stops phones from reaching Lazy Scan on this network. This happens when the firewall's question was cancelled or the network type was not ticked. Someone with administrator rights can open Windows Defender Firewall with Advanced Security (wf.msc), select Inbound Rules and delete {0} that block it. Windows then asks again.",
                                 string.Join(", ", snapshot.BlockingRules.Select(r => $"\"{r}\""))),
                    [TroubleshootAction.Refresh]);
            case CompanionFirewallVerdict.WillAsk when wanted:
                bool approvedPublic = snapshot.Networks.Any(n => n.Trust == NetworkTrust.Approved
                                                                 && n.Network.Category != CompanionNetworkCategory.Private);
                return new TroubleshootCheck(
                    "phoneFirewall", CheckStatus.Tip, Loc.T("Windows Firewall will ask once"),
                    approvedPublic
                        ? Loc.T("When Lazy Scan starts receiving, Windows Firewall asks whether to allow it. Choose Allow, with Public networks ticked for the networks you allowed that Windows treats as public. Cancel blocks phones until the rule it makes is removed.")
                        : Loc.T("When Lazy Scan starts receiving, Windows Firewall asks whether to allow it. Choose Allow. Cancel blocks phones until the rule it makes is removed."),
                    []);
            case CompanionFirewallVerdict.Allowed:
                return new TroubleshootCheck(
                    "phoneFirewall", CheckStatus.Ok, Loc.T("Windows Firewall allows Lazy Scan"),
                    Loc.T("Phones on the networks you receive on can reach this PC."), []);
            default:
                return null;
        }
    }

    private static TroubleshootCheck? SyncFolderCheck(CompanionSnapshot snapshot)
    {
        if (snapshot.PairedCount == 0 || snapshot.SyncFolderChosen || snapshot.PhonesQuietFor is not { } quiet || quiet < QuietTime)
        {
            return null;
        }
        return new TroubleshootCheck(
            "phoneSyncFolder", CheckStatus.Tip, Loc.T("Phone has not reached this PC lately?"),
            Loc.Plural((int)quiet.TotalDays,
                       "No paired phone has connected for {0} day. If the phone and this PC are often on a network that keeps devices apart, choose a cloud folder above, one synced by OneDrive or iCloud Drive. The phone then puts documents there when it cannot reach this PC, and they are added here.",
                       "No paired phone has connected for {0} days. If the phone and this PC are often on a network that keeps devices apart, choose a cloud folder above, one synced by OneDrive or iCloud Drive. The phone then puts documents there when it cannot reach this PC, and they are added here."),
            []);
    }

    private static int Rank(CheckStatus status) => status switch
    {
        CheckStatus.Problem => 0,
        CheckStatus.Warning => 1,
        CheckStatus.Ok => 2,
        _ => 3,
    };

    private static string JoinNames(IReadOnlyList<string> names) => names.Count switch
    {
        0 => Loc.T("this network"),
        1 => names[0],
        _ => Loc.T("{0} and {1}", string.Join(", ", names.Take(names.Count - 1)), names[^1]),
    };

    private static string JoinSentences(string? first, string second)
    {
        string head = first?.Trim() ?? "";
        if (head.Length == 0) return second;
        if (!".!?".Contains(head[^1])) head += ".";
        return $"{head} {second}";
    }
}
