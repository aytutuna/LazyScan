import XCTest

// Importing a photo of a document, as a person does it on the Simulator: the app is launched on the
// demo scanner with one photo to import (`-importFixture`; a UI test cannot drive the system's Photos
// or Files pickers, so the photo's bytes come in the environment, as the Files app would hand them
// over). The photo is the test's own fixture (Fixtures/document-photo.png, drawn by
// scripts/make_ios_ui_fixture.py: a sheet on a table, no real document). The page is found, the corner
// editor opens with its corners, Use corners puts the straightened page in the strip, and Save writes
// a PDF in the app's own Documents folder in the Simulator, with Save floating on camera mode's
// viewfinder. With the photo to import twice, Stop in the first one's corner editor ends the
// import: no page comes in. A type only sets choices, so the page stays when Photos, Receipts or Book is
// picked, nothing asked; the ID card starts its own steps and would leave it without a Save, so picking it
// asks first, and Cancel keeps the kind and the page.

final class ImportTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_photoImport_goesThroughTheCornerEditor_andSavesAPDF() throws {
        // Into Document by name: without it the photo goes into the task kept from the test before (Book).
        let app: XCUIApplication = try launchWithFixture(task: "document")

        let use: XCUIElement = app.buttons["corners.use"]
        XCTAssertTrue(use.waitForExistence(timeout: 120), "The corner editor's Use corners button")
        XCTAssertTrue(app.descendants(matching: .any)["corners.stage"].exists, "The photo with its corners")
        XCTAssertTrue(app.buttons["corners.whole"].exists, "Use whole photo")
        XCTAssertTrue(app.buttons["corners.skip"].exists, "Skip photo")
        waitUntilEnabled(use, timeout: 30)
        use.tap()

        app.openPages(1)
        app.closePages()

        app.switchToCamera()
        XCTAssertTrue(app.buttons["camera.shutter"].exists, "The shutter")

        let save: XCUIElement = app.buttons["save.button"]
        waitUntilEnabled(save, timeout: 120)
        save.tap()

        let saved: XCUIElement = app.staticTexts["saved.files"]
        XCTAssertTrue(saved.waitForExistence(timeout: 240), "The saved file's name")
        XCTAssertTrue(saved.label.hasSuffix(".pdf"), saved.label)
        XCTAssertTrue(app.buttons["share.button"].exists, "The saved file's Share button")
    }

    @MainActor
    func test_stop_inTheCornerEditor_endsTheImport() throws {
        // Stop is offered only while another photo follows the one in hand.
        let app: XCUIApplication = try launchWithFixture(count: 2)
        let stop: XCUIElement = app.buttons["corners.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 120), "The corner editor's Stop button")
        stop.tap()

        // Back on the scan screen with the import over: no editor, no progress, no Stop, no page.
        waitUntilGone(app.buttons["corners.use"], timeout: 30)
        waitUntilGone(app.descendants(matching: .any)["import.progress"], timeout: 30)
        XCTAssertFalse(app.buttons["import.stop"].exists, "The scan screen's Stop button")
        app.switchToPrinter()
        XCTAssertTrue(app.buttons["save.button"].waitForExistence(timeout: 30), "The printer screen")
        XCTAssertEqual(app.pagesButton.pageCount, 0,
                       "A page came in after Stop")
        XCTAssertFalse(app.buttons["save.button"].isEnabled, "Save with nothing to save")
    }

    @MainActor
    func test_everyTypeKeepsThePage_onlyTheIdCardAsksFirst() throws {
        let app: XCUIApplication = try launchWithFixture(task: "document")
        let use: XCUIElement = app.buttons["corners.use"]
        XCTAssertTrue(use.waitForExistence(timeout: 120), "The corner editor's Use corners button")
        waitUntilEnabled(use, timeout: 30)
        use.tap()
        app.openPages(1)
        app.closePages()

        app.switchToCamera()
        XCTAssertEqual(app.pickedKind, "document")
        for kind in ["photos", "receipts", "book"] {
            app.pickTask(kind)
            XCTAssertEqual(app.pickedKind, kind)
            XCTAssertFalse(app.alerts.firstMatch.exists, "Nothing asked for \(kind)")
            XCTAssertEqual(app.pagesButton.pageCount, 1, "\(kind) keeps the page")
            XCTAssertTrue(app.buttons["save.button"].isEnabled, "Save still has the page")
        }

        app.chooseType("idCard")
        let question: XCUIElement = app.alerts.firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 10), "Asked before the ID card")
        // First match: the Simulator lists an alert's button twice.
        XCTAssertTrue(question.buttons["keepPages.save"].firstMatch.exists, "Save first")
        XCTAssertTrue(question.buttons["keepPages.discard"].firstMatch.exists, "Discard 1 page")
        question.buttons["keepPages.cancel"].firstMatch.tap()
        waitUntilGone(question, timeout: 10)
        XCTAssertEqual(app.pickedKind, "book", "Cancel keeps the kind")
        XCTAssertEqual(app.pagesButton.pageCount, 1, "Cancel keeps the page")
        XCTAssertEqual(app.buttons["save.button"].label, "Save")
    }

    /// The app on the demo scanner with the fixture photo to import at launch, `count` times, into `task` when
    /// one is given (`ScanTask`'s raw value).
    @MainActor
    private func launchWithFixture(task: String? = nil, count: Int = 1) throws -> XCUIApplication {
        let fixture: URL = try XCTUnwrap(Bundle(for: ImportTests.self).url(forResource: "document-photo", withExtension: "png"),
                                         "The fixture photo in the test bundle")
        let bytes: Data = try Data(contentsOf: fixture)
        let app = XCUIApplication()
        app.launchArguments = ["-demoScanner", "-importFixture"]
        if let task {
            app.launchArguments += ["-importTask", task]
        }
        // Several files go comma-separated, as `IOSLaunchOptions` reads them.
        let photos: [String] = Array(repeating: bytes.base64EncodedString(), count: count)
        app.launchEnvironment["LAZYSCAN_IMPORT_FIXTURE"] = photos.joined(separator: ",")
        app.launch()
        return app
    }

    @MainActor
    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval,
                               file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "exists == false")
        let gone = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result: XCTWaiter.Result = XCTWaiter.wait(for: [gone], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(element.identifier) stayed", file: file, line: line)
    }

    @MainActor
    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "isEnabled == true")
        let enabled = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result: XCTWaiter.Result = XCTWaiter.wait(for: [enabled], timeout: timeout)
        XCTAssertEqual(result, .completed, "\(element.identifier) stayed disabled", file: file, line: line)
    }
}
