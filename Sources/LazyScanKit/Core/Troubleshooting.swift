import Foundation

// Scanner problems every backend reports the same way, so the user sees one wording whatever
// the connection. Twin of windows/LazyScan.Core/Troubleshooting.cs (same cases, same
// text).

/// A condition at the scanner that stops a scan and that the user can usually fix. The first
/// case is the safe default; add new cases after the existing ones.
public enum ScannerProblem: String, CaseIterable, Sendable {
    /// The scanner reported a problem this version does not recognize.
    case unknown
    case feederEmpty
    case paperJam
    /// A misfeed or a sheet the feeder could not handle (too short, too long, ...).
    case paperProblem
    /// Several sheets were pulled in at once.
    case multiFeed
    case coverOpen
    case offline
    case busy
    case warmingUp
    /// The scanner wants someone at its panel (lamp off, a message on its display, ...).
    case needsAttention
    case communicationError
    /// The system suspended the app in the background before the scanner had finished (the pages
    /// received are kept). Only the iPhone and iPad produce it, through their eSCL connection; the
    /// Windows app never does, but knows its text.
    case appSuspended
}

/// An error as the error bar or alert shows it: what went wrong in a few words, and what to do.
/// Twin of C# `ProblemNotice`.
public struct ProblemNotice: Equatable, Sendable {
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

public enum ScannerProblems {
    /// User-facing text: what happened and what to do about it.
    public static func describe(_ problem: ScannerProblem) -> String {
        switch problem {
        case .feederEmpty:
            return L10n.t("Load paper in the feeder, then scan again.")
        case .paperJam:
            return L10n.t("Paper is jammed in the scanner. Clear the jam, then scan again.")
        case .paperProblem:
            return L10n.t("The scanner could not feed the paper. Check the sheets in the feeder, then scan again.")
        case .multiFeed:
            return L10n.t("The scanner pulled in several sheets at once. Fan the stack, load it again, then scan again.")
        case .coverOpen:
            return L10n.t("The scanner's cover is open. Close it, then scan again.")
        case .offline:
            return L10n.t("The scanner is offline. Check that it is turned on and connected.")
        case .busy:
            return L10n.t("The scanner is busy. Wait until it has finished, then try again.")
        case .warmingUp:
            return L10n.t("The scanner is warming up. Try again in a moment.")
        case .needsAttention:
            return L10n.t("The scanner needs attention. Check its display or control panel.")
        case .communicationError:
            return L10n.t("The connection to the scanner was interrupted. Check the cable or network, then try again.")
        case .appSuspended:
            return L10n.t("The system suspended Lazy Scan in the background before the scan finished. Keep the app open. Put back only the unfinished sheets.")
        case .unknown:
            return L10n.t("The scanner reported a problem. Check the scanner, then try again.")
        }
    }

    /// The title of an error that names no scanner problem.
    public static var genericTitle: String { L10n.t("Something went wrong") }

    /// The problem in two or three words, for the title of the error alert: "Paper jam", "Scanner offline".
    public static func title(_ problem: ScannerProblem) -> String {
        switch problem {
        case .feederEmpty: return L10n.t("Feeder empty")
        case .paperJam: return L10n.t("Paper jam")
        case .paperProblem: return L10n.t("Paper problem")
        case .multiFeed: return L10n.t("Several sheets fed")
        case .coverOpen: return L10n.t("Cover open")
        case .offline: return L10n.t("Scanner offline")
        case .busy: return L10n.t("Scanner busy")
        case .warmingUp: return L10n.t("Warming up")
        case .needsAttention: return L10n.t("Needs attention")
        case .communicationError: return L10n.t("Connection lost")
        case .appSuspended: return L10n.t("App suspended")
        case .unknown: return genericTitle
        }
    }

    /// What to do, in ten words at most, shown under `title`; `describe` is the sentence that stands on
    /// its own (error messages, the status line, the troubleshooter).
    public static func advice(_ problem: ScannerProblem) -> String {
        switch problem {
        case .feederEmpty: return L10n.t("Load paper in the feeder, then scan again.")
        case .paperJam: return L10n.t("Clear the jam, then scan again.")
        case .paperProblem: return L10n.t("Check the sheets in the feeder, then scan again.")
        case .multiFeed: return L10n.t("Fan the stack, load it again, then scan again.")
        case .coverOpen: return L10n.t("Close the cover, then scan again.")
        case .offline: return L10n.t("Turn it on and check the cable or network.")
        case .busy: return L10n.t("Wait until it has finished, then try again.")
        case .warmingUp: return L10n.t("Try again in a moment.")
        case .needsAttention: return L10n.t("Check its display or control panel.")
        case .communicationError: return L10n.t("Check the cable or network, then try again.")
        case .appSuspended: return L10n.t("Keep the app open. Put back only the unfinished sheets.")
        case .unknown: return L10n.t("Check the scanner, then try again.")
        }
    }

    /// The scanner problem an error message describes (its `describe` text is in it); nil when none is.
    public static func find(_ message: String?) -> ScannerProblem? {
        guard let message, !message.isEmpty else { return nil }
        for problem in ScannerProblem.allCases where message.contains(describe(problem)) {
            return problem
        }
        return nil
    }

    /// How the error alert shows `message`: a title naming the problem ("Paper jam") and the message
    /// with the problem's sentence cut to what to do ("Clear the jam, then scan again."); "Something
    /// went wrong" and the message as it is when it names no problem.
    public static func notice(_ message: String) -> ProblemNotice {
        let trimmed: String = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let problem = find(message) else {
            return ProblemNotice(title: genericTitle, message: trimmed)
        }
        let shortened: String = message.replacingOccurrences(of: describe(problem), with: advice(problem))
        return ProblemNotice(title: title(problem),
                             message: shortened.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

/// Why a feeder batch ended before the feeder ran out (a jam, a dropped connection, ...). The
/// scan still returns the pages that transferred; the session keeps this in
/// `ScannerSession.lastScanStop` so the app can tell the user the stack was not finished.
/// Twin of C# `ScanStop`.
public struct ScanStop: Equatable, Sendable {
    /// User-facing text of the failure that stopped the batch.
    public var reason: String
    /// The scanner condition behind it, when the backend could tell.
    public var problem: ScannerProblem?

    public init(reason: String, problem: ScannerProblem? = nil) {
        self.reason = reason
        self.problem = problem
    }

    /// The stop for `error`: its user-facing text and, for a `ScanError`, its problem.
    public static func from(_ error: Error) -> ScanStop {
        ScanStop(reason: error.localizedDescription, problem: (error as? ScanError)?.problem)
    }

    /// User-facing text: how many pages were kept, then why scanning stopped.
    public func message(pagesKept: Int) -> String {
        let kept = L10n.plural(pagesKept, one: "Scanning stopped after {0} page; it was kept.",
                               other: "Scanning stopped after {0} pages; they were kept.")
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kept : "\(kept) \(trimmed)"
    }
}
