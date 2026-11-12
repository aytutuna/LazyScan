#if os(iOS)
import CoreGraphics
import Foundation
import SwiftUI
import XCTest
@testable import LazyScanIOS
@testable import LazyScanKit
import LazyScanModel

// The Options pages, the file name editor and the iPad's layout without a screen (I15): the pages and the
// values on their rows, built on the shared InspectorSections, the adjustments' sliders, the naming editor's parts, example and problems, the sidebar's width rule, the
// keyboard shortcuts, moving a page of the strip by dragging it, a dropped file, and the save folder (I3:
// a folder picked in Files kept as a bookmark, the app's folder moved with the container).

/// A page of the test's own, its own every time.
private func settingsPage() -> ScannedPage {
    let context: CGContext = ImportTestSupport.context(width: 30, height: 40)
    context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 30, height: 40))
    return ScannedPage(image: context.makeImage()!, dpi: 60, colorMode: .color)
}

final class IOSSettingsTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = try ImportTestSupport.makeFolder("settings")
    }

    override func tearDownWithError() throws {
        if let folder {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    // MARK: The Options pages

    func test_optionsPages_followTheTaskAndTheTab() {
        let document: ScanSettings = ScanSettings()
        XCTAssertEqual(IOSOptionsPage.listed(document, camera: false, pageCount: 0, photoSizes: 0),
                       [.saveAs, .look, .pages, .separate, .fileName, .afterSaving, .scanner])
        // The camera measures its own pages: no Scanner; Camera only where it offers more than one photo size.
        XCTAssertEqual(IOSOptionsPage.listed(document, camera: true, pageCount: 0, photoSizes: 1),
                       [.saveAs, .look, .pages, .separate, .fileName, .afterSaving])
        XCTAssertEqual(IOSOptionsPage.listed(document, camera: true, pageCount: 0, photoSizes: 3),
                       [.saveAs, .look, .pages, .separate, .fileName, .afterSaving, .camera])

        // Pictures are not pages to cut into documents.
        let photos: ScanSettings = TaskCatalog.apply(.photos, to: ScanSettings())
        XCTAssertEqual(IOSOptionsPage.listed(photos, camera: false, pageCount: 0, photoSizes: 0),
                       [.saveAs, .look, .fileName, .afterSaving, .scanner])
        let receipts: ScanSettings = TaskCatalog.apply(.receipt, to: ScanSettings())
        XCTAssertEqual(IOSOptionsPage.listed(receipts, camera: false, pageCount: 0, photoSizes: 0),
                       [.saveAs, .look, .fileName, .afterSaving, .scanner])
        // The ID card is saved from its review: nothing to do after saving.
        let idCard: ScanSettings = TaskCatalog.apply(.idCard, to: ScanSettings())
        XCTAssertEqual(IOSOptionsPage.listed(idCard, camera: false, pageCount: 0, photoSizes: 0),
                       [.saveAs, .look, .fileName, .scanner])
        let book: ScanSettings = TaskCatalog.apply(.book, to: ScanSettings())
        let bookPages: [IOSOptionsPage] = IOSOptionsPage.listed(book, camera: true, pageCount: 0, photoSizes: 0)
        XCTAssertTrue(bookPages.contains(.pages))
        XCTAssertTrue(bookPages.contains(.separate), "The queue can be split")

        XCTAssertEqual(IOSOptionsPage.more, [.presets, .computer, .help])
    }

    func test_optionsPages_haveTheirOwnIdentifiersAndTitles() {
        XCTAssertEqual(IOSOptionsPage.saveAs.identifier, "options.page.saveAs")
        XCTAssertEqual(IOSOptionsPage.afterSaving.identifier, "options.page.afterSaving")
        XCTAssertEqual(IOSOptionsPage.saveAs.title, "Save as")
        XCTAssertEqual(IOSOptionsPage.separate.title, "Separate documents")
        XCTAssertEqual(IOSOptionsPage.fileName.title, "File name and folder")
        XCTAssertEqual(IOSOptionsPage.afterSaving.title, "After saving")
        XCTAssertEqual(IOSOptionsPage.computer.title, "My computer")
        XCTAssertEqual(IOSOptionsPage.help.title, "Help and about")
        var seen: Set<String> = []
        let pages: [IOSOptionsPage] = [.saveAs, .look, .pages, .separate, .fileName, .afterSaving, .scanner, .camera,
                                       .shareNow, .presets, .computer, .help, .about, .licences]
        for page in pages {
            XCTAssertFalse(page.title.isEmpty)
            seen.insert(page.identifier)
        }
        XCTAssertEqual(seen.count, pages.count)
    }

    func test_optionsRows_saveAs_showsTheFormatSaved() {
        XCTAssertEqual(IOSOptionsPage.saveAsValue(ScanSettings()), "PDF \u{00B7} Standard")
        // The Text kind's screen saves its page as a picture whatever format was picked before.
        var text: ScanSettings = TaskCatalog.apply(.quickScan, to: ScanSettings())
        text.format = .pdf
        XCTAssertEqual(IOSOptionsPage.saveAsValue(text), "JPEG")
        var word: ScanSettings = ScanSettings()
        word.format = .word
        XCTAssertEqual(IOSOptionsPage.saveAsValue(word), "Word")
        var locked: ScanSettings = ScanSettings()
        locked.output.protect = true
        XCTAssertEqual(IOSOptionsPage.saveAsValue(locked), "PDF \u{00B7} Standard \u{00B7} Password on")
        locked.output.protect = false
        locked.output.archival = true
        XCTAssertEqual(IOSOptionsPage.saveAsValue(locked), "PDF \u{00B7} Standard \u{00B7} PDF/A")
        // An ID card is a PDF or a picture, never Word.
        var idCard: ScanSettings = TaskCatalog.apply(.idCard, to: ScanSettings())
        idCard.format = .word
        XCTAssertEqual(IOSOptionsPage.saveAsValue(idCard), "PDF \u{00B7} Standard")
    }

    func test_optionsRows_look_nameTheFilterOnTheCamera_andWhatIsAdjusted() {
        var s: ScanSettings = ScanSettings()
        XCTAssertEqual(IOSOptionsPage.lookValue(s, camera: true), IOSShell.drawerFilter(s).label)
        XCTAssertEqual(IOSOptionsPage.lookValue(s, camera: false), InspectorSections.adjustmentsSummary(s.adjustments))
        s = IOSShell.settingDrawerFilter(.grayscale, in: s)
        XCTAssertTrue(IOSOptionsPage.lookValue(s, camera: true).hasPrefix(CaptureFilter.grayscale.label))
        s.adjustments = IOSAdjustment.brightness.setting(30, in: s.adjustments)
        XCTAssertEqual(IOSOptionsPage.lookValue(s, camera: true), CaptureFilter.grayscale.label + " \u{00B7} Edited")
        XCTAssertEqual(IOSOptionsPage.lookValue(s, camera: false), "Edited")
        // The kinds that keep no pages have no filters, only the adjustments.
        var card: ScanSettings = TaskCatalog.apply(.idCard, to: ScanSettings())
        card.adjustments = IOSAdjustment.brightness.setting(30, in: card.adjustments)
        XCTAssertEqual(IOSOptionsPage.lookValue(card, camera: true), "Edited")
    }

    func test_optionsRows_pages_inCameraMode_countOnlyWhatRunsOnTheCamerasPages() {
        // The camera's pages are cut along their corners already: never cropped or straightened.
        var cut: ScanSettings = ScanSettings()
        cut.document.autoCrop = true
        cut.document.autoStraighten = true
        XCTAssertEqual(IOSOptionsPage.pagesValue(cut, camera: true), "")
        XCTAssertEqual(IOSOptionsPage.pagesValue(cut, camera: false), "Crop \u{00B7} Straighten")

        // Facing pages are split only from spreads taken whole (the Book kind's Whole spread).
        var book: ScanSettings = TaskCatalog.apply(.book, to: ScanSettings())
        XCTAssertEqual(IOSOptionsPage.pagesValue(book, camera: false), "Straighten \u{00B7} Upright +1")
        XCTAssertEqual(IOSOptionsPage.pagesValue(book, camera: true), "Upright")
        book.taskOptions.cameraSpreads = true
        XCTAssertEqual(IOSOptionsPage.pagesValue(book, camera: true), "Upright \u{00B7} Facing pages")
    }

    func test_optionsRows_separate_saysOnOffOrHowTheQueueIsSplit() {
        var s: ScanSettings = ScanSettings()
        XCTAssertEqual(IOSOptionsPage.separateValue(s), "Off")
        XCTAssertEqual(IOSOptionsPage.separateValue(IOSShell.settingSeparate(true, in: s)), "On")
        s.document.splitMode = .sheetCount
        s.document.splitSheetCount = 3
        XCTAssertEqual(IOSOptionsPage.separateValue(s), InspectorSections.splitSummary(s.document))
        s.document.splitMode = .blankSheet
        XCTAssertEqual(IOSOptionsPage.separateValue(s), "Blank sheets")
    }

    @MainActor
    func test_splitChoice_forTheDocumentKind_isSeparateDocumentsTurnedOnAndOff() {
        let state: AppState = ImportTestSupport.makeState(in: folder)
        state.settings = TaskCatalog.apply(.document, to: state.settings)
        IOSShell.setSplit(.barcode, in: state)
        XCTAssertTrue(IOSShell.separatesDocuments(state.settings))
        XCTAssertEqual(state.settings.document.splitMode, .barcode)
        XCTAssertEqual(state.settings.task, .batch, "The switch's task and feeder come with the choice")
        XCTAssertEqual(state.settings.source, .documentFeeder)

        IOSShell.setSplit(.sheetCount, in: state)
        XCTAssertFalse(IOSShell.separatesDocuments(state.settings))
        XCTAssertEqual(state.settings.document.splitMode, .sheetCount)
        XCTAssertEqual(state.settings.task, .document)
        XCTAssertEqual(state.settings.source, .documentFeeder, "A stack on the feeder stays there")

        IOSShell.setSplit(.separatorSheet, in: state)
        IOSShell.setSplit(.none, in: state)
        XCTAssertEqual(state.settings.document.splitMode, SplitMode.none)
        XCTAssertEqual(state.settings.source, .flatbed, "No split is one document on the glass")

        // Other kinds only set the split.
        state.settings = TaskCatalog.apply(.book, to: state.settings)
        IOSShell.setSplit(.separatorSheet, in: state)
        XCTAssertEqual(state.settings.document.splitMode, .separatorSheet)
        XCTAssertEqual(state.settings.task, .book)
    }

    func test_pdfChoices_aQueueSavedAsPictures_writesNoPDF() {
        var pictures: ScanSettings = ScanSettings()
        pictures.format = .jpeg
        pictures.output.alsoSaveText = true
        XCTAssertTrue(InspectorSections.shown(pictures).contains(InspectorSections.archive), "The desktop saves a PDF")
        XCTAssertFalse(IOSSettingsSections.writesPDF(pictures))
        XCTAssertFalse(IOSSettingsSections.textApplies(pictures))
    }

    func test_photosAndReceipts_showTheFormatOptionsSaves_whateverItIs() {
        var receipts: ScanSettings = TaskCatalog.apply(.receipt, to: ScanSettings())
        receipts.format = .word
        XCTAssertEqual(IOSSettingsSections.shownFormat(receipts), .word)
        XCTAssertFalse(IOSSettingsSections.writesPDF(receipts))
        XCTAssertFalse(IOSSettingsSections.textApplies(receipts))
        // The desktop saves receipts as a PDF or a picture.
        XCTAssertEqual(InspectorSections.shownFormat(receipts), .pdf)

        var photos: ScanSettings = TaskCatalog.apply(.photos, to: ScanSettings())
        XCTAssertEqual(IOSSettingsSections.shownFormat(photos), .jpeg)
        photos.format = .pdf
        XCTAssertEqual(IOSSettingsSections.shownFormat(photos), .pdf)
        XCTAssertTrue(IOSSettingsSections.writesPDF(photos))
        XCTAssertEqual(IOSShell.settingRestore(true, in: photos).format, .pdf)
        XCTAssertEqual(IOSShell.settingRestore(false, in: photos).format, .pdf)
    }

    func test_textFormats_areOfferedWhenThePagesHaveTextOrSearchableReadsThem_orOneIsChosen() {
        var photos: ScanSettings = TaskCatalog.apply(.photos, to: ScanSettings())
        photos.pdfSearchable = false
        photos.format = .jpeg
        XCTAssertFalse(IOSSettingsSections.offersTextFormats(photos, pagesHaveText: false))
        XCTAssertTrue(IOSSettingsSections.offersTextFormats(photos, pagesHaveText: true))
        photos.pdfSearchable = true
        XCTAssertTrue(IOSSettingsSections.offersTextFormats(photos, pagesHaveText: false))
        photos.pdfSearchable = false
        photos.format = .word
        XCTAssertTrue(IOSSettingsSections.offersTextFormats(photos, pagesHaveText: false))
    }

    func test_output_showsTheFormatSaved_aPictureForText_aPDFForAnIdCardInWord() {
        // The Text kind's screen saves its page as a picture whatever format was picked before.
        var text: ScanSettings = TaskCatalog.apply(.quickScan, to: ScanSettings())
        text.format = .pdf
        XCTAssertEqual(InspectorSections.shownFormat(text), .pdf, "The desktop saves the format chosen")
        XCTAssertEqual(IOSSettingsSections.shownFormat(text), .jpeg)
        XCTAssertFalse(IOSSettingsSections.writesPDF(text))
        XCTAssertFalse(IOSSettingsSections.textApplies(text))

        // With Collect pages on, its pages go to the queue and are saved in the format picked.
        text.documentMultiPage = true
        XCTAssertEqual(IOSSettingsSections.shownFormat(text), .pdf)
        XCTAssertTrue(IOSSettingsSections.writesPDF(text))
        XCTAssertTrue(IOSSettingsSections.textApplies(text))

        var idCard: ScanSettings = TaskCatalog.apply(.idCard, to: ScanSettings())
        idCard.format = .word
        XCTAssertEqual(InspectorSections.shownFormat(idCard), .pdf)
        XCTAssertEqual(IOSSettingsSections.shownFormat(idCard), .pdf)
        XCTAssertTrue(IOSSettingsSections.writesPDF(idCard))
    }

    // MARK: Adjustments

    func test_adjustments_mapTheSlidersOntoTheSettings() {
        let neutral: AdjustmentSettings = AdjustmentSettings()
        for adjustment in IOSAdjustment.allCases {
            XCTAssertEqual(adjustment.amount(neutral), 0, accuracy: 1e-9, adjustment.label)
            let changed: AdjustmentSettings = adjustment.setting(37, in: neutral)
            XCTAssertEqual(adjustment.amount(changed), 37, accuracy: 1e-9, adjustment.label)
        }
        XCTAssertEqual(IOSAdjustment.brightness.setting(100, in: neutral).brightness, 1, accuracy: 1e-9)
        XCTAssertEqual(IOSAdjustment.contrast.setting(100, in: neutral).contrast, 4, accuracy: 1e-9)
        XCTAssertEqual(IOSAdjustment.contrast.setting(-100, in: neutral).contrast, 0.25, accuracy: 1e-9)
        XCTAssertEqual(IOSAdjustment.saturation.setting(-100, in: neutral).saturation, 0, accuracy: 1e-9)
        XCTAssertEqual(IOSAdjustment.sharpness.setting(100, in: neutral).sharpness, 2, accuracy: 1e-9)
        XCTAssertEqual(IOSAdjustment.amountText(12.4), "+12")
        XCTAssertEqual(IOSAdjustment.amountText(-5), "-5")
        XCTAssertEqual(IOSAdjustment.amountText(0.3), "0")

        var edited: AdjustmentSettings = IOSAdjustment.brightness.setting(40, in: neutral)
        edited.descreen = true
        XCTAssertFalse(IOSAdjustment.isNeutral(edited))
        let reset: AdjustmentSettings = IOSAdjustment.neutral(edited)
        XCTAssertTrue(IOSAdjustment.isNeutral(reset))
        XCTAssertTrue(reset.descreen, "Reset puts the sliders back, not the switches")
    }

    func test_scannerRows_needASelectedScanner_andListTheSourceChosen() {
        XCTAssertEqual(IOSSettingsSections.scannerRowsReason(selected: nil), IOSSettingsText.noScannerReason)
        // Shown in printer mode, which the app never names.
        XCTAssertFalse(IOSSettingsText.noScannerReason.contains("printer mode"))
        XCTAssertNil(IOSSettingsSections.scannerRowsReason(selected: "escl:office"))
        // Both sides set up for the camera chose the feeder before the scanner's sources are known.
        XCTAssertEqual(IOSSettingsSections.offeredSources(nil, chosen: .documentFeeder), [.flatbed, .documentFeeder])
        XCTAssertEqual(IOSSettingsSections.offeredSources(nil, chosen: .flatbed), [.flatbed])
        let both = ScannerCapabilities(sources: [.flatbed, .documentFeeder])
        XCTAssertEqual(IOSSettingsSections.offeredSources(both, chosen: .documentFeeder), [.flatbed, .documentFeeder])
        // The lock's reason speaks of the phone, which has no Document mode.
        XCTAssertFalse(IOSSettingsText.idCardHeldReason.contains("Document mode"))
        XCTAssertFalse(IOSSettingsText.idCardHeldReason.contains("task"))
    }

    func test_scannerRows_lockTheSource_underIdCardBookAndText_andWhileACardIsHeld() {
        let sources: [ScanSource] = [.flatbed, .documentFeeder]
        XCTAssertEqual(IOSSettingsSections.sourceLockReason(task: .idCard, cardHeld: false, sources: sources),
                       "ID card is scanned on the flatbed. Pick Document to use the feeder.")
        XCTAssertEqual(IOSSettingsSections.sourceLockReason(task: .book, cardHeld: false, sources: sources),
                       "Book is scanned on the flatbed. Pick Document to use the feeder.")
        // Quick scan is the Text kind on the phone.
        XCTAssertEqual(IOSSettingsSections.sourceLockReason(task: .quickScan, cardHeld: false, sources: sources),
                       "Text is scanned on the flatbed. Pick Document to use the feeder.")
        // Document and Both sides leave it free, as do settings without a task.
        XCTAssertNil(IOSSettingsSections.sourceLockReason(task: .document, cardHeld: false, sources: sources))
        XCTAssertNil(IOSSettingsSections.sourceLockReason(task: .twoSided, cardHeld: false, sources: sources))
        XCTAssertNil(IOSSettingsSections.sourceLockReason(task: nil, cardHeld: false, sources: sources))
        // So does a scanner with only a flatbed, or one whose sources are not known yet: no feeder to pick.
        XCTAssertNil(IOSSettingsSections.sourceLockReason(task: .idCard, cardHeld: false, sources: [.flatbed]))
        let tasks: [ScanTask?] = [.idCard, .document, nil]
        for task in tasks {
            XCTAssertEqual(IOSSettingsSections.sourceLockReason(task: task, cardHeld: true, sources: sources),
                           IOSSettingsText.idCardHeldReason)
            XCTAssertEqual(IOSSettingsSections.sourceLockReason(task: task, cardHeld: true, sources: [.flatbed]),
                           IOSSettingsText.idCardHeldReason)
        }
    }

    func test_version_fromTheAppsInfo() {
        let info: [String: Any] = ["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "7"]
        XCTAssertEqual(IOSSettingsText.version(info), "Version 0.1.0 (7)")
        let noBuild: [String: Any] = ["CFBundleShortVersionString": "0.1.0"]
        XCTAssertEqual(IOSSettingsText.version(noBuild), "Version 0.1.0")
        XCTAssertEqual(IOSSettingsText.version(nil), "Version ?")
    }

    func test_licences_theTextsGoWithTheApp() {
        XCTAssertTrue(FastViTCornerModel.licence("DocAligner-LICENSE")?.contains("Apache License") == true)
        XCTAssertTrue(FastViTCornerModel.licence("ONNXRuntime-LICENSE")?.contains("MIT License") == true)
        XCTAssertNil(FastViTCornerModel.licence("Nowhere-LICENSE"))
    }

    // MARK: After saving

    func test_afterSave_runsTheCheckedActionsInOrder_sendingOnlyWhilePaired() throws {
        let suite: String = "IOSSettingsTests.afterSave"
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(IOSAfterSave.steps(defaults, paired: true, pictures: true), [], "Nothing checked at first")
        for action in IOSAfterSave.rows {
            defaults.set(true, forKey: action.key)
        }
        XCTAssertEqual(IOSAfterSave.steps(defaults, paired: true, pictures: true), [.send, .print, .email, .photos])
        XCTAssertEqual(IOSAfterSave.steps(defaults, paired: false, pictures: true), [.print, .email, .photos],
                       "No computer: skipped")
        XCTAssertEqual(IOSAfterSave.steps(defaults, paired: true, pictures: false), [.send, .print, .email],
                       "Not pictures: Photos is skipped")
        defaults.set(false, forKey: IOSAfterSave.print.key)
        XCTAssertEqual(IOSAfterSave.steps(defaults, paired: true, pictures: true), [.send, .email, .photos])
        XCTAssertEqual(IOSAfterSave.rows.map { (action: IOSAfterSave) -> String in action.label },
                       ["Email", "Print", "Send to computer", "Photos"])
        XCTAssertEqual(IOSAfterSave.print.label(lazyPrintInstalled: true), "Lazy Print")
        XCTAssertEqual(IOSAfterSave.print.label(lazyPrintInstalled: false), "Print")
        XCTAssertEqual(IOSAfterSave.email.label(lazyPrintInstalled: true), "Email")
    }

    func test_afterSave_saysWhenSendToPCsPagesWait() {
        let reason: String = CompanionText.notOnNetworkReason("Office PC")
        XCTAssertEqual(IOSAfterSave.notSentMessage(.unreachable(reason: reason), waiting: 1),
                       "Office PC was not found. Open Lazy Scan on it and check both are on the same Wi-Fi. The pages wait on this device and are sent once it answers.")
        XCTAssertEqual(IOSAfterSave.notSentMessage(.unreachable(reason: reason), waiting: 1, inFolder: 1),
                       "Office PC was not found. Open Lazy Scan on it and check both are on the same Wi-Fi. The document is in the cloud folder; the computer takes it from there.")
        XCTAssertEqual(IOSAfterSave.notSentMessage(.unreachable(reason: reason), waiting: 2, inFolder: 1),
                       "Office PC was not found. Open Lazy Scan on it and check both are on the same Wi-Fi. The pages wait on this device and are sent once it answers.",
                       "One of them waits on this device")
        XCTAssertEqual(IOSAfterSave.notSentMessage(.unpaired(byDesktop: "Office PC"), waiting: 2),
                       "This device is no longer paired with Office PC. The pages were not sent.")
        XCTAssertNil(IOSAfterSave.notSentMessage(.reachable(desktopName: "Office PC", queuedPages: 0), waiting: 1),
                     "The computer answered: what waits is on its way")
        XCTAssertNil(IOSAfterSave.notSentMessage(.unreachable(reason: reason), waiting: 0), "Nothing waits")
    }

    func test_afterSave_thenOffersTheKitsActions_inThePhonesWords() {
        XCTAssertEqual(IOSAfterSave.thenTitle, "Then")
        XCTAssertEqual(IOSAfterSave.emailInsteadReason, "Email is sent instead")
        var labels: [String] = []
        for action in AfterSaveAction.allCases {
            labels.append(IOSAfterSave.thenLabel(action))
        }
        XCTAssertEqual(labels, ["Do nothing", "Open", "Show in Files", "Share\u{2026}"])
        XCTAssertEqual(IOSAfterSave.thenLabel(.reveal), IOSSavedFiles.revealLabel)
        XCTAssertEqual(AfterSaveAction.reveal.label, "Show in folder", "The desktop's words stay")
        XCTAssertEqual(IOSAfterSave.thenHint(.open), "Open the file (several: show them in Files)")
        XCTAssertEqual(IOSAfterSave.thenHint(.reveal), "Show the files in the Files app")
        XCTAssertEqual(IOSAfterSave.thenHint(.share), AfterSaveAction.share.hint)
        XCTAssertEqual(IOSAfterSave.thenHint(AfterSaveAction.none), "Stay here")
    }

    // MARK: The file name

    @MainActor
    func test_namingEditor_putsTheTemplateInUse_showsTheNextName_andWhatIsWrong() {
        let state: AppState = ImportTestSupport.makeState(in: folder)
        let model: IOSNamingModel = IOSNamingModel(state: state)
        XCTAssertEqual(model.text, state.settings.namingTemplate)
        XCTAssertEqual(model.parts.count, 7)
        // The phone has no page strip to name a document in: its name comes from a QR sheet.
        let documentName: NamingToken? = model.parts.first(where: { (part: NamingToken) -> Bool in part.token == "{label}" })
        XCTAssertEqual(documentName?.help, "The document's name from its QR sheet")
        // And its Type is what the desktop calls the mode and the task.
        let labels: [String] = model.parts.map(\.label)
        XCTAssertFalse(labels.contains("Mode"))
        XCTAssertFalse(labels.contains("Task"))
        XCTAssertTrue(labels.contains("Type"))
        XCTAssertNil(model.problem)

        model.setText("Invoice {date}")
        XCTAssertEqual(state.settings.namingTemplate, "Invoice {date}")
        XCTAssertNil(model.problem)
        XCTAssertTrue(model.example.hasPrefix("Invoice "), model.example)
        XCTAssertTrue(model.example.hasSuffix(".pdf"), model.example)

        XCTAssertEqual(model.exampleName, String(model.example.dropLast(".pdf".count)))
        XCTAssertFalse(model.exampleName.contains("{"), model.exampleName)

        model.setText("   ")
        XCTAssertEqual(model.problem, NamingTokens.emptyProblem)
        XCTAssertEqual(state.settings.namingTemplate, "Invoice {date}", "A blank name keeps the last one in use")

        model.setText("Invoice {foo}")
        XCTAssertEqual(model.problem, "Unknown part {foo}")
        XCTAssertEqual(state.settings.namingTemplate, "Invoice {foo}")

        model.insert("{counter}")
        XCTAssertEqual(model.text, "Invoice {foo} {counter}")
        XCTAssertEqual(state.settings.namingTemplate, "Invoice {foo} {counter}")

        // The scan screen saves a picture a page as JPEGs.
        state.settings.format = .jpeg
        XCTAssertEqual(model.format, OutputFormat.jpeg)
        XCTAssertTrue(model.example.hasSuffix(".jpg"), model.example)

        model.reset()
        XCTAssertEqual(model.text, "Scan {date} {counter}")
        XCTAssertEqual(state.settings.namingTemplate, "Scan {date} {counter}")
    }

    // MARK: The iPad

    func test_layout_theSidebar_onlyOnARegularWidthOnAnIPad() {
        XCTAssertTrue(IOSLayout.usesSidebar(UserInterfaceSizeClass.regular, pad: true))
        XCTAssertFalse(IOSLayout.usesSidebar(UserInterfaceSizeClass.compact, pad: true))
        XCTAssertFalse(IOSLayout.usesSidebar(nil, pad: true))
        // A large iPhone turned sideways is regular too, and keeps the phone's layout.
        XCTAssertFalse(IOSLayout.usesSidebar(UserInterfaceSizeClass.regular, pad: false))
    }

    @MainActor
    func test_shortcuts_saveNewDocumentOptionsAndTheShutter() {
        XCTAssertEqual(IOSShortcuts.save.key, "s")
        XCTAssertTrue(IOSShortcuts.save.command)
        XCTAssertEqual(IOSShortcuts.newDocument.key, "n")
        XCTAssertTrue(IOSShortcuts.newDocument.command)
        XCTAssertEqual(IOSShortcuts.options.key, ",")
        XCTAssertTrue(IOSShortcuts.options.command)
        XCTAssertEqual(IOSShortcuts.shutter.key, " ")
        XCTAssertFalse(IOSShortcuts.shutter.command)
        var seen: Set<String> = []
        for shortcut in IOSShortcuts.all {
            XCTAssertFalse(shortcut.title.isEmpty)
            seen.insert("\(shortcut.command)-\(shortcut.key)")
        }
        XCTAssertEqual(seen.count, IOSShortcuts.all.count, "No two actions share a key")
        XCTAssertEqual(IOSShortcuts.save.keyboardShortcut.modifiers, EventModifiers.command)
        XCTAssertEqual(IOSShortcuts.shutter.keyboardShortcut.modifiers, EventModifiers())
    }

    @MainActor
    func test_pageDrop_aPageDraggedOntoAnother_takesItsPlace() {
        let state: AppState = ImportTestSupport.makeState(in: folder)
        let pages: [ScannedPage] = [settingsPage(), settingsPage(), settingsPage(), settingsPage()]
        let a: UUID = pages[0].id
        let b: UUID = pages[1].id
        let c: UUID = pages[2].id
        let d: UUID = pages[3].id
        XCTAssertEqual(IOSPageDrop.offset(moving: a, onto: c, in: [a, b, c, d]), 2)
        XCTAssertEqual(IOSPageDrop.offset(moving: d, onto: b, in: [a, b, c, d]), -2)
        XCTAssertNil(IOSPageDrop.offset(moving: a, onto: a, in: [a, b, c, d]))
        XCTAssertNil(IOSPageDrop.offset(moving: UUID(), onto: a, in: [a, b, c, d]))
        XCTAssertEqual(IOSPageDrop.pageID(a.uuidString), a)
        XCTAssertNil(IOSPageDrop.pageID("not a page"))

        state.scannedPages = pages
        XCTAssertTrue(IOSPageDrop.move(a, onto: c, in: state))
        XCTAssertEqual(order(state), [b, c, a, d])
        XCTAssertTrue(IOSPageDrop.move(d, onto: b, in: state))
        XCTAssertEqual(order(state), [d, b, c, a])
        XCTAssertFalse(IOSPageDrop.move(c, onto: c, in: state))
        XCTAssertFalse(IOSPageDrop.move(UUID(), onto: c, in: state))
        XCTAssertEqual(order(state), [d, b, c, a])
    }

    @MainActor
    func test_pageSelection_movesThePagesPicked_keepingTheirOrder() {
        let state: AppState = ImportTestSupport.makeState(in: folder)
        let pages: [ScannedPage] = [settingsPage(), settingsPage(), settingsPage(), settingsPage(), settingsPage()]
        let a: UUID = pages[0].id
        let b: UUID = pages[1].id
        let c: UUID = pages[2].id
        let d: UUID = pages[3].id
        let e: UUID = pages[4].id
        XCTAssertEqual(IOSPageSelection.ordered([e, b, d], in: pages), [b, d, e])

        state.scannedPages = pages
        IOSPageSelection.move([d, b], toStart: true, in: state)
        XCTAssertEqual(order(state), [b, d, a, c, e])
        IOSPageSelection.move([b, a], toStart: false, in: state)
        XCTAssertEqual(order(state), [d, c, e, b, a])
        IOSPageSelection.move([d, c], toStart: true, in: state)
        XCTAssertEqual(order(state), [d, c, e, b, a])
    }

    func test_pageSelection_writesThePagesPicked_namedByTheirNumber() async throws {
        let pages: [ScannedPage] = [settingsPage(), settingsPage(), settingsPage()]
        let urls: [URL] = try await IOSPageSelection.writeImages([pages[2].id, pages[0].id], of: pages, format: .jpeg,
                                                                 jpegQuality: 0.9)
        XCTAssertEqual(urls.map(\.lastPathComponent), ["Page 1.jpg", "Page 3.jpg"])
        for url in urls {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), url.lastPathComponent)
        }
    }

    func test_droppedFiles_comeInByTheirKind() {
        let pdf: IOSImportItem = IOSDroppedFile(data: Data("%PDF-1.4".utf8), kind: .pdf).item
        XCTAssertEqual(pdf.kind, IOSImportItem.Kind.pdf)
        XCTAssertEqual(pdf.name, "Dropped PDF")
        let picture: IOSImportItem = IOSDroppedFile(data: Data([0x89, 0x50]), kind: .image).item
        XCTAssertEqual(picture.kind, IOSImportItem.Kind.image)
        XCTAssertEqual(picture.name, "Dropped picture")
    }

    // MARK: The save folder

    @MainActor
    func test_saveFolder_aBookmarkThatDoesNotOpenNow_isKept_andTheSaveGoesToTheAppsFolder() throws {
        let state: AppState = ImportTestSupport.makeState(in: folder)
        state.resolveDestinationBookmark = { (bookmark: Data) -> (folder: URL, bookmark: Data)? in
            IOSSaveFolder.resolve(bookmark)
        }
        let unplugged: String = folder.appendingPathComponent("Unplugged", isDirectory: true).path
        state.settings.destinationBookmark = Data("not a bookmark".utf8)
        state.settings.destinationPath = unplugged
        XCTAssertNil(state.openBookmarkedFolder())
        XCTAssertEqual(state.settings.destinationBookmark, Data("not a bookmark".utf8))
        XCTAssertEqual(state.settings.destinationPath, unplugged)
        XCTAssertNil(state.errorMessage)

        XCTAssertEqual(try state.destinationDirectory().path, ScanSettings.defaultDestinationPath)
        XCTAssertEqual(state.errorMessage,
                       "The save folder could not be opened, so this save went to the app's folder.")
        XCTAssertEqual(state.settings.destinationBookmark, Data("not a bookmark".utf8))
        XCTAssertEqual(state.settings.destinationPath, unplugged)
        XCTAssertEqual(IOSSavedFiles.folder(state.settings).path, unplugged)
        // The list shows where that save went, not the folder nobody can reach.
        XCTAssertEqual(IOSSavedFiles.shownFolder(state.settings).path, ScanSettings.defaultDestinationPath)
    }

    @MainActor
    func test_saveFolder_aPickedFolder_isBookmarked_andSavesGoThere() throws {
        let picked: URL = folder.appendingPathComponent("Picked", isDirectory: true)
        try FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        let state: AppState = ImportTestSupport.makeState(in: folder)
        state.resolveDestinationBookmark = { (bookmark: Data) -> (folder: URL, bookmark: Data)? in
            IOSSaveFolder.resolve(bookmark)
        }
        state.settings = try IOSSaveFolder.choosing(picked, in: state.settings)
        XCTAssertNotNil(state.settings.destinationBookmark)
        XCTAssertEqual(state.settings.destinationPath, picked.path)
        guard let opened = state.openBookmarkedFolder() else {
            throw XCTSkip("A bookmark of a temporary folder does not resolve here.")
        }
        XCTAssertEqual(opened.resolvingSymlinksInPath().path, picked.resolvingSymlinksInPath().path)
        XCTAssertEqual(try state.destinationDirectory().resolvingSymlinksInPath().path,
                       picked.resolvingSymlinksInPath().path)
        XCTAssertNotNil(state.settings.destinationBookmark)

        let back: ScanSettings = IOSSaveFolder.appFolder(state.settings)
        XCTAssertNil(back.destinationBookmark)
        XCTAssertEqual(back.destinationPath, ScanSettings.defaultDestinationPath)
    }

    @MainActor
    func test_saveFolder_words_theAppsFolderOfAnEarlierInstall_andShowInFiles() throws {
        XCTAssertEqual(IOSSettingsText.saveToLabel, "Save to")
        XCTAssertEqual(IOSSettingsText.chooseFolderLabel, "Choose\u{2026}")
        XCTAssertEqual(IOSSettingsText.appFolderLabel, "Use app folder")

        let documents: URL = try XCTUnwrap(IOSShell.documentsFolder)
        var settings: ScanSettings = ScanSettings()
        settings.destinationPath =
            "/var/mobile/Containers/Data/Application/7A1F2E3D-4C5B-4A69-8778-96A5B4C3D2E1/Documents/Lazy Scan"
        XCTAssertEqual(IOSSavedFiles.folder(settings).path, documents.appendingPathComponent("Lazy Scan").path)
        let otherApp: String =
            "/private/var/mobile/Containers/Data/Application/0B9C8D7E-6F5A-4B3C-9D2E-1F0A9B8C7D6E/Documents/Scans"
        settings.destinationPath = otherApp
        settings.destinationBookmark = Data("picked".utf8)
        XCTAssertEqual(IOSSavedFiles.folder(settings).path, otherApp)
        let actions = IOSFileActions(pasteboard: nil, openSystemURL: { (_: URL) -> Void in })
        let made: AppState = AppState.makeForIOS(options: IOSLaunchOptions(demoScannerOnly: true), fileActions: actions)
        XCTAssertEqual(made.documentsFolder, documents)
        XCTAssertNotNil(made.resolveDestinationBookmark)

        let iCloud = URL(fileURLWithPath: "/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Scans",
                         isDirectory: true)
        XCTAssertEqual(IOSFileActions.filesAppURL(for: [iCloud])?.absoluteString,
                       "shareddocuments:///private/var/mobile/Library/Mobile%20Documents/com~apple~CloudDocs/Scans/")
    }

    @MainActor
    private func order(_ state: AppState) -> [UUID] {
        var ids: [UUID] = []
        for page in state.scannedPages {
            ids.append(page.id)
        }
        return ids
    }
}
#endif
