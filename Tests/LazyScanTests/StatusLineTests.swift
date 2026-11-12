import XCTest
import CoreGraphics
import Foundation
@testable import LazyScanKit

// Mirrors windows/LazyScan.Core.Tests/StatusLineTests.cs: the status line's six words.

final class StatusLineTests: XCTestCase {

    func test_short_readsCountsWithThousandsSeparators() {
        L10n.withTable([:], language: "en") {
            XCTAssertEqual(StatusLine.short("Added 1 page \u{2014} 1,000 in queue.",
                                            StatusDetail(head: .pagesAdded(1, queue: 1000, blank: 0, split: 0))), "Page 1,000 added")
            XCTAssertEqual(StatusLine.short("Found 1,200 photos.", StatusDetail(head: .found(1200, .photo))), "Found 1,200 photos")
        }
    }

    func test_short_isShortAndFactual() {
        let added: (Int, Int, Int, Int) -> StatusHead = { (count: Int, queue: Int, blank: Int, split: Int) -> StatusHead in
            .pagesAdded(count, queue: queue, blank: blank, split: split)
        }
        let cases: [(String, StatusDetail, String)] = [
            ("Added 1 page \u{2014} 3 in queue. Scan more or Save PDF.", StatusDetail(head: added(1, 3, 0, 0)), "Page 3 added"),
            ("Added 6 pages, both sides of each sheet \u{2014} 6 in queue. Scan more or Save PDF. 1 looks blank and will be skipped.",
             StatusDetail(head: added(6, 6, 1, 0)), "6 pages added \u{00B7} 1 blank"),
            ("Added 2 pages \u{2014} 4 in queue. Scan more or Save PDF. 1 spread split into pages. Spine shadow softened on 2 pages.",
             StatusDetail(head: added(2, 4, 0, 1)), "2 pages added \u{00B7} 1 spread split"),
            ("Added 2 pages from Aytu's iPhone \u{2014} 3 in queue.", StatusDetail(head: added(2, 3, 0, 0)), "2 pages added"),
            ("Added 1 page to Contract.pdf (now 4 pages, 1.1 MB)",
             StatusDetail(head: .pagesAdded(1, queue: nil, blank: 0, split: 0)), "1 page added"),
            ("Saved 3-page PDF: Scan 2026-10-20 1.pdf (497.7 KB)", StatusDetail(head: .saved), "Saved"),
            ("Saved 3 photos to /Users/me/files", StatusDetail(head: .savedFiles(3, .photo)), "Saved 3 photos"),
            ("Saved 2 receipts: a.pdf, b.pdf", StatusDetail(head: .savedFiles(2, .receipt)), "Saved 2 receipts"),
            ("Saved 1 PDF (7 pages): A.pdf", StatusDetail(head: .savedFiles(1, .pdf)), "Saved 1 PDF"),
            ("Found 3 photos.", StatusDetail(head: .found(3, .photo)), "Found 3 photos"),
            ("Found 1 receipt.", StatusDetail(head: .found(1, .receipt)), "Found 1 receipt"),
            ("Front scanned. Turn the card over where it lies and scan the back, or skip it.", StatusDetail(), "Front scanned"),
            ("Back scanned. Check the sides, then save.", StatusDetail(), "Back scanned"),
            ("Page queue cleared.", StatusDetail(head: .queueCleared(0)), "Queue cleared"),
            ("Cleared 12 pages.", StatusDetail(head: .queueCleared(12)), "Cleared 12 pages"),
            ("Cleared 1 page.", StatusDetail(head: .queueCleared(1)), "Cleared 1 page"),
            ("Page removed.", StatusDetail(head: .pagesRemoved(1)), "Page removed"),
            ("3 pages removed.", StatusDetail(head: .pagesRemoved(3)), "3 pages removed"),
            ("Save undone: the pages are in the queue again.", StatusDetail(), "Save undone"),
            ("Save undone: Contract.pdf is as it was, and the pages are in the queue again.", StatusDetail(), "Save undone"),
            ("Ready \u{2014} Demo Scanner", StatusDetail(), "Ready \u{2014} Demo Scanner"),
            ("Overview ready \u{2014} drag on the preview to select an area, then Scan.", StatusDetail(), "Overview ready"),
            ("Overview ready \u{2014} tap the preview to choose the scan area, then Scan.", StatusDetail(), "Overview ready"),
            ("Scanning\u{2026}", StatusDetail(), "Scanning\u{2026}"),
            ("Reading the text of page 3 of 12\u{2026}", StatusDetail(head: .readingPage(3, of: 12)), "Reading page 3 of 12\u{2026}"),
            ("Reading the text of page 3\u{2026}", StatusDetail(head: .readingPage(3, of: nil)), "Reading page 3\u{2026}"),
            ("Adding 3 pages to Scan 2026-10-20 1.pdf\u{2026}", StatusDetail(head: .addingPages(3)), "Adding 3 pages\u{2026}"),
            ("Sent the ruler test page to Office Laser. At real size each square measures 1 inch.",
             StatusDetail(head: .sentToPrinter), "Sent to the printer"),
            ("3 pages sent to MacBook.", StatusDetail(), "3 pages sent to MacBook"),
            ("9 pages \u{00B7} 3 documents.", StatusDetail(), "9 pages \u{00B7} 3 documents"),
            ("9 pages \u{00B7} 3 documents \u{00B7} 2 separator pages skipped.", StatusDetail(), "9 pages \u{00B7} 3 documents"),
            ("12 pages \u{00B7} 4 documents \u{00B7} 2 separator pages and 1 blank skipped.", StatusDetail(), "12 pages \u{00B7} 4 documents"),
            ("24 pages \u{00B7} 5 blank skipped.", StatusDetail(), "24 pages \u{00B7} 5 blank skipped"),
        ]
        for (message, detail, expected) in cases {
            XCTAssertEqual(StatusLine.short(message, detail), expected, message)
        }
    }

