import Foundation

// The status line's short text. Both apps show at most six words of their status sentence, facts
// only, and keep the whole sentence as the line's accessibility label. Twin of
// windows/LazyScan.Core/StatusLine.cs (same rules, same tests).
//
// The producers of a status hand over what the line needs next to the sentence (`StatusDetail`:
// the kind of message and the warnings), so nothing here reads the sentence's language. The six
// words are counted on the English text of each piece, whatever the language, so every language
// shows the same facts and the views only truncate what still does not fit.

/// A kind of file a status counts.
public enum FileKind: Equatable, Sendable {
    case photo
    case receipt
    case pdf
}

/// What a status says about the message itself, for the short line.
public enum StatusHead: Equatable, Sendable {
    /// A task was picked: "Ready — Demo Scanner" (the scanner connected) or "Ready".
    case readyForTask
    /// Pages joined the queue; `queue` is the queue's length (nil when the message gives none),
    /// `blank` and `split` the blank pages and the spreads split among them.
    case pagesAdded(Int, queue: Int?, blank: Int, split: Int)
    /// A save, whatever it wrote: "Saved".
    case saved
    /// A save of `count` files of one kind: "Saved 3 photos".
    case savedFiles(Int, FileKind)
    /// A review's find: "Found 3 photos".
    case found(Int, FileKind)
    case queueCleared
    case readingPage(Int, of: Int?)
    case addingPages(Int)
    case sentToPrinter

    /// The message is about a save.
    var isSave: Bool {
        switch self {
        case .saved, .savedFiles: return true
        default: return false
        }
    }
}

/// A short warning a status keeps on the line. Twin of C# `StatusWarning`.
public enum StatusWarning: Equatable, Sendable {
    case feederUsed
    case flatbedUsed
    case twoSidedByHand
    case paperAutomatic
    case dpiUsed(Int)
    /// A two-sided scan came back with one side of each sheet.
    case oneSideOnly
}

/// What goes with a status sentence for the short line: the kind of message, the warnings in the
/// order they come, and for a message with no kind the sentence without the settings notes after it.
public struct StatusDetail: Equatable, Sendable {
    public var head: StatusHead?
    public var warnings: [StatusWarning]
    public var body: String?

    public init(head: StatusHead? = nil, warnings: [StatusWarning] = [], body: String? = nil) {
        self.head = head
        self.warnings = warnings
        self.body = body
    }
}

/// The status line's visible text: at most `maxWords` words, facts only. The full sentence stays the
/// status line's accessibility label, so VoiceOver reads all of it. Twin of C# `StatusLine`.
public enum StatusLine {
    public static let maxWords = 6

    /// Words as the text spec counts them: whitespace-separated tokens with a letter or digit.
    public static func words(_ text: String) -> Int {
        let tokens: [Substring] = text.split(whereSeparator: { (c: Character) -> Bool in c.isWhitespace })
        return tokens.filter { (token: Substring) -> Bool in isWord(token) }.count
    }

