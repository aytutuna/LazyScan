import XCTest

// Walks the app's main screens on the demo scanner and keeps a screenshot of each, named by screen, so
// CI's ios-screenshots artifact shows what the screens look like after a change: camera mode (the
// Simulator's viewfinder says there is no camera), its kinds with Receipts picked and its drawer on
// Export, then printer mode, its Scanner sheet, two scanned pages in the page grid (and selecting, one
// ticked), Save's menu and the Export sheet, Settings with My computer and Presets, and the library from
// camera mode, with Troubleshooter and the file name's editor from Settings and a book page's split sheet;
// and, on runs of their own, a photo of a page in the page viewer with its filters, the ID card's review
// with its menus and the copy screen, a batch's and a two-sided sheet's pages, and the password sheet. The
// corner editor's Retake and the ID card guide only come with a camera, which the Simulator does not have.
// A screen whose button is not there is left out rather than failed, so the walk stays green while the
// screens change; a "skipped-" screenshot shows what was on screen instead.

final class ScreenshotTests: XCTestCase {
    /// CI's pseudo-language run sets LAZYSCAN_PSEUDO: the app then starts in qps-ploc, where every
    /// string that went through the lookup is wrapped in [!! !!].
    private static let language: [String] = (ProcessInfo.processInfo.environment["LAZYSCAN_PSEUDO"] == nil
        ? [] : ["-AppleLanguages", "(qps-ploc)"]) + direction

    /// The RTL run sets LAZYSCAN_RTL: the English bundle laid out right to left, which -AppleLanguages (ar)
    /// cannot do before Arabic has a lproj.
    private static let direction: [String] = ProcessInfo.processInfo.environment["LAZYSCAN_RTL"] == nil
        ? [] : ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"]

    @MainActor
    func test_mainScreens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoScanner"] + Self.language
        app.launch()

