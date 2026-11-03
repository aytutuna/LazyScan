import Foundation

// The status line's short text. Both apps show at most six words of their status sentence, facts
// only, and keep the whole sentence as the line's accessibility label. Twin of
// windows/LazyScan.Core/StatusLine.cs (same rules, same tests).
//
// The six words are counted on the English text of each piece, whatever the language, so every
// language shows the same facts and the views only truncate what still does not fit. The settings
// notes are matched from their catalog entries, so they work in any language. The message heads
// (Added, Saved, Found, the one-sided mark, "Ready for “", "Page queue cleared", "Reading the text
// of page", "Sent ") are still matched in English: their messages ("Saved {0}", "Saved {0}: {1}",
// "Saved {0}{1}", "Ready for “{0}”.", "Page queue cleared.", "Reading the text of page {0}…", the
// "Sent the ..." keys) must not get translations until the app hands StatusLine structured input
// instead of a sentence.

/// The status line's visible text: at most `maxWords` words, facts only. The full sentence stays the
/// status line's accessibility label, so VoiceOver reads all of it. Twin of C# `StatusLine`.
public enum StatusLine {
    public static let maxWords = 6

    /// Words as the text spec counts them: whitespace-separated tokens with a letter or digit.
    public static func words(_ text: String) -> Int {
        let tokens: [Substring] = text.split(whereSeparator: { (c: Character) -> Bool in c.isWhitespace })
        return tokens.filter { (token: Substring) -> Bool in isWord(token) }.count
    }

