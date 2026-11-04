import XCTest
@testable import LazyScanKit

final class L10nTests: XCTestCase {
    func testNoTableReturnsEnglish() {
        XCTAssertEqual(L10n.t("Save as PDF"), "Save as PDF")
    }

    func testPlaceholdersAreFilled() {
        XCTAssertEqual(L10n.t("{1} of {0}", 5, "ab"), "ab of 5")
        XCTAssertEqual(L10n.t("{0} and {0}", "x"), "x and x")
    }

    func testUnmatchedPlaceholderStaysAndValuesAreNotReplaced() {
        XCTAssertEqual(L10n.t("{0} {2} { }", "{1}"), "{1} {2} { }")
    }

    func testContextMarkerIsStrippedInEnglish() {
        XCTAssertEqual(L10n.t("Scan|noun"), "Scan")
        XCTAssertEqual(L10n.t("Scan|verb"), "Scan")
    }

    func testContextMarkerSelectsTheTranslation() {
        let table = ["Scan|noun": "Tarama", "Scan|verb": "Tara"]
        L10n.withTable(table, language: "tr") {
            XCTAssertEqual(L10n.t("Scan|noun"), "Tarama")
            XCTAssertEqual(L10n.t("Scan|verb"), "Tara")
        }
    }

    func testOverrideReplacesTheLookupAndFillsPlaceholders() {
        L10n.withTable(["Open {0}": "{0} dosyasını aç"], language: "tr") {
            XCTAssertEqual(L10n.t("Open {0}", "a.pdf"), "a.pdf dosyasını aç")
            XCTAssertEqual(L10n.t("Not in the table"), "Not in the table")
        }
        XCTAssertEqual(L10n.t("Open {0}", "a.pdf"), "Open a.pdf")
    }

    func testOverrideIsPerTask() {
        final class Box: @unchecked Sendable { var value = "" }
        let box = Box()
        L10n.withTable(["Save": "Kaydet"], language: "tr") {
            let done = DispatchSemaphore(value: 0)
            Thread {
                box.value = L10n.t("Save")
                done.signal()
            }.start()
            done.wait()
            XCTAssertEqual(L10n.t("Save"), "Kaydet")
        }
        XCTAssertEqual(box.value, "Save")
    }

    func testNumbersUseTheLanguageFormat() {
        L10n.withTable([:], language: "tr") {
            XCTAssertEqual(L10n.t("{0} mm", 1.5), "1,5 mm")
            XCTAssertEqual(L10n.t("{0}", 1234), "1.234")
            XCTAssertEqual(L10n.t("{0}", "1234"), "1234")
        }
    }

    func testPlainNumbersAreNotGrouped() {
        L10n.withTable([:], language: "tr") {
            XCTAssertEqual(L10n.plain(1200), "1200")
            XCTAssertEqual(L10n.t("{0} dpi", L10n.plain(1200)), "1200 dpi")
            XCTAssertEqual(L10n.t("{0}", 1200), "1.200")
        }
    }

    func testEnglishPlural() {
        L10n.withTable([:], language: "en") {
            XCTAssertEqual(L10n.plural(1, one: "{0} scan", other: "{0} scans"), "1 scan")
            XCTAssertEqual(L10n.plural(0, one: "{0} scan", other: "{0} scans"), "0 scans")
            XCTAssertEqual(L10n.plural(3, one: "{0} scan", other: "{0} scans"), "3 scans")
        }
    }

    func testPluralWithoutTableFallsBackToEnglish() {
        XCTAssertEqual(L10n.plural(2, one: "{0} scan", other: "{0} scans"), "2 scans")
    }

    func testTurkishPluralUsesItsOwnRows() {
        let table = ["Delete {0} page?|one": "Sayfa silinsin mi?", "Delete {0} page?|other": "{0} sayfa silinsin mi?"]
        L10n.withTable(table, language: "tr") {
            XCTAssertEqual(L10n.plural(1, one: "Delete {0} page?", other: "Delete {0} pages?"), "Sayfa silinsin mi?")
            XCTAssertEqual(L10n.plural(1234, one: "Delete {0} page?", other: "Delete {0} pages?"), "1.234 sayfa silinsin mi?")
        }
    }

    func testPluralContextMarkerStaysInTheKey() {
        XCTAssertEqual(L10n.plural(1, one: "Delete {0} page?|all", other: "Delete all {0} pages?"), "Delete 1 page?")
        let table = ["Delete {0} page?|all|one": "Sayfa silinsin mi?"]
        L10n.withTable(table, language: "tr") {
            XCTAssertEqual(L10n.plural(1, one: "Delete {0} page?|all", other: "Delete all {0} pages?"), "Sayfa silinsin mi?")
        }
    }

