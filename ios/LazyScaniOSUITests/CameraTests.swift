import XCTest

// Camera mode as a person meets it on the Simulator: launched on the demo scanner alone (`-demoScanner`),
// the viewfinder is the scan screen. The Simulator has no camera, so the viewfinder says so in one line,
// the shutter is dimmed and no permission prompt is shown; the bottom bar has Options and Save, then the
// pages, the shutter, Photos and Files. The arrow opens the options drawer, whose Camera group has Auto, Both
// sides and Items in frame; what is saved is in the Options sheet, whose Type row lists the camera's kinds.
// The scanner button switches to printer mode and its camera button back; the bottom bar is the same there.
// Nothing is photographed.

final class CameraTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_cameraMode_showsTheNoCameraState_inTheSimulator() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoScanner"]
        app.launch()

        app.switchToCamera()
        app.pickTask("document")

        let message: XCUIElement = app.staticTexts["camera.message"]
        XCTAssertTrue(message.waitForExistence(timeout: 30), "The viewfinder's one line")
        XCTAssertEqual(message.label, "No camera here")
        XCTAssertFalse(app.buttons["camera.settings"].exists, "Settings is only for access turned off")
        let shutter: XCUIElement = app.buttons["camera.shutter"]
        XCTAssertTrue(shutter.exists, "The shutter")
        XCTAssertFalse(shutter.isEnabled, "No shutter without a camera")
        let pages: XCUIElement = app.descendants(matching: .any)["camera.pages"].firstMatch
        XCTAssertTrue(pages.exists, "The pages")
        XCTAssertEqual(pages.pageCount, 0)
        XCTAssertTrue(app.buttons["options.button"].exists, "Options")
        XCTAssertTrue(app.buttons["save.button"].exists, "Save")
        XCTAssertFalse(app.buttons["save.button"].isEnabled, "No Save before there are pages")
        XCTAssertTrue(app.buttons["import.photos"].exists, "Photos")
        XCTAssertTrue(app.buttons["import.files"].exists, "Files")
        XCTAssertFalse(app.buttons["scan.button"].exists, "No Scan in camera mode")

        app.openDrawer("camera")
        XCTAssertTrue(app.descendants(matching: .any)["camera.auto"].firstMatch.exists, "The Auto switch")
        XCTAssertTrue(app.switches["options.bothSides"].firstMatch.exists, "Both sides")
        XCTAssertTrue(app.descendants(matching: .any)["camera.itemsInFrame"].firstMatch.exists, "Items in frame")
        XCTAssertFalse(app.buttons["drawer.export"].exists, "What is saved is not in the drawer")
        XCTAssertFalse(app.buttons["drawer.quality"].exists, "The PDF's size is not in the drawer")
        app.closeDrawer()

        app.openOptions()
        XCTAssertTrue(app.descendants(matching: .any)["options.format"].firstMatch.waitForExistence(timeout: 10),
                      "The format in Options")
        XCTAssertTrue(app.descendants(matching: .any)["pdf.size"].firstMatch.exists, "The PDF's size in Options")
        XCTAssertTrue(app.scrolledTo("save.email").exists, "Email in Options")
        app.closeOptions()
        XCTAssertEqual(app.pickedKind, "document")
    }

    @MainActor
    func test_typeRow_listsTheCameraKinds_andPicksOne() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoScanner"]
        app.launch()

        app.switchToCamera()
        app.openOptions()
        let menu: XCUIElement = app.descendants(matching: .any)["options.type"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 30), "The Type row")
        menu.tap()
        for kind in ["photos", "document", "receipts", "idCard", "book"] {
            XCTAssertTrue(app.descendants(matching: .any)["type.\(kind)"].firstMatch.waitForExistence(timeout: 10),
                          "The \(kind) type")
        }
        XCTAssertFalse(app.descendants(matching: .any)["type.text"].firstMatch.exists, "Text is the scanner tab's")
        app.descendants(matching: .any)["type.photos"].firstMatch.tap()
        app.waitForType("photos")
        // Photos are pages like a document's: Export's format is there (JPEG to start with) beside Restore,
        // which is under the Type row, and Save waits for a page.
        XCTAssertTrue(app.switches["options.restore"].firstMatch.waitForExistence(timeout: 10), "Restore faded colors")
        XCTAssertTrue(app.descendants(matching: .any)["options.format"].firstMatch.exists, "Export's format for Photo")
        app.closeOptions()
        XCTAssertFalse(app.buttons["save.button"].isEnabled, "No Save without a page")
    }

    @MainActor
    func test_optionsAndSave_areRoundButtonsInThePicture_onBothTabs_andTheShutterStaysPut() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoScanner"]
        app.launch()

        app.switchToCamera()
        let viewfinder: XCUIElement = app.descendants(matching: .any)["camera.screen"].firstMatch
        XCTAssertTrue(viewfinder.waitForExistence(timeout: 30), "The viewfinder")
        let options: XCUIElement = app.buttons["options.button"]
        let save: XCUIElement = app.buttons["save.button"]
        XCTAssertTrue(options.exists && save.exists, "Options and Save")
        XCTAssertTrue(viewfinder.frame.contains(options.frame), "Options over the viewfinder's corner")
        XCTAssertTrue(viewfinder.frame.contains(save.frame), "Save over the viewfinder's corner")
        XCTAssertLessThan(options.frame.midX, save.frame.midX, "Options at the left, Save at the right")
        XCTAssertEqual(options.frame.midY, save.frame.midY, accuracy: 1)
        XCTAssertEqual(options.label, "Options")
        XCTAssertEqual(save.label, "Save")
        XCTAssertGreaterThanOrEqual(save.frame.width, 44, "A hit area of 44 points")
        XCTAssertEqual(viewfinder.frame.maxY - save.frame.maxY, 16, accuracy: 1, "16 points from the picture's foot")
        let shutter: CGRect = app.buttons["camera.shutter"].frame

        app.switchToPrinter()
        let picture: XCUIElement = app.descendants(matching: .any)["preview.area"].firstMatch
        XCTAssertTrue(picture.waitForExistence(timeout: 30), "The scanner tab's picture")
        XCTAssertTrue(picture.frame.contains(options.frame), "Options over the picture's corner")
        XCTAssertTrue(picture.frame.contains(save.frame), "Save over the picture's corner")
        XCTAssertLessThan(options.frame.midX, save.frame.midX, "Options at the left, Save at the right")
        let row: XCUIElement = app.descendants(matching: .any)["options.row.scanner"].firstMatch
        XCTAssertTrue(row.exists, "The Scanner row")
        XCTAssertLessThanOrEqual(row.frame.maxY, picture.frame.minY + 1, "The Scanner row is above the picture")
        let scan: CGRect = app.buttons["scan.button"].frame
        XCTAssertEqual(scan.midX, shutter.midX, accuracy: 1, "Scan where the shutter was")
        XCTAssertEqual(scan.midY, shutter.midY, accuracy: 1, "Scan where the shutter was")
    }

    @MainActor
    func test_printerButton_andCameraButton_switchTheMode() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoScanner"]
        app.launch()

        app.switchToCamera()
        app.switchToPrinter()
        XCTAssertTrue(app.buttons["scan.button"].waitForExistence(timeout: 30), "Scan in printer mode")
        XCTAssertFalse(app.buttons["camera.shutter"].exists, "No shutter in printer mode")
        XCTAssertTrue(app.descendants(matching: .any)["camera.pages"].firstMatch.waitForExistence(timeout: 10), "The pages")
        XCTAssertTrue(app.buttons["options.button"].exists, "Options on the scanner tab too")
        XCTAssertTrue(app.buttons["save.button"].exists, "Save on the scanner tab too")
        XCTAssertEqual(app.buttons["scan.button"].label, "Scan page")
        XCTAssertTrue(app.buttons["import.photos"].exists, "Photos on the scanner tab too")
        app.switchToCamera()
        XCTAssertTrue(app.buttons["camera.shutter"].waitForExistence(timeout: 30), "The shutter again")
        XCTAssertFalse(app.buttons["scan.button"].exists, "No Scan in camera mode")
    }
}