    /// `message`'s short form. `deviceName`: the connected scanner, for "Ready — Demo Scanner" after a
    /// task is picked. A setting changed for the scanner, or a two-sided scan that came back
    /// one-sided, keeps a short warning on the line ("Ready — Demo · feeder used", "3 pages added · one
    /// side only"); when the line can't hold both, the warnings win.
    public static func short(_ message: String, deviceName: String? = nil) -> String {
        let text: String = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }
        let found: (warnings: [Warning], notesAt: Int) = findWarnings(text)
        var head: Piece = Piece(text: "", words: 0)
        if found.notesAt > 0 {
            let before: String = (text as NSString).substring(to: found.notesAt)
            head = headOf(before.trimmingCharacters(in: .whitespacesAndNewlines), deviceName: deviceName)
        }
        return compose(head, found.warnings)
    }

    /// `head` with the short warnings found in `message`, the same way `short` adds them: "Saved · 600
    /// dpi used", or the warnings alone when the line can't hold both; just `head` when there are none.
    public static func withWarnings(_ head: String, message: String) -> String {
        compose(Piece(text: head, words: words(head)), warningsIn(message))
    }

    /// The short warnings in `message`, in the order they come: a setting changed for the scanner
    /// ("600 dpi used"), a two-sided scan that came back one-sided ("One side only").
    public static func warnings(_ message: String) -> [String] {
        warningsIn(message).map { (warning: Warning) -> String in warning.short.text }
    }

    /// What the status line shows while the app is idle: nothing while a review shows its own title
    /// (`reviewShown`), "Saved" with any warning while the saved files' actions show (`savedShown`, for
    /// a message about a save), else `short`.
    public static func shown(_ message: String, deviceName: String?, reviewShown: Bool, savedShown: Bool) -> String {
        if reviewShown { return "" }
        let start: String = String(message.drop(while: { (c: Character) -> Bool in c.isWhitespace }))
        if savedShown && start.hasPrefix("Saved") { return compose(piece { L10n.t("Saved") }, warningsIn(message)) }
        return short(message, deviceName: deviceName)
    }

    // MARK: - Private

    /// A two-sided scan came back with one side of each sheet.
    private static let oneSidedMark = "the scanner did not scan both sides"

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

    /// The pattern for the catalog sentence `english` as the current language words it, with each
    /// `{n}` replaced by `groups[n]`.
    private static func pattern(_ english: String, _ groups: String...) -> String {
        var result: String = NSRegularExpression.escapedPattern(for: L10n.t(english))
        for (index, group) in groups.enumerated() {
            result = result.replacingOccurrences(of: "\\{\(index)\\}", with: group)
        }
        return result
    }

    /// A token with a letter or a digit.
    private static func isWord(_ token: Substring) -> Bool {
        token.contains { (c: Character) -> Bool in c.isLetter || c.isNumber }
    }

    /// The sentences `SettingsAdapter` adds when a setting had to change for the scanner, each with its
    /// short form (given the number its pattern captures, if any): a warning stays visible, not only in
    /// the label.
    private static func settingsNotes() -> [(NSRegularExpression, (String) -> Warning)] {
        let papers: String = PaperSize.allCases.map { (size: PaperSize) -> String in
            NSRegularExpression.escapedPattern(for: size.label)
        }.joined(separator: "|")
        let paper: (String) -> Warning = { (_: String) -> Warning in
            Warning(short: piece { L10n.t("Paper size Automatic") }, inline: piece { L10n.t("paper size Automatic|after another fact") })
        }
        let patterns: [(String, (String) -> Warning)] = [
            (pattern("This scanner has no flatbed, so the document feeder is used."), { (_: String) -> Warning in
                Warning(short: piece { L10n.t("Feeder used") }, inline: piece { L10n.t("feeder used|after another fact") })
            }),
            (pattern("This scanner has no document feeder, so the flatbed is used."), { (_: String) -> Warning in
                Warning(short: piece { L10n.t("Flatbed used") }, inline: piece { L10n.t("flatbed used|after another fact") })
            }),
            (pattern("This scanner's feeder scans one side at a time, so you'll turn the stack over by hand."), { (_: String) -> Warning in
                Warning(short: piece { L10n.t("Two-sided by hand") }, inline: piece { L10n.t("two-sided by hand|after another fact") })
            }),
            (pattern("{0} paper does not fit this scanner's feeder, so the paper size is Automatic.", "(?:" + papers + ")"), paper),
            (pattern("{0} paper does not fit this scanner's glass, so the paper size is Automatic.", "(?:" + papers + ")"), paper),
            (pattern("This scanner does not offer {0} dpi, so {1} dpi is used.", "\\d+", "(\\d+)"), { (dpi: String) -> Warning in
                let text: Piece = piece { L10n.t("{0} dpi used", dpi) }
                return Warning(short: text, inline: text)
            }),
        ]
        var notes: [(NSRegularExpression, (String) -> Warning)] = []
        for (pattern, warning) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                notes.append((regex, warning))
            }
        }
        return notes
    }

    /// The warnings in `message`, in the order they come.
    private static func warningsIn(_ message: String) -> [Warning] {
        findWarnings(message.trimmingCharacters(in: .whitespacesAndNewlines)).warnings
    }

    /// The warnings in `text`, and where the first settings note starts (UTF-16 offset; the text's
    /// length when none does).
    private static func findWarnings(_ text: String) -> (warnings: [Warning], notesAt: Int) {
        // The notes are appended after the message: the message is what comes before the first one.
        let ns: NSString = text as NSString
        let whole: NSRange = NSRange(location: 0, length: ns.length)
        var found: [(at: Int, order: Int, warning: Warning)] = []
        var notesAt: Int = ns.length
        for (regex, warning) in settingsNotes() {
            for match in regex.matches(in: text, options: [], range: whole) {
                let captured: String = match.numberOfRanges > 1 ? ns.substring(with: match.range(at: 1)) : ""
                found.append((at: match.range.location, order: found.count, warning: warning(captured)))
                notesAt = min(notesAt, match.range.location)
            }
        }
        let oneSided: NSRange = ns.range(of: oneSidedMark)
        if oneSided.location != NSNotFound {
            let warning: Warning = Warning(short: piece { L10n.t("One side only") }, inline: piece { L10n.t("one side only|after another fact") })
            found.append((at: oneSided.location, order: found.count, warning: warning))
        }
        let sorted = found.sorted { (a: (at: Int, order: Int, warning: Warning), b: (at: Int, order: Int, warning: Warning)) -> Bool in
            a.at != b.at ? a.at < b.at : a.order < b.order
        }
        let warnings: [Warning] = sorted.map { (item: (at: Int, order: Int, warning: Warning)) -> Warning in item.warning }
        return (warnings: warnings, notesAt: notesAt)
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

    /// The groups of `pattern`'s first match in `text` (group 0 is the whole match; a group that took
    /// no part is ""); nil when it does not match.
    private static func number(_ digits: String) -> Int { Int(digits.filter(\.isNumber)) ?? 0 }

    private static func groups(_ pattern: String, in text: String,
                               options: NSRegularExpression.Options = []) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let ns: NSString = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        var result: [String] = []
        for index in 0..<match.numberOfRanges {
            let range: NSRange = match.range(at: index)
            result.append(range.location == NSNotFound ? "" : ns.substring(with: range))
        }
        return result
    }

    /// The short form of the message itself (without the notes after it).
    private static func headOf(_ text: String, deviceName: String?) -> Piece {
        if text.isEmpty { return Piece(text: "", words: 0) }
        if text.hasPrefix("Ready for \u{201C}") {
            if let name = deviceName, !name.isEmpty { return piece { L10n.t("Ready — {0}", name) } }
            return piece { L10n.t("Ready") }
        }
        if let added = groups("^Added (\\d[\\d,.\u{00A0}\u{202F}]*) (?:page|pages)\\b", in: text) {
            let count: Int = number(added[1])
            var head: Piece
            if count == 1, let queue = groups("\u{2014} (\\d[\\d,.\u{00A0}\u{202F}]*) in queue", in: text) {
                head = piece { L10n.t("Page {0} added", number(queue[1])) }
            } else {
                head = piece { L10n.plural(count, one: "{0} page added", other: "{0} pages added") }
            }
            if let blank = groups("(\\d[\\d,.\u{00A0}\u{202F}]*) looks? blank", in: text) {
                head = append(head, piece { L10n.plural(number(blank[1]), one: "{0} blank", other: "{0} blank") })
            }
            if let spreads = groups("(\\d[\\d,.\u{00A0}\u{202F}]*) spreads? split into pages", in: text) {
                head = append(head, piece { L10n.plural(number(spreads[1]), one: "{0} spread split", other: "{0} spreads split") })
            }
            return head
        }
        let savedPattern: String = "^(?:Cancelled \u{2014} )?Saved (\\d[\\d,.\u{00A0}\u{202F}]*) (photos?|receipts?|documents?|files?|PDFs?|copies)\\b"
        if let saved = groups(savedPattern, in: text, options: [.caseInsensitive]) {
            return savedHead(number(saved[1]), noun: saved[2].lowercased())
        }
        if text.hasPrefix("Saved ") { return piece { L10n.t("Saved") } }
        if let found = groups("^Found (\\d[\\d,.\u{00A0}\u{202F}]*) (photos?|receipts?)\\b", in: text) {
            let count: Int = number(found[1])
            if found[2].hasPrefix("photo") { return piece { L10n.plural(count, one: "Found {0} photo", other: "Found {0} photos") } }
            return piece { L10n.plural(count, one: "Found {0} receipt", other: "Found {0} receipts") }
        }
        if text.hasPrefix("Page queue cleared") { return piece { L10n.t("Queue cleared") } }
        if let reading = groups("^Reading the text of page (\\d[\\d,.\u{00A0}\u{202F}]*)(?: of (\\d[\\d,.\u{00A0}\u{202F}]*))?\u{2026}", in: text) {
            let page: Int = number(reading[1])
            if reading[2].isEmpty { return piece { L10n.t("Reading page {0}…", page) } }
            return piece { L10n.t("Reading page {0} of {1}…", page, number(reading[2])) }
        }
        if let adding = groups("^Adding (\\d[\\d,.\u{00A0}\u{202F}]*) pages? to .+\u{2026}$", in: text) {
            return piece { L10n.plural(number(adding[1]), one: "Adding {0} page…", other: "Adding {0} pages…") }
        }
        if text.hasPrefix("Sent ") { return piece { L10n.t("Sent to the printer") } }

        // Anything else: its first sentence, then what comes before a dash or a colon, then its whole facts.
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

    /// "Saved 3 photos" for the kind of file `noun` names (lower case, as the message has it).
    private static func savedHead(_ count: Int, noun: String) -> Piece {
        if noun.hasPrefix("photo") { return piece { L10n.plural(count, one: "Saved {0} photo", other: "Saved {0} photos") } }
        if noun.hasPrefix("receipt") { return piece { L10n.plural(count, one: "Saved {0} receipt", other: "Saved {0} receipts") } }
        if noun.hasPrefix("document") { return piece { L10n.plural(count, one: "Saved {0} document", other: "Saved {0} documents") } }
        if noun.hasPrefix("file") { return piece { L10n.plural(count, one: "Saved {0} file", other: "Saved {0} files") } }
        if noun.hasPrefix("pdf") { return piece { L10n.plural(count, one: "Saved {0} PDF", other: "Saved {0} PDFs") } }
        return piece { L10n.plural(count, one: "Saved {0} copy", other: "Saved {0} copies") }
    }

    /// "6 pages added · 1 blank", while the words stay within the limit.
    private static func append(_ head: Piece, _ part: Piece) -> Piece {
        if head.words + part.words > maxWords { return head }
        return Piece(text: head.text + " \u{00B7} " + part.text, words: head.words + part.words)
    }

    /// The first sentence without its full stop ("…" is kept: it says work is under way).
    private static func firstSentence(_ text: String) -> String {
        let chars: [Character] = Array(text)
        let enders: Set<Character> = [".", "!", "?"]
        var i: Int = 0
        while i + 2 < chars.count {
            let next: Character = chars[i + 2]
            if enders.contains(chars[i]) && chars[i + 1] == " " && (next.isUppercase || next.isNumber) {
                return String(chars[0..<i])
            }
            i += 1
        }
        if text.hasSuffix(".") && !text.hasSuffix("\u{2026}") { return String(text.dropLast()) }
        return text
    }
}