    /// `message`'s short form. `detail`: what its producer says about it. `deviceName`: the connected
    /// scanner, for "Ready — Demo Scanner" after a task is picked. A setting changed for the scanner, or
    /// a two-sided scan that came back one-sided, keeps a short warning on the line ("Ready — Demo ·
    /// feeder used", "3 pages added · one side only"); when the line can't hold both, the warnings win.
    public static func short(_ message: String, _ detail: StatusDetail = StatusDetail(), deviceName: String? = nil) -> String {
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "" }
        let text: String = (detail.body ?? message).trimmingCharacters(in: .whitespacesAndNewlines)
        return compose(headOf(text, detail.head, deviceName: deviceName), detail.warnings.map(warning))
    }

    /// The short warnings of `detail`, in the order they come: a setting changed for the scanner
    /// ("600 dpi used"), a two-sided scan that came back one-sided ("One side only").
    public static func warnings(_ detail: StatusDetail) -> [String] {
        detail.warnings.map { (w: StatusWarning) -> String in warning(w).short.text }
    }

    /// What the status line shows while the app is idle: nothing while a review shows its own title
    /// (`reviewShown`), "Saved" with any warning while the saved files' actions show (`savedShown`, for
    /// a message about a save), else `short`.
    public static func shown(_ message: String, _ detail: StatusDetail, deviceName: String?, reviewShown: Bool, savedShown: Bool) -> String {
        if reviewShown { return "" }
        if savedShown && detail.head?.isSave == true { return compose(piece { L10n.t("Saved") }, detail.warnings.map(warning)) }
        return short(message, detail, deviceName: deviceName)
    }

    // MARK: - Private

    /// A piece of the line with its word count in English.
    private struct Piece {
        let text: String
        let words: Int
    }

    /// `render`'s text in the current language, counted as the English text it stands for.
    private static func piece(_ render: () -> String) -> Piece {
        let english: Int = L10n.withTable([:], language: "en") { words(render()) }
        return Piece(text: render(), words: english)
    }

    /// A warning's short form, and the form that follows another fact on the line ("Ready — Demo ·
    /// feeder used"). Written out for each, so a language can start the second one the way it needs to.
    private struct Warning {
        let short: Piece
        let inline: Piece
    }

    /// A token with a letter or a digit.
    private static func isWord(_ token: Substring) -> Bool {
        token.contains { (c: Character) -> Bool in c.isLetter || c.isNumber }
    }

    private static func warning(_ w: StatusWarning) -> Warning {
        switch w {
        case .feederUsed:
            return Warning(short: piece { L10n.t("Feeder used") }, inline: piece { L10n.t("feeder used|after another fact") })
        case .flatbedUsed:
            return Warning(short: piece { L10n.t("Flatbed used") }, inline: piece { L10n.t("flatbed used|after another fact") })
        case .twoSidedByHand:
            return Warning(short: piece { L10n.t("Two-sided by hand") }, inline: piece { L10n.t("two-sided by hand|after another fact") })
        case .paperAutomatic:
            return Warning(short: piece { L10n.t("Paper size Automatic") }, inline: piece { L10n.t("paper size Automatic|after another fact") })
        case .dpiUsed(let dpi):
            let text: Piece = piece { L10n.t("{0} dpi used", L10n.plain(dpi)) }
            return Warning(short: text, inline: text)
        case .oneSideOnly:
            return Warning(short: piece { L10n.t("One side only") }, inline: piece { L10n.t("one side only|after another fact") })
        }
    }

    /// The head, then the warnings while they fit; when the line can't hold both, the warnings win.
    private static func compose(_ head: Piece, _ warnings: [Warning]) -> String {
        guard let firstWarning = warnings.first else { return head.text }
        if !head.text.isEmpty {
            let inline: [String] = warnings.map { (w: Warning) -> String in w.inline.text }
            let count: Int = warnings.reduce(head.words) { (sum: Int, w: Warning) -> Int in sum + w.inline.words }
            if count <= maxWords { return ([head.text] + inline).joined(separator: " \u{00B7} ") }
        }
        // Not room for the message too: the warnings alone, as many as fit, then how many more.
        var shown: String = firstWarning.short.text
        var shownWords: Int = firstWarning.short.words
        var i: Int = 1
        while i < warnings.count {
            // While more would follow, keep a word free for "+N".
            let room: Int = maxWords - (i < warnings.count - 1 ? 1 : 0)
            if shownWords + warnings[i].inline.words > room { break }
            shown += " \u{00B7} " + warnings[i].inline.text
            shownWords += warnings[i].inline.words
            i += 1
        }
        return i < warnings.count ? shown + " " + L10n.t("+{0}", warnings.count - i) : shown
    }

    /// The short form of the message itself (without the notes after it).
    private static func headOf(_ text: String, _ head: StatusHead?, deviceName: String?) -> Piece {
        switch head {
        case .readyForTask?:
            if let name = deviceName, !name.isEmpty { return piece { L10n.t("Ready — {0}", name) } }
            return piece { L10n.t("Ready") }
        case .pagesAdded(let count, let queue, let blank, let split)?:
            var added: Piece
            if count == 1, let queue {
                added = piece { L10n.t("Page {0} added", queue) }
            } else {
                added = piece { L10n.plural(count, one: "{0} page added", other: "{0} pages added") }
            }
            if blank > 0 {
                added = append(added, piece { L10n.plural(blank, one: "{0} blank", other: "{0} blank") })
            }
            if split > 0 {
                added = append(added, piece { L10n.plural(split, one: "{0} spread split", other: "{0} spreads split") })
            }
            return added
        case .saved?:
            return piece { L10n.t("Saved") }
        case .savedFiles(let count, let kind)?:
            switch kind {
            case .photo: return piece { L10n.plural(count, one: "Saved {0} photo", other: "Saved {0} photos") }
            case .receipt: return piece { L10n.plural(count, one: "Saved {0} receipt", other: "Saved {0} receipts") }
            case .pdf: return piece { L10n.plural(count, one: "Saved {0} PDF", other: "Saved {0} PDFs") }
            }
        case .found(let count, let kind)?:
            if kind == .receipt { return piece { L10n.plural(count, one: "Found {0} receipt", other: "Found {0} receipts") } }
            return piece { L10n.plural(count, one: "Found {0} photo", other: "Found {0} photos") }
        case .queueCleared?:
            return piece { L10n.t("Queue cleared") }
        case .readingPage(let page, let total)?:
            if let total { return piece { L10n.t("Reading page {0} of {1}…", page, total) } }
            return piece { L10n.t("Reading page {0}…", page) }
        case .addingPages(let count)?:
            return piece { L10n.plural(count, one: "Adding {0} page…", other: "Adding {0} pages…") }
        case .sentToPrinter?:
            return piece { L10n.t("Sent to the printer") }
        case nil:
            return generic(text)
        }
    }

    /// A message with no kind: its first sentence, then what comes before a dash or a colon, then its
    /// whole facts.
    private static func generic(_ text: String) -> Piece {
        if text.isEmpty { return Piece(text: "", words: 0) }
        let first: String = firstSentence(text)
        if words(first) <= maxWords { return Piece(text: first, words: words(first)) }
        for mark in [" \u{2014} ", ": ", ", "] {
            if let range = first.range(of: mark), range.lowerBound > first.startIndex {
                let before: String = String(first[first.startIndex..<range.lowerBound])
                if words(before) <= maxWords { return Piece(text: before, words: words(before)) }
            }
        }
        // Facts joined by " · " ("9 pages · 3 documents · 2 separator pages skipped"): the whole facts that fit.
        let facts: [String] = first.components(separatedBy: " \u{00B7} ")
        if facts.count > 1, words(facts[0]) <= maxWords {
            var shown: String = facts[0]
            for fact in facts.dropFirst() {
                let next: String = shown + " \u{00B7} " + fact
                if words(next) > maxWords { break }
                shown = next
            }
            return Piece(text: shown, words: words(shown))
        }
        let tokens: [Substring] = first.split(separator: " ", omittingEmptySubsequences: true)
        var kept: [String] = []
        var count: Int = 0
        for token in tokens {
            if isWord(token) {
                count += 1
                if count > maxWords { break }
            }
            kept.append(String(token))
        }
        var joined: String = kept.joined(separator: " ")
        let trailing: Set<Character> = [",", ":", ";", ".", " "]
        while let last: Character = joined.last, trailing.contains(last) {
            joined.removeLast()
        }
        return Piece(text: joined + "\u{2026}", words: min(count, maxWords))
    }

    /// "6 pages added · 1 blank", while the words stay within the limit.
    private static func append(_ head: Piece, _ part: Piece) -> Piece {
        if head.words + part.words > maxWords { return head }
        return Piece(text: head.text + " \u{00B7} " + part.text, words: head.words + part.words)
    }

    /// The first sentence without its full stop ("…" is kept: it says work is under way).
    private static func firstSentence(_ text: String) -> String {
        let chars: [Character] = Array(text)
        let spaced: Set<Character> = [".", "!", "?", "\u{061F}", "\u{0964}"]
        let fullWidth: Set<Character> = ["\u{3002}", "\u{FF01}", "\u{FF1F}"]
        var i: Int = 0
        while i < chars.count {
            if fullWidth.contains(chars[i]) { return String(chars[0..<i]) }
            if i + 2 < chars.count && spaced.contains(chars[i]) && chars[i + 1] == " " {
                let j: Int = chars[i + 2] == "\u{2068}" && i + 3 < chars.count ? i + 3 : i + 2
                let next: Character = chars[j]
                if (next.isLetter && !next.isLowercase) || next.isNumber { return String(chars[0..<i]) }
            }
            i += 1
        }
        if text.hasSuffix(".") && !text.hasSuffix("\u{2026}") { return String(text.dropLast()) }
        return text
    }
}