    func test_short_readyForATask_namesTheScannerInstead() {
        let ready = StatusDetail(head: .readyForTask)
        XCTAssertEqual(StatusLine.short("Ready for \u{201C}Document to PDF\u{201D}.", ready, deviceName: "Demo Scanner"),
                       "Ready \u{2014} Demo Scanner")
        XCTAssertEqual(StatusLine.short("Ready for \u{201C}Document to PDF\u{201D}.", ready), "Ready")
        XCTAssertEqual(StatusLine.short("   "), "")
    }

    func test_short_neverShowsMoreThanSixWords() {
        let messages: [String] = [
            "Could not connect to the Epson Perfection V600 Photo scanner over the network.",
            "Scanned 3 front sides before the feeder stopped. Load the rest of the stack and scan, or turn it over.",
            "The ID card task ended during the scan. Nothing of the card was kept.",
            "A very long message without any punctuation that goes on and on about nothing in particular",
        ]
        for message in messages {
            let shown = StatusLine.short(message)
            XCTAssertTrue((1...StatusLine.maxWords).contains(StatusLine.words(shown)), shown)
        }
    }

    func test_short_ofALongSentence_endsWithAnEllipsis() {
        XCTAssertEqual(StatusLine.short("A very long message without any punctuation that goes on and on about nothing in particular"),
                       "A very long message without any\u{2026}")
        XCTAssertEqual(StatusLine.short("Could not connect to the Epson Perfection V600 Photo scanner over the network."),
                       "Could not connect to the Epson\u{2026}")
        XCTAssertEqual(StatusLine.short("Scanned 3 front sides before the feeder stopped. Load the rest of the stack and scan, or turn it over."),
                       "Scanned 3 front sides before the\u{2026}")
    }

    /// The status after settings met a scanner, as the apps build it: the message, then each note.
    private func withNotes(_ message: String, _ settings: ScanSettings, _ capabilities: ScannerCapabilities,
                           head: StatusHead? = nil) -> (message: String, detail: StatusDetail) {
        let notes: [SettingsNote] = SettingsAdapter.adapt(settings, to: capabilities).notes
        XCTAssertFalse(notes.isEmpty)
        return (message: message + " " + notes.map(\.message).joined(separator: " "),
                detail: StatusDetail(head: head, warnings: notes.map(\.warning), body: message))
    }

