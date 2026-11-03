import XCTest

// The page grid's Select mode, as a person uses it on the Simulator: the three pages of the batch fixture
// brought in at launch (`-importFixture`, as in BatchTests), Select, the first two pages ticked, Delete and
// its question, and one page is left; and Delete All, which empties the queue and closes the sheet.

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

    // The sheet's title says its count in digits, in any language.
    @MainActor
    private func titleCount(_ app: XCUIApplication, is count: Int) -> Bool {
        let bar: XCUIElement = app.navigationBars.firstMatch
        let counted = XCTNSPredicateExpectation(predicate: NSPredicate { (_: Any?, _: [String: Any]?) -> Bool in
            Int((bar.label.isEmpty ? bar.identifier : bar.label).filter(\.isNumber)) == count
        }, object: nil)
        return XCTWaiter.wait(for: [counted], timeout: 30) == .completed
    }

    @MainActor
    func test_deleteAll_emptiesTheQueue_andClosesTheSheet() throws {
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

        let done: XCUIElement = app.descendants(matching: .any)["pages.done"].firstMatch
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: done)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 30), .completed, "The page strip closed")
        XCTAssertFalse(app.descendants(matching: .any)["page.1"].exists, "No pages left")
        XCTAssertTrue(app.pagesButton.waitForPageCount(0, timeout: 30), "0 pages on the pages' button")
    }
}
