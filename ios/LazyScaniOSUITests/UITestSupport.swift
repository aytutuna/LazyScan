import UIKit
import XCTest

// By identifier among every element: toolbar items and some rows are not buttons in the Simulator's tree.

extension XCUIApplication {
    /// What the Options sheet's Type row says for each kind (`IOSScanKind`): camera mode calls Photos "Photo".
    static let typeTitles: [String: [String]] = [
        "document": ["Document"], "photos": ["Photo", "Photos"], "receipts": ["Receipts"], "idCard": ["ID card"],
        "book": ["Book"], "text": ["Text"],
    ]

    /// Waits for the scan screen in either mode and says which: true for camera mode (its printer button),
    /// false for printer mode (its camera button). The app comes back in the mode the last run left.
    @MainActor
    @discardableResult
    func waitForScanScreen(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let printer: XCUIElement = descendants(matching: .any)["mode.printer"].firstMatch
        let camera: XCUIElement = descendants(matching: .any)["mode.camera"].firstMatch
        // The iPad starts on its task list; the scan screen is behind this button.
        let open: XCUIElement = descendants(matching: .any)["open.scanner"].firstMatch
        let deadline: Date = Date().addingTimeInterval(60)
        while Date() < deadline {
            if printer.exists { return true }
            if camera.exists { return false }
            if open.exists && open.isHittable { open.tap() }
            _ = printer.waitForExistence(timeout: 1)
        }
        XCTFail("The scan screen", file: file, line: line)
        return false
    }

    /// Camera mode, from printer mode by its camera button; nothing when it is up already.
    @MainActor
    func switchToCamera(file: StaticString = #filePath, line: UInt = #line) {
        guard !waitForScanScreen(file: file, line: line) else { return }
        let button: XCUIElement = descendants(matching: .any)["mode.camera"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "The camera button", file: file, line: line)
        waitUntilEnabled(button, "The camera button", file: file, line: line)
        button.tap()
        let printer: XCUIElement = descendants(matching: .any)["mode.printer"].firstMatch
        XCTAssertTrue(printer.waitForExistence(timeout: 30), "Camera mode's printer button", file: file, line: line)
        // The scanner tab is still there for a moment while the screens change places, and the next
        // question about the mode would be answered by it.
        waitUntilGone(button, "The scanner tab gone", file: file, line: line)
    }

    /// Printer mode, from camera mode by its printer button; nothing when it is up already. The scanner is
    /// the one picked last, which `pickScanner(_:)` picks when there is none.
    @MainActor
    func switchToPrinter(file: StaticString = #filePath, line: UInt = #line) {
        guard waitForScanScreen(file: file, line: line) else { return }
        let drawer: XCUIElement = descendants(matching: .any)["drawer"].firstMatch
        if drawer.exists {
            closeDrawer(file: file, line: line)
        }
        let button: XCUIElement = descendants(matching: .any)["mode.printer"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "The printer button", file: file, line: line)
        waitUntilEnabled(button, "The printer button", file: file, line: line)
        button.tap()
        let camera: XCUIElement = descendants(matching: .any)["mode.camera"].firstMatch
        XCTAssertTrue(camera.waitForExistence(timeout: 30), "The scanner tab's camera button", file: file, line: line)
        waitUntilGone(button, "Camera mode gone", file: file, line: line)
    }

    /// Picks what is scanned the way a person does, in either mode: Options, its Type row and the kind in
    /// its menu, then Done. `task` is the kind's name ("document", "photos", "idCard", "book", "receipts", and
    /// in printer mode "text"). The kind already picked changes nothing, and the app comes back on the task
    /// the last run left, so that one is set up afresh by way of another kind.
    @MainActor
    func pickTask(_ task: String, file: StaticString = #filePath, line: UInt = #line) {
        waitForScanScreen(file: file, line: line)
        openOptions(file: file, line: line)
        if typeShown == task {
            chooseType(task == "document" ? "photos" : "document", file: file, line: line)
        }
        chooseType(task, file: file, line: line)
        closeOptions(file: file, line: line)
    }

