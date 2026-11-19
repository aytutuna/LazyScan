import XCTest

// The page grid's Select mode, as a person uses it on the Simulator: the three pages of the batch fixture
// brought in at launch (`-importFixture`, as in BatchTests), Select, the first two pages ticked, Remove and
// its question, and one page is left; Remove All, which empties the queue and closes the sheet; the bar's
// Options and the format menu beside Save; a page dragged onto another, which lands before it; and a pinch.

final class PagesTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_twoPagesSelected_areDeletedTogether() throws {
        let fixture: URL = try XCTUnwrap(Bundle(for: PagesTests.self).url(forResource: "batch", withExtension: "pdf"),
                                         "The fixture PDF in the test bundle")
        let app = XCUIApplication()
        app.launchArguments = ["-demoScanner", "-importFixture", "-importTask", "batch"]
        app.launchEnvironment["LAZYSCAN_IMPORT_FIXTURE"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launch()

        app.openPages(3)
        app.waitUntilEnabled(app.descendants(matching: .any)["pages.save"].firstMatch, "Save", timeout: 120)
        let select: XCUIElement = app.descendants(matching: .any)["pages.select"].firstMatch
        XCTAssertTrue(select.waitForExistence(timeout: 10), "Select")
        select.tap()
        XCTAssertTrue(app.descendants(matching: .any)["pages.cancel"].firstMatch.waitForExistence(timeout: 10),
                      "Cancel while selecting")
        XCTAssertFalse(app.descendants(matching: .any)["pages.done"].firstMatch.exists, "No Done while selecting")
        for number in [1, 2] {
            let page: XCUIElement = app.descendants(matching: .any)["page.\(number)"].firstMatch
            page.tap()
            let ticked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: page)
            XCTAssertEqual(XCTWaiter.wait(for: [ticked], timeout: 10), .completed, "Page \(number) ticked")
        }

        XCTAssertTrue(titleCount(app, is: 2), "The title counts the two selected pages")

