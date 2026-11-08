import XCTest

// Several photos in one shot, as a person does it on the Simulator (I13): the app is launched on the demo
// scanner with one photo to import into the Photos task (`-importFixture` with `-importTask photos`; the
// Simulator has no camera, and a UI test cannot drive the system's pickers, so the photo's bytes come in
// the environment, as a camera's shot would be read). The photo is the test's own fixture
// (Fixtures/photos-on-table.png, drawn by scripts/make_ios_ui_fixture.py: two prints with white borders on
// a dark table, no picture of anything). Both prints are found (Vision's rectangles, or the photo search of
// the whole shot where Vision finds none) and come in as two pages of the page list, with Options and Save as
// for a document; Save writes two JPEGs in the app's own Documents folder in the Simulator, and a print left
// out is deleted from the pages first.

final class PhotosTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_twoPrintsInOneShot_underThePhotosTask_areTwoPages_andSaveTwoJPEGs() throws {
        let app: XCUIApplication = try launchWithPrints()

        app.openPages(2)
        XCTAssertTrue(app.descendants(matching: .any)["page.1"].exists, "The first print's page")
        XCTAssertTrue(app.descendants(matching: .any)["page.2"].exists, "The second print's page")
        XCTAssertFalse(app.descendants(matching: .any)["page.3"].exists, "Only the two prints")
        app.closePages()
        XCTAssertFalse(app.descendants(matching: .any)["review.save"].exists, "No review opens")

        let save: XCUIElement = app.buttons["save.button"]
        XCTAssertTrue(save.waitForExistence(timeout: 30), "Save")
        XCTAssertEqual(save.value as? String, "Save JPEG (2 pages)")
        app.waitUntilEnabled(save, "Save", timeout: 60)
        save.tap()

        let saved: XCUIElement = app.staticTexts["saved.files"]
        XCTAssertTrue(saved.waitForExistence(timeout: 240), "The saved files' names")
        let names: [String] = saved.label.components(separatedBy: ", ")
        XCTAssertEqual(names.count, 2, saved.label)
        for name in names {
            XCTAssertTrue(name.hasSuffix(".jpg"), name)
        }
    }

    @MainActor
    func test_aPrintLeftOut_isDeletedFromThePages_andOneJPEGIsSaved() throws {
        let app: XCUIApplication = try launchWithPrints()

        app.openPages(2)
        let select: XCUIElement = app.descendants(matching: .any)["pages.select"].firstMatch
        XCTAssertTrue(select.waitForExistence(timeout: 10), "Select")
        select.tap()
        let second: XCUIElement = app.descendants(matching: .any)["page.2"].firstMatch
        second.tap()
        let ticked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: second)
        XCTAssertEqual(XCTWaiter.wait(for: [ticked], timeout: 10), .completed, "Page 2 ticked")

        let delete: XCUIElement = app.descendants(matching: .any)["pages.deleteSelected"].firstMatch
        app.waitUntilEnabled(delete, "Delete", timeout: 120)
        let deleteText: String = delete.label
        delete.tap()
        let confirm: XCUIElement = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", deleteText,
                                                                    "pages.deleteSelected")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "The question's Delete")
        confirm.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: second)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 30), .completed, "No second page")
        app.closePages()
        XCTAssertTrue(app.pagesButton.waitForPageCount(1, timeout: 30), "1 page on the pages' button")

        let save: XCUIElement = app.buttons["save.button"]
        app.waitUntilEnabled(save, "Save", timeout: 60)
        save.tap()
        let saved: XCUIElement = app.staticTexts["saved.files"]
        XCTAssertTrue(saved.waitForExistence(timeout: 240), "The saved file's name")
        XCTAssertTrue(saved.label.hasSuffix(".jpg"), saved.label)
    }

    /// The app on the demo scanner with the two prints to import into Photos at launch.
    @MainActor
    private func launchWithPrints() throws -> XCUIApplication {
        let fixture: URL = try XCTUnwrap(Bundle(for: PhotosTests.self).url(forResource: "photos-on-table", withExtension: "png"),
                                         "The fixture photo in the test bundle")
        let bytes: Data = try Data(contentsOf: fixture)
        let app = XCUIApplication()
        app.launchArguments = ["-demoScanner", "-importFixture", "-importTask", "photos"]
        app.launchEnvironment["LAZYSCAN_IMPORT_FIXTURE"] = bytes.base64EncodedString()
        app.launch()
        return app
    }
}