        // The mode is kept from run to run: the walk starts in camera mode.
        app.switchToCamera()
        Thread.sleep(forTimeInterval: 1)
        shot("01-camera")
        cameraScreens(app)
        printerScreens(app)
        settingsScreens(app)
        libraryScreens(app)
    }

    /// A photo of a page brought in through the corner editor, opened from the page grid in the page viewer
    /// with its filters shown: the page as the camera saw it (Original) and the other filters beside it.
    @MainActor
    func test_pageViewer() throws {
        let app: XCUIApplication = try launchImporting("document-photo", "png", task: "document")
        guard useCorners(app, for: "06a-corners") else { return }
        app.openPages(1)
        guard tapIfThere(app, "page.1", for: "06b-page-viewer"),
              tapIfThere(app, "viewer.filters", for: "06b-page-viewer") else { return }
        if element(app, "filter.original").waitForExistence(timeout: 10) {
            // The small pictures of each filter are made off the main thread.
            Thread.sleep(forTimeInterval: 3)
            shot("06b-page-viewer")
        } else {
            shot("skipped-06b-page-viewer")
        }
        if tapIfThere(app, "viewer.text", for: "06c-page-text") {
            let done: XCUIElement = element(app, "text.done")
            if done.waitForExistence(timeout: 10) {
                // The text is read off the main thread: the shot once it is in, or once none was found.
                let ids: [String] = ["text.body", "text.none"]
                let read: XCUIElement = app.descendants(matching: .any)
                    .matching(NSPredicate(format: "identifier IN %@", ids)).firstMatch
                _ = read.waitForExistence(timeout: 60)
                shot("06c-page-text")
                done.tap()
                waitUntilGone(done)
            } else {
                shot("skipped-06c-page-text")
            }
        }
        if tapIfThere(app, "viewer.done", for: "viewer-closed") {
            waitUntilGone(element(app, "viewer.done"))
        }
    }

    /// An ID card from two imported photos: its review, the Paper and Save as menus open, the lower part with
    /// the page both sides go on, and Discard's question. Nothing is saved.
    @MainActor
    func test_reviewIdCard() throws {
        let app: XCUIApplication = try launchImporting("document-photo", "png", count: 2, task: "idCard")
        guard useCorners(app, for: "15-idcard-corners"), useCorners(app, for: "15-idcard-corners", shooting: false) else { return }
        let save: XCUIElement = element(app, "idcard.save")
        guard save.waitForExistence(timeout: 180) else {
            shot("skipped-15-idcard-review")
            return
        }
        // The sides' pictures and the page are drawn off the main thread.
        Thread.sleep(forTimeInterval: 3)
        shot("15-idcard-review")
        for (id, screen) in [("idcard.paper", "15a-idcard-paper-menu"), ("idcard.format", "15b-idcard-format-menu")] {
            if tapIfThere(app, id, for: screen) {
                Thread.sleep(forTimeInterval: 1)
                shot(screen)
                // A tap off the menu closes it: on the title, which is no button.
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.09)).tap()
                Thread.sleep(forTimeInterval: 1)
            }
        }
        app.swipeUp()
        Thread.sleep(forTimeInterval: 1)
        shot("15c-idcard-review-lower")
        if tapIfThere(app, "idcard.discard", for: "15d-idcard-discard") {
            let confirm: XCUIElement = element(app, "idcard.confirmDiscard")
            if confirm.waitForExistence(timeout: 5) {
                Thread.sleep(forTimeInterval: 1)
                shot("15d-idcard-discard")
                confirm.tap()
                waitUntilGone(confirm)
            } else {
                shot("skipped-15d-idcard-discard")
            }
        }
        backToDocument(app)
    }

    /// A photo brought in as a copy: the copy screen with what it prints, then Discard.
    @MainActor
    func test_reviewCopy() throws {
        let app: XCUIApplication = try launchImporting("document-photo", "png", task: "copy")
        guard useCorners(app, for: "16-copy-corners") else { return }
        let printCopy: XCUIElement = element(app, "copy.print")
        guard printCopy.waitForExistence(timeout: 180) else {
            shot("skipped-16-copy")
            return
        }
        Thread.sleep(forTimeInterval: 3)
        shot("16-copy")
        let discard: XCUIElement = element(app, "copy.discard")
        if discard.waitForExistence(timeout: 5), discard.isHittable {
            discard.tap()
            waitUntilGone(printCopy)
        }
        backToDocument(app)
    }

    /// A PDF of three pages brought in as a batch: its page grid with the separator sheet marked, then the
    /// Export sheet with the separator sheets to print.
    @MainActor
    func test_sheetBatch() throws {
        let app: XCUIApplication = try launchImporting("batch", "pdf", task: "batch")
        app.waitForScanScreen()
        let pages: XCUIElement = app.pagesButton
        guard pages.waitForExistence(timeout: 60), pages.waitForPageCount(3, timeout: 240) else {
            shot("skipped-17-batch-pages")
            return
        }
        pages.tap()
        if element(app, "page.3").waitForExistence(timeout: 30) {
            Thread.sleep(forTimeInterval: 1)
            shot("17-batch-pages")
        } else {
            shot("skipped-17-batch-pages")
        }
        if tapIfThere(app, "pages.done", for: "17-batch-pages-closed") {
            waitUntilGone(element(app, "pages.done"))
        }
        if tapIfThere(app, "mode.printer", for: "17a-batch-export"),
           element(app, "task.chips").waitForExistence(timeout: 10),
           tapIfThere(app, "options.row.export", for: "17a-batch-export") {
            if app.scrolledTo("separator.save").exists {
                Thread.sleep(forTimeInterval: 1)
                shot("17a-batch-export")
            } else {
                shot("skipped-17a-batch-export")
            }
            closeOptions(app)
        }
        backToDocument(app)
    }

    /// A PDF of two pages brought in as a two-sided sheet: its page grid, camera mode's drawer on Camera with
    /// Both sides, and the password sheet Save asks for with Password on in Export (turned off again).
    @MainActor
    func test_sheetTwoSided() throws {
        let app: XCUIApplication = try launchImporting("two-sided", "pdf", task: "twoSided")
        app.waitForScanScreen()
        let pages: XCUIElement = app.pagesButton
        guard pages.waitForExistence(timeout: 60), pages.waitForPageCount(2, timeout: 240) else {
            shot("skipped-18-two-sided-pages")
            return
        }
        pages.tap()
        if element(app, "page.2").waitForExistence(timeout: 30) {
            Thread.sleep(forTimeInterval: 1)
            shot("18-two-sided-pages")
        } else {
            shot("skipped-18-two-sided-pages")
        }
        if tapIfThere(app, "pages.done", for: "18-two-sided-pages-closed") {
            waitUntilGone(element(app, "pages.done"))
        }
        if element(app, "mode.camera").exists, tapIfThere(app, "mode.camera", for: "18a-two-sided-drawer") {
            _ = element(app, "kinds.row").waitForExistence(timeout: 10)
        }
        if tapIfThere(app, "drawer.toggle", for: "18a-two-sided-drawer") {
            if tapIfThere(app, "drawer.camera", for: "18a-two-sided-drawer") {
                Thread.sleep(forTimeInterval: 1)
                shot("18a-two-sided-drawer")
            }
            if tapIfThere(app, "drawer.export", for: "19-password") {
                togglePassword(app)
                // Save sits under the drawer, which is closed first.
                if tapIfThere(app, "drawer.toggle", for: "19-password") {
                    waitUntilGone(element(app, "drawer"))
                }
                passwordSheet(app)
                if tapIfThere(app, "drawer.toggle", for: "19-password-off") {
                    if tapIfThere(app, "drawer.export", for: "19-password-off") {
                        togglePassword(app)
                    }
                    if tapIfThere(app, "drawer.toggle", for: "drawer-closed") {
                        waitUntilGone(element(app, "drawer"))
                    }
                }
            }
        }
        backToDocument(app)
    }

    /// Password among the drawer's Export chips, dragged into view when the row is long.
    @MainActor
    private func togglePassword(_ app: XCUIApplication) {
        let chip: XCUIElement = element(app, "chip.protect")
        guard chip.waitForExistence(timeout: 5) else {
            shot("skipped-19-password")
            return
        }
        var swipes: Int = 0
        while !chip.isHittable && swipes < 4 {
            let y: CGFloat = chip.frame.midY / app.frame.height
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: y)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: y)))
            swipes += 1
        }
        if chip.isHittable {
            chip.tap()
            Thread.sleep(forTimeInterval: 1)
        }
    }

    /// Save on a protected PDF asks for the password: the sheet, then Cancel.
    @MainActor
    private func passwordSheet(_ app: XCUIApplication) {
        let save: XCUIElement = element(app, "save.button")
        guard save.waitForExistence(timeout: 10), waitUntilEnabled(save, timeout: 60) else {
            shot("skipped-19-password")
            return
        }
        save.tap()
        let field: XCUIElement = element(app, "password.field")
        if field.waitForExistence(timeout: 20) {
            Thread.sleep(forTimeInterval: 1)
            shot("19-password")
            let cancel: XCUIElement = element(app, "password.cancel")
            if cancel.waitForExistence(timeout: 5) {
                cancel.tap()
                waitUntilGone(field)
            }
        } else {
            shot("skipped-19-password")
        }
    }

    /// The troubleshooter from Settings, then Done.
    @MainActor
    private func troubleshooterScreen(_ app: XCUIApplication) {
        guard tapIfThere(app, "settings.troubleshoot", for: "11a-troubleshooter") else { return }
        if element(app, "troubleshooter.headline").waitForExistence(timeout: 10) {
            Thread.sleep(forTimeInterval: 2)
            shot("11a-troubleshooter")
        } else {
            shot("skipped-11a-troubleshooter")
        }
        let done: XCUIElement = element(app, "troubleshooter.done")
        if done.waitForExistence(timeout: 5) {
            done.tap()
            waitUntilGone(done)
        }
    }

    /// The file name's editor, from the row in Settings' More section, which is opened when it is closed.
    @MainActor
    private func namingScreen(_ app: XCUIApplication) {
        // The row is no element of its own in the tree: found by the template it shows.
        let template: XCUIElement = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'settings.fileName' OR label CONTAINS '{task}'")).firstMatch
        var row: XCUIElement = scrolledDown(app, to: template)
        if !row.isHittable {
            let section: XCUIElement = scrolledDown(app, to: element(app, "settings.section.more"))
            if section.isHittable {
                section.tap()
                Thread.sleep(forTimeInterval: 1)
                row = scrolledDown(app, to: template)
            }
        }
        guard row.isHittable else {
            shot("skipped-11b-naming")
            return
        }
        row.tap()
        if element(app, "naming.field").waitForExistence(timeout: 10) {
            Thread.sleep(forTimeInterval: 1)
            shot("11b-naming")
        } else {
            shot("skipped-11b-naming")
        }
        back(app)
    }

    /// Settings is long, and its sections below the first are made only as they scroll into view.
    @MainActor
    private func scrolledDown(_ app: XCUIApplication, to target: XCUIElement) -> XCUIElement {
        var swipes: Int = 0
        while !(target.exists && target.isHittable) && swipes < 12 {
            app.swipeUp()
            swipes += 1
        }
        return target
    }

    /// The app launched on the demo scanner with the fixture to import into `task`, `count` times.
    @MainActor
    private func launchImporting(_ name: String, _ ext: String, count: Int = 1, task: String) throws -> XCUIApplication {
        let fixture: URL = try XCTUnwrap(Bundle(for: ScreenshotTests.self).url(forResource: name, withExtension: ext),
                                         "The fixture in the test bundle")
        let bytes: String = try Data(contentsOf: fixture).base64EncodedString()
        let app = XCUIApplication()
        app.launchArguments = ["-demoScanner", "-importFixture", "-importTask", task] + Self.language
        app.launchEnvironment["LAZYSCAN_IMPORT_FIXTURE"] = Array(repeating: bytes, count: count).joined(separator: ",")
        app.launch()
        return app
    }

    /// The corner editor's Use corners for a photo imported at launch, with a shot of the editor first when
    /// `shooting`; false, with a "skipped-" shot, when it never comes.
    @MainActor
    private func useCorners(_ app: XCUIApplication, for screen: String, shooting: Bool = true) -> Bool {
        var use: XCUIElement = app.buttons["corners.use"]
        // A long Skip title (the pseudo language's) pushes Use into the toolbar's overflow menu, where the
        // item has no identifier: found by its pseudo text instead.
        let more: XCUIElement = app.navigationBars.buttons["More"].firstMatch
        if app.buttons["corners.skip"].waitForExistence(timeout: 120), !use.exists, more.exists {
            more.tap()
            use = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Üšé çõrñérš'")).firstMatch
        }
        guard use.waitForExistence(timeout: 120), waitUntilEnabled(use, timeout: 30) else {
            shot("skipped-\(screen)")
            return false
        }
        if shooting {
            shot(screen)
        }
        use.tap()
        waitUntilGone(use)
        return true
    }

    /// The task back on Document, which the next run starts from: the printer screen's chip or camera
    /// mode's kind, whichever is up.
    @MainActor
    private func backToDocument(_ app: XCUIApplication) {
        let printer: Bool = element(app, "task.document").exists
        let chip: XCUIElement = element(app, printer ? "task.document" : "kinds.document")
        if chip.waitForExistence(timeout: 10) {
            bringIntoView(chip, in: element(app, printer ? "task.chips" : "kinds.row"))
            if chip.isHittable {
                chip.tap()
            }
        }
    }

    /// Swipes a row of chips until `chip` can be tapped; the row keeps the picked one in its middle.
    @MainActor
    private func bringIntoView(_ chip: XCUIElement, in row: XCUIElement) {
        var swipes: Int = 0
        while !chip.isHittable && swipes < 3 {
            if chip.frame.midX < row.frame.midX {
                row.swipeRight()
            } else {
                row.swipeLeft()
            }
            swipes += 1
        }
    }

    /// Picks a kind of camera mode's row, when it can be tapped.
    @MainActor
    private func pick(_ chip: XCUIElement) -> Bool {
        guard chip.exists, chip.isHittable else { return false }
        chip.tap()
        waitUntilSelected(chip)
        return true
    }

    /// Camera mode's kinds with Photo picked, and its drawer open on Export.
    @MainActor
    private func cameraScreens(_ app: XCUIApplication) {
        let photo: XCUIElement = element(app, "kinds.photos")
        let document: XCUIElement = element(app, "kinds.document")
        if photo.waitForExistence(timeout: 5) && document.exists {
            photo.tap()
            waitUntilSelected(photo)
            Thread.sleep(forTimeInterval: 1)
            shot("02-kinds-photo")
            swipeToMiddle(app, document)
            // The row keeps the kind picked in its middle, so a longer title can push the next but one off
            // the screen: each kind is picked from its neighbour.
            for kind in ["idCard", "book"] {
                if pick(element(app, "kinds.\(kind)")) {
                    Thread.sleep(forTimeInterval: 1)
                    shot("02-kinds-\(kind)")
                } else {
                    shot("skipped-02-kinds-\(kind)")
                }
            }
            for kind in ["idCard", "document"] {
                _ = pick(element(app, "kinds.\(kind)"))
            }
        } else {
            shot("skipped-02-kinds-photo")
        }
        if tapIfThere(app, "drawer.toggle", for: "03-drawer-export") {
            if tapIfThere(app, "drawer.export", for: "03-drawer-export") {
                Thread.sleep(forTimeInterval: 1)
                shot("03-drawer-export")
            }
            if tapIfThere(app, "drawer.toggle", for: "drawer-closed") {
                waitUntilGone(element(app, "drawer"))
            }
        }
    }

    /// Printer mode with the demo scanner picked in its Scanner sheet, two pages scanned, Save's menu and the
    /// Export sheet.
    @MainActor
    private func printerScreens(_ app: XCUIApplication) {
        guard tapIfThere(app, "mode.printer", for: "04-printer") else { return }
        guard element(app, "task.chips").waitForExistence(timeout: 10) else {
            shot("skipped-04-printer")
            return
        }
        Thread.sleep(forTimeInterval: 1)
        shot("04-printer")
        if tapIfThere(app, "options.row.scanner", for: "05-scanner-sheet") {
            let demo: XCUIElement = element(app, "scanner.row.mock:demo")
            if demo.waitForExistence(timeout: 5) {
                demo.tap()
                Thread.sleep(forTimeInterval: 1)
                shot("05-scanner-sheet")
                flatbedScreens(app)
            } else {
                shot("skipped-05-scanner-sheet")
            }
            closeOptions(app)
        }
        let scan: XCUIElement = element(app, "scan.button")
        let pages: XCUIElement = element(app, "capture.pages")
        guard scan.waitForExistence(timeout: 5) && waitUntilEnabled(scan, timeout: 30) else {
            shot("skipped-06-pages")
            return
        }
        scan.tap()
        if pages.waitForPageCount(1, timeout: 60) {
            // A second page, so the grid shows two across.
            if waitUntilEnabled(scan, timeout: 30) {
                scan.tap()
                _ = pages.waitForPageCount(2, timeout: 60)
            }
            pages.tap()
            let done: XCUIElement = element(app, "pages.done")
            if done.waitForExistence(timeout: 5) {
                Thread.sleep(forTimeInterval: 1)
                shot("06-pages")
                selectionScreen(app)
                if done.waitForExistence(timeout: 5) {
                    done.tap()
                    waitUntilGone(done)
                } else {
                    shot("skipped-pages-select-closed")
                    // Down to half height, then away.
                    app.swipeDown()
                    app.swipeDown()
                }
            } else {
                shot("skipped-06-pages")
            }
            if tapIfThere(app, "save.menu", for: "07-save-menu") {
                Thread.sleep(forTimeInterval: 1)
                shot("07-save-menu")
                closeMenu(app, item: element(app, "append.button"))
            }
        } else {
            shot("skipped-06-pages")
        }
        if tapIfThere(app, "options.row.export", for: "08-export-options") {
            if element(app, "options.format").waitForExistence(timeout: 5) {
                Thread.sleep(forTimeInterval: 1)
                shot("08-export-options")
            } else {
                shot("skipped-08-export-options")
            }
            closeOptions(app)
        }
        spreadScreens(app)
    }

    /// The kind dragged to the row's middle, as a swipe would: it should be the one picked.
    @MainActor
    private func swipeToMiddle(_ app: XCUIApplication, _ kind: XCUIElement) {
        let row: XCUIElement = element(app, "kinds.row")
        let from: XCUICoordinate = kind.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to: XCUICoordinate = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        let picked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: kind)
        if XCTWaiter.wait(for: [picked], timeout: 10) == .completed {
            shot("02-kinds-swipe")
        } else {
            shot("skipped-02-kinds-swipe")
        }
    }

    /// The flatbed preview in the open Scanner sheet: its thumbnail, then the Choose area screen with an
    /// area dragged out on the glass. The area is cleared again so the pages scanned next are whole.
    @MainActor
    private func flatbedScreens(_ app: XCUIApplication) {
        let preview: XCUIElement = app.scrolledTo("preview.button")
        guard preview.exists else {
            shot("skipped-05a-flatbed")
            return
        }
        preview.tap()
        var open: XCUIElement = element(app, "crop.open")
        if !open.waitForExistence(timeout: 60) {
            // The sheet closes while the preview is made: back into it.
            closeOptions(app)
            guard tapIfThere(app, "options.row.scanner", for: "05a-flatbed") else { return }
            open = app.scrolledTo("crop.open")
        }
        guard open.waitForExistence(timeout: 60) else {
            shot("skipped-05a-flatbed")
            return
        }
        Thread.sleep(forTimeInterval: 1)
        shot("05a-flatbed")
        open.tap()
        let editor: XCUIElement = element(app, "crop.editor")
        if editor.waitForExistence(timeout: 10) {
            let from: XCUICoordinate = editor.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.25))
            let to: XCUICoordinate = editor.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.65))
            from.press(forDuration: 0.1, thenDragTo: to)
            Thread.sleep(forTimeInterval: 1)
            shot("05b-crop-area")
        } else {
            shot("skipped-05b-crop-area")
        }
        let done: XCUIElement = element(app, "crop.done")
        if done.waitForExistence(timeout: 5) {
            done.tap()
            waitUntilGone(done)
        }
        let clear: XCUIElement = element(app, "crop.clear")
        if clear.waitForExistence(timeout: 5) {
            clear.tap()
        }
    }

    /// A book page scanned on the demo scanner and its split sheet, opened from the page grid's menu.
    @MainActor
    private func spreadScreens(_ app: XCUIApplication) {
        let book: XCUIElement = element(app, "task.book")
        let scan: XCUIElement = element(app, "scan.button")
        let pages: XCUIElement = element(app, "capture.pages")
        guard book.waitForExistence(timeout: 5) else {
            shot("skipped-14-spread")
            return
        }
        bringIntoView(book, in: element(app, "task.chips"))
        guard book.isHittable else {
            shot("skipped-14-spread")
            return
        }
        book.tap()
        let before: Int = pages.pageCount ?? 0
        guard waitUntilEnabled(scan, timeout: 30) else {
            shot("skipped-14-spread-scan")
            return
        }
        scan.tap()
        let grown = XCTNSPredicateExpectation(predicate: NSPredicate { (_: Any?, _: [String: Any]?) -> Bool in
            (pages.pageCount ?? 0) > before
        }, object: nil)
        guard XCTWaiter.wait(for: [grown], timeout: 60) == .completed else {
            print("spread scan: \(before) pages before, the button says \(pages.label)")
            shot("skipped-14-spread-scan")
            return
        }
        // A spread is one page until it is split: the page just added is the last.
        let count: Int = pages.pageCount ?? before + 1
        pages.tap()
        let page: XCUIElement = element(app, "page.\(count)")
        guard page.waitForExistence(timeout: 5) else {
            shot("skipped-14-spread-grid")
            return
        }
        page.press(forDuration: 1)
        let split: XCUIElement = app.buttons.matching(NSPredicate(
            format: "identifier == 'page.split' OR label BEGINSWITH 'Split' OR label BEGINSWITH 'Change'")).firstMatch
        guard split.waitForExistence(timeout: 5) else {
            shot("skipped-14-spread-menu")
            return
        }
        split.tap()
        let cut: XCUIElement = element(app, "spread.cut")
        if cut.waitForExistence(timeout: 10) {
            Thread.sleep(forTimeInterval: 1)
            shot("14-spread")
            if tapIfThere(app, "spread.split", for: "14-spread") {
                waitUntilGone(cut)
            }
        } else {
            shot("skipped-14-spread")
        }
    }

    /// The page grid selecting, its first page ticked, then Cancel back to Done.
    @MainActor
    private func selectionScreen(_ app: XCUIApplication) {
        guard tapIfThere(app, "pages.select", for: "06b-pages-select") else { return }
        if tapIfThere(app, "page.1", for: "06b-pages-select") {
            waitUntilSelected(element(app, "page.1"))
            Thread.sleep(forTimeInterval: 1)
            shot("06b-pages-select")
        }
        if tapIfThere(app, "pages.cancel", for: "pages-select-closed") {
            _ = element(app, "pages.done").waitForExistence(timeout: 5)
        }
    }

    /// Settings from printer mode's row, with My computer and Presets.
    @MainActor
    private func settingsScreens(_ app: XCUIApplication) {
        guard tapIfThere(app, "scan.settings", for: "09-settings") else { return }
        if element(app, "settings.presets").waitForExistence(timeout: 5) {
            shot("09-settings")
            if tapIfThere(app, "settings.companion", for: "10-my-computer") {
                Thread.sleep(forTimeInterval: 1)
                shot("10-my-computer")
                back(app)
            }
            if tapIfThere(app, "settings.presets", for: "11-presets") {
                if element(app, "presets.save").waitForExistence(timeout: 5) {
                    shot("11-presets")
                } else {
                    shot("skipped-11-presets")
                }
                back(app)
            }
            troubleshooterScreen(app)
            namingScreen(app)
        } else {
            shot("skipped-09-settings")
        }
        let done: XCUIElement = element(app, "settings.done")
        if done.waitForExistence(timeout: 5) {
            done.tap()
            waitUntilGone(done)
        }
    }

    /// The library from camera mode's top bar, its saved files and its scans.
    @MainActor
    private func libraryScreens(_ app: XCUIApplication) {
        if tapIfThere(app, "mode.camera", for: "12-library-saved") {
            _ = element(app, "kinds.row").waitForExistence(timeout: 10)
        }
        guard tapIfThere(app, "open.library", for: "12-library-saved") else { return }
        let part: XCUIElement = app.segmentedControls["library.part"]
        if part.waitForExistence(timeout: 5) {
            Thread.sleep(forTimeInterval: 1)
            shot("12-library-saved")
            let scans: XCUIElement = part.buttons.element(boundBy: 1)
            if scans.waitForExistence(timeout: 5) {
                scans.tap()
                Thread.sleep(forTimeInterval: 1)
                shot("13-library-history")
            } else {
                shot("skipped-13-library-history")
            }
        } else {
            shot("skipped-12-library-saved")
        }
        back(app)
    }

    @MainActor
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// By identifier among every element: toolbar items and some rows are not buttons to the test.
    @MainActor
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// Taps the element if it comes, else keeps a "skipped-" screenshot of what is there instead. The
    /// printer screen's list rows (`options.row.*`, Settings) and Settings' own rows are scrolled into view first.
    @MainActor
    private func tapIfThere(_ app: XCUIApplication, _ id: String, for screen: String) -> Bool {
        let inList: Bool = id.hasPrefix("options.row.") || id.hasPrefix("settings.") || id == "scan.settings"
        let target: XCUIElement = inList ? app.scrolledTo(id) : element(app, id)
        guard target.waitForExistence(timeout: 5) else {
            shot("skipped-\(screen)")
            return false
        }
        target.tap()
        return true
    }

    /// Closes the open Save menu with a tap on the preview area, or a swipe down when that leaves it open.
    @MainActor
    private func closeMenu(_ app: XCUIApplication, item: XCUIElement) {
        element(app, "preview.area").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        if !waitUntilGone(item) {
            app.swipeDown()
            waitUntilGone(item)
        }
    }

    /// Closes an option group's sheet with Done.
    @MainActor
    private func closeOptions(_ app: XCUIApplication) {
        let done: XCUIElement = element(app, "options.done")
        if done.waitForExistence(timeout: 5) {
            done.tap()
            waitUntilGone(done)
        }
    }

    @MainActor
    private func back(_ app: XCUIApplication) {
        let button: XCUIElement = app.navigationBars.buttons["BackButton"].firstMatch
        if button.waitForExistence(timeout: 5) {
            button.tap()
        }
    }

    @MainActor
    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: element)
        return XCTWaiter.wait(for: [enabled], timeout: timeout) == .completed
    }

    @MainActor
    private func waitUntilSelected(_ element: XCUIElement) {
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: element)
        _ = XCTWaiter.wait(for: [selected], timeout: 5)
    }

    @MainActor
    @discardableResult
    private func waitUntilGone(_ element: XCUIElement) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [gone], timeout: 5) == .completed
    }
}