        // On a compact phone the actions sit in one menu.
        let actions: XCUIElement = app.descendants(matching: .any)["pages.selectActions"].firstMatch
        if actions.exists {
            app.waitUntilEnabled(actions, "Actions", timeout: 10)
            actions.tap()
        }
        let delete: XCUIElement = app.descendants(matching: .any)["pages.deleteSelected"].firstMatch
        // Off until the import is done, as Save is in BatchTests.
        app.waitUntilEnabled(delete, "Remove", timeout: 10)
        let deleteText: String = delete.label
        delete.tap()
        // By its label: a dialog's button may not keep its identifier. The bar's Remove is the other one.
        let confirm: XCUIElement = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", deleteText,
                                                                    "pages.deleteSelected")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "The question's Remove")
        confirm.tap()

        let second: XCUIElement = app.descendants(matching: .any)["page.2"]
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: second)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 30), .completed, "No second page")
        XCTAssertTrue(titleCount(app, is: 1), "The title counts the remaining page")
        app.closePages()
        XCTAssertTrue(app.pagesButton.waitForPageCount(1, timeout: 30), "1 page on the pages' button")
    }

    // The document items of the page viewer are in the selection's actions for one page picked, and gone for two.
    // In the batch fixture the third page starts Document 2.
    @MainActor
    func test_onePageSelected_offersTheDocumentItems() throws {
        let fixture: URL = try XCTUnwrap(Bundle(for: PagesTests.self).url(forResource: "batch", withExtension: "pdf"),
                                         "The fixture PDF in the test bundle")
        let app = XCUIApplication()
        app.launchArguments = ["-demoScanner", "-importFixture", "-importTask", "batch"]
        app.launchEnvironment["LAZYSCAN_IMPORT_FIXTURE"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launch()

        app.openPages(3)
        app.waitUntilEnabled(app.descendants(matching: .any)["pages.save"].firstMatch, "Save", timeout: 120)
        app.descendants(matching: .any)["pages.select"].firstMatch.tap()
        let rename: XCUIElement = app.descendants(matching: .any)["tile.document.name"].firstMatch
        let join: XCUIElement = app.descendants(matching: .any)["tile.document.break"].firstMatch

        app.descendants(matching: .any)["page.3"].firstMatch.tap()
        openSelectionMenu(app)
        XCTAssertTrue(join.waitForExistence(timeout: 10), "Join with document 1")
        XCTAssertTrue(rename.exists, "Name document")
        dismissSelectionMenu(app)

        app.descendants(matching: .any)["page.1"].firstMatch.tap()
        XCTAssertTrue(titleCount(app, is: 2), "The title counts the two selected pages")
        if app.descendants(matching: .any)["pages.selectActions"].firstMatch.exists {
            openSelectionMenu(app)
            let rotate: XCUIElement = app.descendants(matching: .any)["pages.rotateSelected"].firstMatch
            XCTAssertTrue(rotate.waitForExistence(timeout: 10), "The other actions stay")
            XCTAssertFalse(join.exists, "No document items for two pages")
            XCTAssertFalse(rename.exists, "No document items for two pages")
            dismissSelectionMenu(app)
        } else {
            XCTAssertFalse(app.descendants(matching: .any)["pages.documentSelected"].firstMatch.exists,
                           "No Document menu for two pages")
        }
    }

    // On a compact phone the items are in the Actions menu, at a regular width in the Document menu.
    @MainActor
    private func openSelectionMenu(_ app: XCUIApplication) {
        let actions: XCUIElement = app.descendants(matching: .any)["pages.selectActions"].firstMatch
        let document: XCUIElement = app.descendants(matching: .any)["pages.documentSelected"].firstMatch
        if actions.exists {
            app.waitUntilEnabled(actions, "Actions", timeout: 10)
            actions.tap()
        } else {
            XCTAssertTrue(document.waitForExistence(timeout: 10), "The Document menu")
            document.tap()
        }
    }

    // A tap on the title, which no page is under.
    @MainActor
    private func dismissSelectionMenu(_ app: XCUIApplication) {
        app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    // Mark Up opens from the page viewer with nothing drawn: Undo is off, and Cancel closes it with no question.
    @MainActor
    func test_markUp_opensWithUndoOff_andCancelCloses() throws {
        let fixture: URL = try XCTUnwrap(Bundle(for: PagesTests.self).url(forResource: "batch", withExtension: "pdf"),
                                         "The fixture PDF in the test bundle")
        let app = XCUIApplication()
        app.launchArguments = ["-demoScanner", "-importFixture", "-importTask", "batch"]
        app.launchEnvironment["LAZYSCAN_IMPORT_FIXTURE"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launch()

        app.openPages(3)
        app.descendants(matching: .any)["page.1"].firstMatch.tap()
        let markUp: XCUIElement = app.descendants(matching: .any)["viewer.markup"].firstMatch
        XCTAssertTrue(markUp.waitForExistence(timeout: 30), "The viewer's Mark Up button")
        app.waitUntilEnabled(markUp, "Mark Up", timeout: 120)
        markUp.tap()
        let undo: XCUIElement = app.descendants(matching: .any)["markup.undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 10), "Undo on the Mark Up screen")
        XCTAssertFalse(undo.isEnabled, "Nothing to undo yet")
        app.descendants(matching: .any)["markup.cancel"].firstMatch.tap()
        XCTAssertTrue(markUp.waitForExistence(timeout: 10), "Back on the viewer")
        app.descendants(matching: .any)["viewer.done"].firstMatch.tap()
        app.closePages()
    }

    // Pressing the third page and dragging it onto the first puts it first. The demo scanner's pages look
    // alike, so each tile's accessibility value (the page's id, under -demoScanner) tells them apart.
    @MainActor
    func test_pageDraggedOntoTheFirst_takesItsPlace() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoScanner"]
        app.launch()

        app.switchToPrinter()
        app.pickTask("document")
        app.pickScanner("scanner.row.mock:demo")
        let scan: XCUIElement = app.buttons["scan.button"]
        XCTAssertTrue(scan.waitForExistence(timeout: 30), "The scan screen's Scan button")
        for count in 1...3 {
            app.waitUntilEnabled(scan, "Scan", timeout: 120)
            scan.tap()
            XCTAssertTrue(app.pagesButton.waitForPageCount(count, timeout: 240), "\(count) on the pages' button")
        }
        // The drop is refused while a scan is still being spooled.
        app.waitUntilEnabled(scan, "Scan", timeout: 120)
        app.openPages(3)

        let ids: [String] = (1...3).map { (number: Int) -> String in pageID(app, number) }
        XCTAssertEqual(Set(ids).count, 3, "Three different pages")

        let first: XCUIElement = app.descendants(matching: .any)["page.1"].firstMatch
        let third: XCUIElement = app.descendants(matching: .any)["page.3"].firstMatch
        var isFirst = false
        for _ in 1...2 where !isFirst {
            third.press(forDuration: 1, thenDragTo: first, withVelocity: .slow, thenHoldForDuration: 1)
            let moved = XCTNSPredicateExpectation(predicate: NSPredicate { (_: Any?, _: [String: Any]?) -> Bool in
                self.pageID(app, 1) == ids[2]
            }, object: nil)
            isFirst = XCTWaiter.wait(for: [moved], timeout: 10) == .completed
        }
        XCTAssertTrue(isFirst, "The third page is first")
        XCTAssertEqual((1...3).map { (number: Int) -> String in pageID(app, number) }, [ids[2], ids[0], ids[1]],
                       "The others moved down one")
    }

    @MainActor
    private func pageID(_ app: XCUIApplication, _ number: Int) -> String {
        app.descendants(matching: .any)["page.\(number)"].firstMatch.value as? String ?? ""
    }

    // The sheet's title says its count in digits, in any language.
    @MainActor
    private func titleCount(_ app: XCUIApplication, is count: Int) -> Bool {
        // The sheet's bar: on the iPad the first one is the sidebar's.
        let bar: XCUIElement = app.navigationBars.containing(NSPredicate(format: "identifier IN %@", ["pages.cancel", "pages.done"])).firstMatch
        let counted = XCTNSPredicateExpectation(predicate: NSPredicate { (_: Any?, _: [String: Any]?) -> Bool in
            Int((bar.label.isEmpty ? bar.identifier : bar.label).filter(\.isNumber)) == count
        }, object: nil)
        return XCTWaiter.wait(for: [counted], timeout: 30) == .completed
    }

    @MainActor
    func test_deleteAll_emptiesTheQueue_andUndoPutsItBack() throws {
        let fixture: URL = try XCTUnwrap(Bundle(for: PagesTests.self).url(forResource: "batch", withExtension: "pdf"),
                                         "The fixture PDF in the test bundle")
        let app = XCUIApplication()
        app.launchArguments = ["-demoScanner", "-importFixture", "-importTask", "batch"]
        app.launchEnvironment["LAZYSCAN_IMPORT_FIXTURE"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launch()

        app.openPages(3)
        app.waitUntilEnabled(app.descendants(matching: .any)["pages.save"].firstMatch, "Save", timeout: 120)
        let deleteAll: XCUIElement = app.descendants(matching: .any)["pages.deleteAll"].firstMatch
        XCTAssertTrue(deleteAll.waitForExistence(timeout: 10), "Remove All in the bar")
        XCTAssertFalse(app.descendants(matching: .any)["pages.more"].exists, "No menu behind Remove All")
        // Off until the import is done.
        app.waitUntilEnabled(deleteAll, "Remove All", timeout: 10)
        let deleteAllText: String = deleteAll.label
        deleteAll.tap()
        let confirm: XCUIElement = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", deleteAllText,
                                                                    "pages.deleteAll")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "The question's Remove All")
        confirm.tap()

        // The sheet stays, with the Undo of the pages just cleared.
        let undo: XCUIElement = app.descendants(matching: .any)["remove.undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 30), "Undo on the page strip")
        XCTAssertFalse(app.descendants(matching: .any)["page.1"].exists, "No pages left")
        undo.tap()
        XCTAssertTrue(app.descendants(matching: .any)["page.3"].waitForExistence(timeout: 30), "The pages are back")
    }

    // The bar has Options, and the chevron beside Save lists the formats of the kind: a document's has PDF, and
    // picking JPEG puts it in Save's text.
    @MainActor
    func test_saveFormatMenu_listsPDF_andJPEGChangesSave() throws {
        let fixture: URL = try XCTUnwrap(Bundle(for: PagesTests.self).url(forResource: "batch", withExtension: "pdf"),
                                         "The fixture PDF in the test bundle")
        let app = XCUIApplication()
        app.launchArguments = ["-demoScanner", "-importFixture", "-importTask", "batch"]
        app.launchEnvironment["LAZYSCAN_IMPORT_FIXTURE"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launch()

        app.openPages(3)
        let save: XCUIElement = app.descendants(matching: .any)["pages.save"].firstMatch
        app.waitUntilEnabled(save, "Save", timeout: 120)
        XCTAssertTrue(app.descendants(matching: .any)["pages.options"].firstMatch.exists, "Options in the bar")
        let formats: XCUIElement = app.descendants(matching: .any)["pages.saveFormat"].firstMatch
        XCTAssertTrue(formats.waitForExistence(timeout: 10), "The format menu beside Save")
        XCTAssertFalse(save.label.contains("JPEG"), "Save is not a JPEG's yet")

        formats.tap()
        let pdf: XCUIElement = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "PDF")).firstMatch
        XCTAssertTrue(pdf.waitForExistence(timeout: 10), "PDF in the format menu")
        let jpeg: XCUIElement = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "JPEG")).firstMatch
        XCTAssertTrue(jpeg.exists, "JPEG in the format menu")
        jpeg.tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "JPEG"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed, "Save names JPEG")

        // The format is kept across launches, so put PDF back for the tests after this one.
        formats.tap()
        XCTAssertTrue(pdf.waitForExistence(timeout: 10), "PDF in the format menu again")
        pdf.tap()
        let back = XCTNSPredicateExpectation(predicate: NSPredicate(format: "NOT (label CONTAINS %@)", "JPEG"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [back], timeout: 10), .completed, "Save back to PDF")
    }

    // Options in the bar closes the sheet for the Options sheet, and Done there brings the pages back.
    @MainActor
    func test_optionsInTheBar_comesBackToThePages() throws {
        let fixture: URL = try XCTUnwrap(Bundle(for: PagesTests.self).url(forResource: "batch", withExtension: "pdf"),
                                         "The fixture PDF in the test bundle")
        let app = XCUIApplication()
        app.launchArguments = ["-demoScanner", "-importFixture", "-importTask", "batch"]
        app.launchEnvironment["LAZYSCAN_IMPORT_FIXTURE"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launch()

        app.openPages(3)
        let options: XCUIElement = app.descendants(matching: .any)["pages.options"].firstMatch
        XCTAssertTrue(options.waitForExistence(timeout: 10), "Options in the bar")
        options.tap()
        let done: XCUIElement = app.descendants(matching: .any)["options.done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 30), "The Options sheet")
        done.tap()
        XCTAssertTrue(app.descendants(matching: .any)["pages.done"].firstMatch.waitForExistence(timeout: 30),
                      "The pages are back")
        app.closePages()
    }

    // Pinching in shows more pages across with the number on a pill, which goes a second after the fingers lift;
    // the pages settle at a whole number across, so they are narrower than before.
    @MainActor
    func test_pinchingTheGrid_showsTheNumberAcross_andSettlesNarrower() throws {
        let fixture: URL = try XCTUnwrap(Bundle(for: PagesTests.self).url(forResource: "batch", withExtension: "pdf"),
                                         "The fixture PDF in the test bundle")
        let app = XCUIApplication()
        app.launchArguments = ["-demoScanner", "-importFixture", "-importTask", "batch"]
        app.launchEnvironment["LAZYSCAN_IMPORT_FIXTURE"] = try Data(contentsOf: fixture).base64EncodedString()
        app.launch()

        app.openPages(3)
        app.waitUntilEnabled(app.descendants(matching: .any)["pages.save"].firstMatch, "Save", timeout: 120)
        let page: XCUIElement = app.descendants(matching: .any)["page.1"].firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 10), "The first page")
        let before: CGFloat = page.frame.width
        let readout: XCUIElement = app.descendants(matching: .any)["pages.columnsReadout"].firstMatch
        XCTAssertFalse(readout.exists, "No pill before a pinch")

        // On a page, not the whole strip: fingers that far apart drag the sheet down to half instead.
        page.pinch(withScale: 0.4, velocity: -1)
        XCTAssertTrue(readout.waitForExistence(timeout: 5), "The pill with the number across")
        let narrower = XCTNSPredicateExpectation(predicate: NSPredicate { (_: Any?, _: [String: Any]?) -> Bool in
            page.frame.width < before - 10
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [narrower], timeout: 10), .completed, "The pages settle narrower")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: readout)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed, "The pill fades")
        app.closePages()
    }
}