    /// Picks `task` in the Options sheet's Type menu, opening the sheet when it is not up, and leaves it
    /// open (a question about the pages queued closes it).
    @MainActor
    func chooseType(_ task: String, file: StaticString = #filePath, line: UInt = #line) {
        let done: XCUIElement = descendants(matching: .any)["options.done"].firstMatch
        if !done.exists {
            openOptions(file: file, line: line)
        }
        let menu: XCUIElement = descendants(matching: .any)["options.type"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 30), "The Type row", file: file, line: line)
        waitUntilEnabled(menu, "The Type row", file: file, line: line)
        menu.tap()
        let item: XCUIElement = descendants(matching: .any)["type.\(task)"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), "The \(task) type", file: file, line: line)
        waitUntilEnabled(item, "The \(task) type", file: file, line: line)
        item.tap()
    }

    /// Waits until the Type row says `task`.
    @MainActor
    func waitForType(_ task: String, file: StaticString = #filePath, line: UInt = #line) {
        let menu: XCUIElement = descendants(matching: .any)["options.type"].firstMatch
        let titles: [String] = XCUIApplication.typeTitles[task] ?? []
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate { (_: Any?, _: [String: Any]?) -> Bool in
            titles.contains(menu.value as? String ?? "")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 30), .completed, "The \(task) type picked",
                       file: file, line: line)
    }

    /// The kind the Type row of the Options sheet, which is open, says: "document"; empty when none.
    @MainActor
    private var typeShown: String {
        let menu: XCUIElement = descendants(matching: .any)["options.type"].firstMatch
        guard menu.waitForExistence(timeout: 30), let value = menu.value as? String else { return "" }
        for (kind, titles) in XCUIApplication.typeTitles where titles.contains(value) {
            return kind
        }
        return ""
    }

    /// Opens the options drawer on a group: "colour", "scanner" (printer mode), "flash" or "camera" (camera
    /// mode).
    @MainActor
    func openDrawer(_ group: String, file: StaticString = #filePath, line: UInt = #line) {
        let drawer: XCUIElement = descendants(matching: .any)["drawer"].firstMatch
        if !drawer.exists {
            let toggle: XCUIElement = descendants(matching: .any)["drawer.toggle"].firstMatch
            XCTAssertTrue(toggle.waitForExistence(timeout: 30), "The drawer's arrow", file: file, line: line)
            toggle.tap()
            XCTAssertTrue(drawer.waitForExistence(timeout: 10), "The options drawer", file: file, line: line)
        }
        let button: XCUIElement = descendants(matching: .any)["drawer.\(group)"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "The drawer's \(group) group", file: file, line: line)
        button.tap()
        waitUntilSelected(button, "The drawer's \(group) group picked", file: file, line: line)
    }

    /// Closes the options drawer.
    @MainActor
    func closeDrawer(file: StaticString = #filePath, line: UInt = #line) {
        let toggle: XCUIElement = descendants(matching: .any)["drawer.toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "The drawer's arrow", file: file, line: line)
        toggle.tap()
        waitUntilGone(descendants(matching: .any)["drawer"].firstMatch, "The drawer closed", file: file, line: line)
    }

    /// The element by identifier, the printer screen's list scrolled until it is on screen: the list makes
    /// its rows only as they come into view, so one below the fold is not in the tree yet.
    @MainActor
    func scrolledTo(_ id: String) -> XCUIElement {
        let element: XCUIElement = descendants(matching: .any)[id].firstMatch
        var swipes: Int = 0
        while !(element.waitForExistence(timeout: 2) && element.isHittable) && swipes < 8 {
            if swipes < 3 {
                swipeUp()
            } else {
                swipeDown()
            }
            swipes += 1
        }
        return element
    }

    /// Opens a sheet as its button or row does, in either mode: "Options" (the Type, what is saved, the
    /// actions on the pages) from the bottom bar, or "Scanner" (the scanners, then the flatbed's preview)
    /// from the scanner tab's row.
    @MainActor
    func openOptions(_ group: String = "Options", file: StaticString = #filePath, line: UInt = #line) {
        if group == "Scanner" {
            let row: XCUIElement = scrolledTo("options.row.scanner")
            XCTAssertTrue(row.exists && row.isHittable, "The Scanner row", file: file, line: line)
            row.tap()
        } else {
            let button: XCUIElement = descendants(matching: .any)["options.button"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 30), "The Options button", file: file, line: line)
            waitUntilEnabled(button, "The Options button", file: file, line: line)
            button.tap()
        }
        let done: XCUIElement = descendants(matching: .any)["options.done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10), "The \(group) sheet", file: file, line: line)
    }

    /// Opens a page of the Options sheet, which is open, from its row: "saveAs", "look", "pages", "separate",
    /// "fileName", "afterSaving", "scanner" (printer mode), "camera", "shareNow", "presets", "computer" or
    /// "help". The sheet opens at half height, so it is grown when the row is out of reach.
    @MainActor
    func openPage(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let id: String = "options.page.\(name)"
        var row: XCUIElement = descendants(matching: .any)[id].firstMatch
        if !(row.waitForExistence(timeout: 10) && row.isHittable) {
            growOptions()
            row = scrolledTo(id)
        }
        XCTAssertTrue(row.exists && row.isHittable, "The \(name) page's row", file: file, line: line)
        row.tap()
        XCTAssertTrue(navigationBars.buttons["BackButton"].firstMatch.waitForExistence(timeout: 10), "The \(name) page",
                      file: file, line: line)
    }

    /// Goes back from a page to the Options list.
    @MainActor
    func closePage(file: StaticString = #filePath, line: UInt = #line) {
        let back: XCUIElement = navigationBars.buttons["BackButton"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "The back button", file: file, line: line)
        back.tap()
        waitUntilGone(back, "The page closed", file: file, line: line)
    }

    /// In printer mode, opens the Scanner options and picks the scanner there by its row
    /// ("scanner.row.mock:demo" for the demo scanner). The sheet closes on the pick. The app keeps the
    /// scanner from run to run.
    @MainActor
    func pickScanner(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        // The iPad lists the scanners in its sidebar, beside the screen.
        if UIDevice.current.userInterfaceIdiom == .pad {
            let listed: XCUIElement = descendants(matching: .any)[id].firstMatch
            XCTAssertTrue(listed.waitForExistence(timeout: 30), "The \(id) row in the sidebar", file: file, line: line)
            // As on the iPhone, a pick right after launch may not take, so the row is tapped again until it
            // shows as selected, three times at most.
            var tries: Int = 0
            repeat {
                waitUntilEnabled(listed, "The \(id) row", file: file, line: line)
                listed.tap()
                tries += 1
            } while !selects(listed, timeout: 10) && tries < 3
            XCTAssertTrue(listed.isSelected, "The \(id) row is picked", file: file, line: line)
            return
        }
        openOptions("Scanner", file: file, line: line)
        let row: XCUIElement = descendants(matching: .any)[id].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "The \(id) row in the Scanner options", file: file, line: line)
        let done: XCUIElement = descendants(matching: .any)["options.done"].firstMatch
        // Right after launch a pick may not take (the app busy for a moment, or the selection still following
        // the mode as the scanners are listed), so the row is tapped again until the sheet closes, three
        // times at most.
        var taps: Int = 0
        repeat {
            waitUntilEnabled(row, "The \(id) row", file: file, line: line)
            row.tap()
            taps += 1
        } while !closes(done, timeout: 10) && taps < 3
        waitUntilGone(done, "The Scanner options closed on the pick", file: file, line: line)
    }

    @MainActor
    private func selects(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let picked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: element)
        return XCTWaiter.wait(for: [picked], timeout: timeout) == .completed
    }

    @MainActor
    private func closes(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter.wait(for: [gone], timeout: timeout) == .completed
    }

    /// Drags a sheet from half height to full: the scanner's settings sit below the list, and the list makes
    /// its rows only once they come on screen.
    @MainActor
    func growOptions() {
        // The sheet's bar is the row Done sits in; the bar itself has no identifier to ask for.
        let done: XCUIElement = descendants(matching: .any)["options.done"].firstMatch
        guard done.waitForExistence(timeout: 10) else { return }
        let bar: XCUICoordinate = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: done.frame.midY / frame.height))
        bar.press(forDuration: 0.1, thenDragTo: coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
    }

    /// Closes the sheet with Done.
    @MainActor
    func closeOptions(file: StaticString = #filePath, line: UInt = #line) {
        let done: XCUIElement = descendants(matching: .any)["options.done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10), "The options' Done", file: file, line: line)
        done.tap()
        waitUntilGone(done, "The options' sheet closed", file: file, line: line)
    }

    /// Turns an Options switch on or off by its identifier and waits until it says so. A SwiftUI toggle's
    /// row is not always what takes the tap, so its switch is tapped when the tree has one.
    @MainActor
    func turnSwitch(_ id: String, on: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let toggle: XCUIElement = switches[id].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 30), "The \(id) switch", file: file, line: line)
        let wanted: String = on ? "1" : "0"
        let turned: () -> XCTNSPredicateExpectation = {
            XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", wanted), object: toggle)
        }
        if (toggle.value as? String) != wanted {
            let inner: XCUIElement = toggle.switches.firstMatch
            let target: XCUIElement = inner.exists ? inner : toggle
            target.tap()
            // The first tap now and then lands while the drawer is still settling and does nothing.
            if XCTWaiter.wait(for: [turned()], timeout: 8) != .completed, (toggle.value as? String) != wanted {
                target.tap()
            }
        }
        XCTAssertEqual(XCTWaiter.wait(for: [turned()], timeout: 10), .completed, "\(id) turned \(on ? "on" : "off")",
                       file: file, line: line)
    }

    /// The kind picked, in either mode: "document"; empty when none is. Reads the Type row of the Options
    /// sheet, which it opens and closes.
    @MainActor
    var pickedKind: String {
        waitForScanScreen()
        openOptions()
        let kind: String = typeShown
        closeOptions()
        return kind
    }

    /// The pages' button, the same stack on both tabs.
    @MainActor
    var pagesButton: XCUIElement {
        descendants(matching: .any)["camera.pages"].firstMatch
    }

    /// Waits for the pages' button to count `count` pages, then opens the page strip's sheet and waits for
    /// the last page's cell.
    @MainActor
    func openPages(_ count: Int, timeout: TimeInterval = 240, file: StaticString = #filePath, line: UInt = #line) {
        waitForScanScreen(file: file, line: line)
        let pages: XCUIElement = pagesButton
        XCTAssertTrue(pages.waitForPageCount(count, timeout: timeout), "\(count) on the pages' button",
                      file: file, line: line)
        pages.tap()
        let cell: XCUIElement = descendants(matching: .any)["page.\(count)"]
        XCTAssertTrue(cell.waitForExistence(timeout: 30), "Page \(count) in the page strip", file: file, line: line)
    }

    /// Closes the page strip's sheet with Done.
    @MainActor
    func closePages(file: StaticString = #filePath, line: UInt = #line) {
        let done: XCUIElement = descendants(matching: .any)["pages.done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10), "The page strip's Done", file: file, line: line)
        done.tap()
        waitUntilGone(done, "The page strip closed", file: file, line: line)
    }

    @MainActor
    func waitUntilEnabled(_ element: XCUIElement, _ message: String, timeout: TimeInterval = 60,
                          file: StaticString = #filePath, line: UInt = #line) {
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: timeout), .completed, "\(message) enabled",
                       file: file, line: line)
    }

    @MainActor
    private func waitUntilSelected(_ element: XCUIElement, _ message: String, file: StaticString, line: UInt) {
        let picked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [picked], timeout: 30), .completed, message, file: file, line: line)
    }

    @MainActor
    private func waitUntilGone(_ element: XCUIElement, _ message: String, file: StaticString, line: UInt) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 30), .completed, message, file: file, line: line)
    }
}

extension XCUIElement {
    /// The number a pages' button counts: its label says it in digits, except that Arabic spells out
    /// none, one and two.
    var pageCount: Int? {
        if let count = Int(label.filter(\.isNumber)) {
            return count
        }
        return ["لا توجد صفحات": 0, "صفحة واحدة": 1, "صفحتان": 2][label]
    }

    @MainActor
    func waitForPageCount(_ count: Int, timeout: TimeInterval) -> Bool {
        let counted = XCTNSPredicateExpectation(predicate: NSPredicate { (_: Any?, _: [String: Any]?) -> Bool in
            self.pageCount == count
        }, object: nil)
        return XCTWaiter.wait(for: [counted], timeout: timeout) == .completed
    }
}