    func test_short_keepsASettingChangedForTheScanner_asAShortWarning() {
        var six = ScanSettings()
        six.resolution = 600
        let lowResolution = ScannerCapabilities(supportedResolutions: [150, 300])
        // A preset at 600 dpi on a scanner that tops out at 300.
        let resolution = withNotes("Applied preset \u{201C}Invoices\u{201D}.", six, lowResolution)
        XCTAssertEqual(StatusLine.short(resolution.message, resolution.detail), "Applied preset \u{201C}Invoices\u{201D} \u{00B7} 300 dpi used")
        // A longer preset name leaves no room: the warning wins.
        let longName = withNotes("Applied preset \u{201C}Monthly office invoices\u{201D}.", six, lowResolution)
        XCTAssertEqual(StatusLine.short(longName.message, longName.detail), "300 dpi used")
        // A scanner without a flatbed connects: no full stop before the note, and the name stays.
        var flatbedSettings = ScanSettings()
        flatbedSettings.source = .flatbed
        let feederOnly = ScannerCapabilities(sources: [.documentFeeder], feederSizeInches: CGSize(width: 8.5, height: 14))
        let feeder = withNotes("Ready \u{2014} Demo Scanner", flatbedSettings, feederOnly)
        XCTAssertEqual(StatusLine.short(feeder.message, feeder.detail), "Ready \u{2014} Demo Scanner \u{00B7} feeder used")
        // A task is picked: "Ready — device" and the note.
        let picked = withNotes("Ready for \u{201C}Document to PDF\u{201D}.", flatbedSettings, feederOnly, head: .readyForTask)
        XCTAssertEqual(StatusLine.short(picked.message, picked.detail, deviceName: "Demo Scanner"),
                       "Ready \u{2014} Demo Scanner \u{00B7} feeder used")
        var feederSettings = ScanSettings()
        feederSettings.source = .documentFeeder
        let flatbed = withNotes("Ready \u{2014} Demo Scanner", feederSettings, ScannerCapabilities(sources: [.flatbed]))
        XCTAssertEqual(StatusLine.short(flatbed.message, flatbed.detail), "Ready \u{2014} Demo Scanner \u{00B7} flatbed used")
        var legal = ScanSettings()
        legal.paperSize = .legal
        let paper = withNotes("Ready \u{2014} Demo Scanner", legal, ScannerCapabilities())
        XCTAssertEqual(StatusLine.short(paper.message, paper.detail), "Ready \u{2014} Demo Scanner \u{00B7} paper size Automatic")
        var both = ScanSettings()
        both.source = .documentFeeder
        both.duplex = .both
        let sides = withNotes("Ready \u{2014} Demo Scanner", both, feederOnly)
        XCTAssertEqual(StatusLine.short(sides.message, sides.detail), "Ready \u{2014} Demo Scanner \u{00B7} two-sided by hand")
        // Every note at once: as many as fit, then how many more.
        var everything = ScanSettings()
        everything.source = .flatbed
        everything.duplex = .both
        everything.paperSize = .legal
        everything.resolution = 600
        let small = ScannerCapabilities(supportedResolutions: [300], sources: [.documentFeeder],
                                        feederSizeInches: CGSize(width: 8.5, height: 11))
        let all = withNotes("Ready \u{2014} Demo Scanner", everything, small)
        XCTAssertEqual(StatusLine.short(all.message, all.detail), "Feeder used \u{00B7} two-sided by hand +2")
        for status in [resolution, longName, feeder, picked, flatbed, paper, sides, all] {
            let line = StatusLine.short(status.message, status.detail, deviceName: "Demo Scanner")
            XCTAssertTrue((1...StatusLine.maxWords).contains(StatusLine.words(line)))
        }
    }

    func test_short_aTwoSidedScanThatCameBackOneSided_saysSo() {
        XCTAssertEqual(StatusLine.short(
            "Added 3 pages, one side of each sheet: the scanner did not scan both sides \u{2014} 3 in queue. Scan more or Save PDF.",
            StatusDetail(head: .pagesAdded(3, queue: 3, blank: 0, split: 0), warnings: [.oneSideOnly])),
                       "3 pages added \u{00B7} one side only")
        XCTAssertEqual(StatusLine.short(
            "Added 1 page, one side of each sheet: the scanner did not scan both sides \u{2014} 4 in queue. Scan more or Save PDF.",
            StatusDetail(head: .pagesAdded(1, queue: 4, blank: 0, split: 0), warnings: [.oneSideOnly])),
                       "Page 4 added \u{00B7} one side only")
    }

