import Foundation

// The English text is the key and the fallback: with no "Kit" table (tests, a language without
// one) the English comes back unchanged.

public enum L10n {
    /// A table and language that replace the bundle lookup inside `withTable`.
    struct Override: Sendable {
        var table: [String: String]
        var language: String
    }

    @TaskLocal static var override: Override?

    /// Runs `body` with `table` standing in for the Kit table, so a test can check a language
    /// without touching the bundle or other tests running in parallel, and so
    /// `Troubleshooter.report` can write English whatever the system language is.
    static func withTable<T>(_ table: [String: String], language: String, _ body: () throws -> T) rethrows -> T {
        try $override.withValue(Override(table: table, language: language), operation: body)
    }

    /// Runs `body` with every text in English, for what goes into a support report.
    public static func english<T>(_ body: () throws -> T) rethrows -> T {
        try withTable([:], language: "en", body)
    }

    /// The text for `english` in the current language, with `{0}`, `{1}`... filled from `args`.
    /// A trailing `|context` (as in "Scan|noun") tells translators which word is meant and is
    /// never shown in English.
    public static func t(_ english: String, _ args: Any...) -> String {
        format(lookup(english) ?? stripContext(english), args)
    }

    /// `one` when the language's plural rule says so for `n`, else `other`. `{0}` is `n`,
    /// written with the language's number format, and `args` follow from `{1}`.
    public static func plural(_ n: Int, one: String, other: String, _ args: Any...) -> String {
        let category = pluralCategory(n, language: language())
        let english = category == .one ? one : other
        let found = lookup(one + "|" + category.rawValue)
        return format(found ?? stripContext(english), [n] + args)
    }

    enum PluralCategory: String {
        case one, other
    }

    // One rule per language, the CLDR cardinal rules. Add a language here when it gets a column
    // in the catalog; an unknown language uses the English rule.
    private static let pluralRules: [String: @Sendable (Int) -> PluralCategory] = [
        "en": { $0 == 1 ? .one : .other },
        "tr": { $0 == 1 ? .one : .other },
    ]

    static func pluralCategory(_ n: Int, language: String) -> PluralCategory {
        let rule = pluralRules[language] ?? pluralRules["en"]!
        return rule(n)
    }

    private static func language() -> String {
        if let override { return override.language }
        let preferred = Bundle.main.preferredLocalizations.first ?? "en"
        return String(preferred.prefix { $0 != "-" && $0 != "_" })
    }

    private static func lookup(_ key: String) -> String? {
        if let override { return override.table[key] }
        let missing = "\u{0}missing"
        let found = Bundle.main.localizedString(forKey: key, value: missing, table: "Kit")
        return found == missing ? nil : found
    }

    private static func stripContext(_ text: String) -> String {
        guard let bar = text.lastIndex(of: "|") else { return text }
        return String(text[..<bar])
    }

    // The user's region decides the separators, like the date and size formatters elsewhere; only
    // the test override pins a language.
    private static func locale() -> Locale {
        if let override { return Locale(identifier: override.language) }
        return .current
    }

    /// `value` in the user's number format, with between `digits.lowerBound` and `digits.upperBound`
    /// decimals (halves round up).
    static func decimal(_ value: Double, digits: ClosedRange<Int>) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale()
        formatter.roundingMode = .halfUp
        formatter.minimumFractionDigits = digits.lowerBound
        formatter.maximumFractionDigits = digits.upperBound
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// A whole number in the user's digits without grouping, for dpi and version numbers.
    static func plain(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale()
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func describe(_ arg: Any, _ formatter: NumberFormatter) -> String {
        if arg is any BinaryInteger || arg is any BinaryFloatingPoint, let text = formatter.string(for: arg) {
            return text
        }
        return String(describing: arg)
    }

    // One pass, so a value that itself contains "{1}" is left alone. A placeholder with no
    // argument stays as written. Numbers are written in the locale's format.
    private static func format(_ text: String, _ args: [Any]) -> String {
        guard !args.isEmpty, text.contains("{") else { return text }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale()
        var result = ""
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            let tail = rest[rest.index(after: open)...]
            if let close = tail.firstIndex(of: "}"), let i = Int(tail[..<close]), args.indices.contains(i) {
                result += describe(args[i], formatter)
                rest = tail[tail.index(after: close)...]
            } else {
                result.append("{")
                rest = tail
            }
        }
        return result + rest
    }
}
