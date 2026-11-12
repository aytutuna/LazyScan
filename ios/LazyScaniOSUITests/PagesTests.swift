import XCTest

// The page grid's Select mode, as a person uses it on the Simulator: the three pages of the batch fixture
// brought in at launch (`-importFixture`, as in BatchTests), Select, the first two pages ticked, Delete and
// its question, and one page is left; Delete All, which empties the queue and closes the sheet; and a page
// dragged onto another, which takes its place.

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

        let delete: XCUIElement = app.descendants(matching: .any)["pages.deleteSelected"].firstMatch
        // Off until the import is done, as Save is in BatchTests.
        app.waitUntilEnabled(delete, "Delete", timeout: 120)
        let deleteText: String = delete.label
        delete.tap()
        // By its label: a dialog's button may not keep its identifier. The bar's Delete is the other one.
        let confirm: XCUIElement = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", deleteText,
                                                                    "pages.deleteSelected")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "The question's Delete")
        confirm.tap()

        let second: XCUIElement = app.descendants(matching: .any)["page.2"]
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: second)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 30), .completed, "No second page")
        XCTAssertTrue(titleCount(app, is: 1), "The title counts the remaining page")
        app.closePages()
        XCTAssertTrue(app.pagesButton.waitForPageCount(1, timeout: 30), "1 page on the pages' button")
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
        let deleteAll: XCUIElement = app.descendants(matching: .any)["pages.deleteAll"].firstMatch
        XCTAssertTrue(deleteAll.waitForExistence(timeout: 10), "Delete All")
        // Off until the import is done.
        app.waitUntilEnabled(deleteAll, "Delete All", timeout: 120)
        let deleteAllText: String = deleteAll.label
        deleteAll.tap()
        let confirm: XCUIElement = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", deleteAllText,
                                                                    "pages.deleteAll")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "The question's Delete All")
        confirm.tap()

        // The sheet stays, with the Undo of the pages just cleared.
        let undo: XCUIElement = app.descendants(matching: .any)["remove.undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 30), "Undo on the page strip")
        XCTAssertFalse(app.descendants(matching: .any)["page.1"].exists, "No pages left")
        undo.tap()
        XCTAssertTrue(app.descendants(matching: .any)["page.3"].waitForExistence(timeout: 30), "The pages are back")
    }
}