    func test_short_worksWithTextInAnyLanguage() {
        let table: [String: String] = [
            "{0} page added|other": "{0} sayfa eklendi",
            "Page {0} added": "{0}. sayfa eklendi",
            "Saved {0} photo|other": "{0} foto\u{011F}raf kaydedildi",
            "Saved": "Kaydedildi",
            "Queue cleared": "S\u{0131}ra temizlendi",
            "{0} dpi used": "{0} dpi kullan\u{0131}ld\u{0131}",
            "One side only": "Tek y\u{00FC}z",
            "one side only|after another fact": "tek y\u{00FC}z",
            "Feeder used": "Besleyici",
        ]
        L10n.withTable(table, language: "tr") {
            // Nothing in the sentence is read: any words do for the same kind of message.
            let queued = StatusDetail(head: .pagesAdded(3, queue: 5, blank: 0, split: 0), warnings: [.oneSideOnly])
            XCTAssertEqual(StatusLine.short("Kuyru\u{011F}a 3 sayfa eklendi.", queued), "3 sayfa eklendi \u{00B7} tek y\u{00FC}z")
            XCTAssertEqual(StatusLine.short("Kuyru\u{011F}a bir sayfa eklendi.",
                                            StatusDetail(head: .pagesAdded(1, queue: 5, blank: 0, split: 0))), "5. sayfa eklendi")
            XCTAssertEqual(StatusLine.short("3 foto\u{011F}raf kaydedildi: /Users/me/files", StatusDetail(head: .savedFiles(3, .photo))),
                           "3 foto\u{011F}raf kaydedildi")
            XCTAssertEqual(StatusLine.short("S\u{0131}ra temizlendi.", StatusDetail(head: .queueCleared(0))), "S\u{0131}ra temizlendi")
            // Under the saved files' actions: "Saved", with the warnings.
            let saved = StatusDetail(head: .saved, warnings: [.dpiUsed(600)])
            XCTAssertEqual(StatusLine.shown("Dosya kaydedildi.", saved, deviceName: nil, reviewShown: false, savedShown: true),
                           "Kaydedildi \u{00B7} 600 dpi kullan\u{0131}ld\u{0131}")
            XCTAssertEqual(StatusLine.warnings(StatusDetail(warnings: [.feederUsed, .dpiUsed(300)])),
                           ["Besleyici", "300 dpi kullan\u{0131}ld\u{0131}"])
        }
    }

    func test_short_cutsTheFirstSentence_ofTextWithoutCase() {
        XCTAssertEqual(StatusLine.short("\u{0627}\u{0644}\u{0648}\u{062C}\u{0647} \u{0645}\u{0645}\u{0633}\u{0648}\u{062D}. \u{0627}\u{0642}\u{0644}\u{0628} \u{0627}\u{0644}\u{0628}\u{0637}\u{0627}\u{0642}\u{0629} \u{0648}\u{0627}\u{0645}\u{0633}\u{062D} \u{0627}\u{0644}\u{062E}\u{0644}\u{0641} \u{0623}\u{0648} \u{062A}\u{062C}\u{0627}\u{0648}\u{0632}\u{0647}."),
                       "\u{0627}\u{0644}\u{0648}\u{062C}\u{0647} \u{0645}\u{0645}\u{0633}\u{0648}\u{062D}")
        XCTAssertEqual(StatusLine.short("\u{8868}\u{9762}\u{3092}\u{30B9}\u{30AD}\u{30E3}\u{30F3}\u{3057}\u{307E}\u{3057}\u{305F}\u{3002}\u{88CF}\u{9762}\u{3092}\u{30B9}\u{30AD}\u{30E3}\u{30F3}\u{3057}\u{3066}\u{304F}\u{3060}\u{3055}\u{3044}\u{3002}"),
                       "\u{8868}\u{9762}\u{3092}\u{30B9}\u{30AD}\u{30E3}\u{30F3}\u{3057}\u{307E}\u{3057}\u{305F}")
    }

    func test_short_countsTheEnglishWords_whateverTheLanguage() {
        let table: [String: String] = ["feeder used|after another fact": "besleyici kullan\u{0131}ld\u{0131} bu sefer l\u{00FC}tfen not al\u{0131}n"]
        L10n.withTable(table, language: "tr") {
            let detail = StatusDetail(head: .pagesAdded(3, queue: 3, blank: 0, split: 0), warnings: [.feederUsed])
            XCTAssertEqual(StatusLine.short("Added 3 pages \u{2014} 3 in queue.", detail),
                           "3 pages added \u{00B7} besleyici kullan\u{0131}ld\u{0131} bu sefer l\u{00FC}tfen not al\u{0131}n")
        }
    }