    func testPluralExtraArguments() {
        L10n.withTable([:], language: "en") {
            XCTAssertEqual(L10n.plural(2, one: "{0} page in {1}", other: "{0} pages in {1}", "Inbox"), "2 pages in Inbox")
        }
    }

    func testDecimalFollowsTheLanguage() {
        L10n.withTable([:], language: "en") {
            XCTAssertEqual(L10n.decimal(2.4, digits: 1...1), "2.4")
            XCTAssertEqual(L10n.decimal(2, digits: 1...1), "2.0")
            XCTAssertEqual(L10n.decimal(8.5, digits: 0...2), "8.5")
            XCTAssertEqual(L10n.decimal(5, digits: 0...2), "5")
        }
        L10n.withTable([:], language: "tr") {
            XCTAssertEqual(L10n.decimal(2.4, digits: 1...1), "2,4")
            XCTAssertEqual(L10n.decimal(8.27, digits: 0...2), "8,27")
        }
    }

    func testPluralRules() {
        XCTAssertEqual(L10n.pluralCategory(1, language: "en"), .one)
        XCTAssertEqual(L10n.pluralCategory(2, language: "en"), .other)
        XCTAssertEqual(L10n.pluralCategory(1, language: "tr"), .one)
        XCTAssertEqual(L10n.pluralCategory(0, language: "tr"), .other)
        XCTAssertEqual(L10n.pluralCategory(1, language: "xx"), .one)
        XCTAssertEqual(L10n.pluralCategory(2, language: "xx"), .other)
    }

    func testPluralRuleKeyDropsSubtags() {
        XCTAssertEqual(L10n.pluralCategory(0, language: "zh-Hant-HK"), .other)
        XCTAssertEqual(L10n.pluralCategory(1, language: "zh-Hant-HK"), .other)
        XCTAssertEqual(L10n.pluralCategory(1_000_000, language: "pt-PT"), .many)
        XCTAssertEqual(L10n.pluralCategory(1_000_000, language: "pt-BR"), .many)
        XCTAssertEqual(L10n.pluralCategory(0, language: "pt-BR"), .one)
        XCTAssertEqual(L10n.pluralCategory(0, language: "pt_PT"), .other)
        XCTAssertEqual(L10n.pluralCategory(3, language: "ru-RU"), .few)
    }

    func testPluralWithoutRowsUsesTheEnglishRule() {
        L10n.withTable([:], language: "ru") {
            XCTAssertEqual(L10n.plural(1, one: "{0} scan", other: "{0} scans"), "1 scan")
            XCTAssertEqual(L10n.plural(21, one: "{0} scan", other: "{0} scans"), "21 scans")
            XCTAssertEqual(L10n.plural(3, one: "{0} scan", other: "{0} scans"), "3 scans")
        }
    }

    func testPluralFallsBackToTheOtherRow() {
        let table = ["{0} scan|other": "{0} Scans"]
        L10n.withTable(table, language: "ru") {
            XCTAssertEqual(L10n.plural(3, one: "{0} scan", other: "{0} scans"), "3 Scans")
            XCTAssertEqual(L10n.plural(1, one: "{0} scan", other: "{0} scans"), "1 Scans")
        }
    }

    func testEverySampleOfEveryLanguage() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("l10n/plural.json"))
        let languages = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var checked = 0
        for (language, value) in languages where language != "cldr" {
            let rules = try XCTUnwrap(value as? [String: [String: String]], language)
            for (category, entry) in rules {
                for n in Self.integerSamples(entry["integer"] ?? "") {
                    XCTAssertEqual(L10n.pluralCategory(n, language: language).rawValue, category, "\(language) \(n)")
                    checked += 1
                }
            }
        }
        XCTAssertGreaterThan(checked, 500)
    }

    // "0, 2~16, 100, 1c3, …": values, ranges and compact exponents; decimals and the ellipsis are skipped.
    private static func integerSamples(_ text: String) -> [Int] {
        var result: [Int] = []
        for part in text.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if let tilde = part.firstIndex(of: "~") {
                if let low = Int(part[..<tilde]), let high = Int(part[part.index(after: tilde)...]) {
                    result += Array(low...high)
                }
            } else if let c = part.firstIndex(of: "c") {
                if let base = Int(part[..<c]), let exponent = Int(part[part.index(after: c)...]) {
                    result.append(base * Int(pow(10, Double(exponent))))
                }
            } else if let value = Int(part) {
                result.append(value)
            }
        }
        return result
    }
}