    func test_words_countsTokensWithALetterOrDigit() {
        XCTAssertEqual(StatusLine.words("Ready \u{2014} Demo Scanner"), 3)
        XCTAssertEqual(StatusLine.words("6 pages added \u{00B7} 1 blank"), 5)
        XCTAssertEqual(StatusLine.words(" \u{2014} \u{00B7} "), 0)
    }

    func test_saved_withASettingChangedForTheScanner_keepsTheWarning() {
        // Capabilities read after a scan saved at once add their note to "Saved …".
        var high = ScanSettings()
        high.resolution = 1200
        let notes = SettingsAdapter.adapt(high, to: ScannerCapabilities(supportedResolutions: [300, 600])).notes
        let message = "Saved Scan 2026-10-20 1.pdf (412 KB) " + notes.map(\.message).joined(separator: " ")
        let detail = StatusDetail(head: .saved, warnings: notes.map(\.warning), body: "Saved Scan 2026-10-20 1.pdf (412 KB)")
        XCTAssertEqual(StatusLine.warnings(detail), ["600 dpi used"])
        XCTAssertEqual(StatusLine.shown(message, detail, deviceName: nil, reviewShown: false, savedShown: true), "Saved \u{00B7} 600 dpi used")
        XCTAssertEqual(StatusLine.short(message, detail), "Saved \u{00B7} 600 dpi used")
        // Without a note, just the head.
        let plain = StatusDetail(head: .saved)
        XCTAssertEqual(StatusLine.warnings(plain), [])
        XCTAssertEqual(StatusLine.shown("Saved Scan 2026-10-20 1.pdf (412 KB)", plain, deviceName: nil, reviewShown: false, savedShown: true), "Saved")
        // Too many to fit with the head: the warnings win, as on any other line.
        var everything = ScanSettings()
        everything.source = .flatbed
        everything.duplex = .both
        everything.paperSize = .legal
        everything.resolution = 600
        let small = ScannerCapabilities(supportedResolutions: [300], sources: [.documentFeeder],
                                        feederSizeInches: CGSize(width: 8.5, height: 11))
        let all = SettingsAdapter.adapt(everything, to: small).notes
        let many = "Saved Scan 2026-10-20 1.pdf (412 KB) " + all.map(\.message).joined(separator: " ")
        let manyDetail = StatusDetail(head: .saved, warnings: all.map(\.warning))
        let shown = StatusLine.shown(many, manyDetail, deviceName: nil, reviewShown: false, savedShown: true)
        XCTAssertEqual(StatusLine.short(many, manyDetail), shown)
        XCTAssertTrue((1...StatusLine.maxWords).contains(StatusLine.words(shown)))
    }

    func test_shown_isEmptyUnderAReview_andSavedWhileTheSavedFilesShow() {
        let found = StatusDetail(head: .found(3, .photo))
        XCTAssertEqual(StatusLine.shown("Found 3 photos.", found, deviceName: "Demo Scanner", reviewShown: true, savedShown: false), "")
        XCTAssertEqual(StatusLine.shown("Back scanned. Check the sides, then save.", StatusDetail(), deviceName: "Demo Scanner",
                                        reviewShown: true, savedShown: false), "")
        XCTAssertEqual(StatusLine.shown("Saved 3-page PDF: Scan 2026-10-20 1.pdf (497.7 KB)", StatusDetail(head: .saved), deviceName: nil,
                                        reviewShown: false, savedShown: true), "Saved")
        XCTAssertEqual(StatusLine.shown("Saved 3 photos to /Users/me/files", StatusDetail(head: .savedFiles(3, .photo)), deviceName: nil,
                                        reviewShown: false, savedShown: true), "Saved")
        // Not about a save: the short line, whatever the saved files' actions.
        XCTAssertEqual(StatusLine.shown("Added 1 page \u{2014} 3 in queue. Scan more or Save PDF.",
                                        StatusDetail(head: .pagesAdded(1, queue: 3, blank: 0, split: 0)), deviceName: nil,
                                        reviewShown: false, savedShown: true), "Page 3 added")
        XCTAssertEqual(StatusLine.shown("Ready for \u{201C}Photos\u{201D}.", StatusDetail(head: .readyForTask), deviceName: "Demo Scanner",
                                        reviewShown: false, savedShown: false), "Ready \u{2014} Demo Scanner")
    }
}
