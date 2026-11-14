#if os(iOS)
import Foundation
import XCTest
@testable import LazyScanIOS

// The one-time tips: the order they come in, what a dismissal remembers, and the launch arguments that keep them off.

final class IOSTipsTests: XCTestCase {
    private func freshDefaults() throws -> UserDefaults {
        let name: String = "tips-tests-" + UUID().uuidString
        let defaults: UserDefaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
        }
        return defaults
    }

    func testTheFirstTipIsOptionsAndTheyComeInOrder() throws {
        let defaults: UserDefaults = try freshDefaults()
        var seen: [IOSTip] = []
        while let tip = IOSTips.due(shown: defaults.bool(forKey: IOSTips.shownKey), step: defaults.integer(forKey: IOSTips.stepKey)) {
            seen.append(tip)
            IOSTips.dismiss(tip, defaults: defaults)
        }
        XCTAssertEqual(seen, [.options, .library, .save, .computer])
        XCTAssertTrue(defaults.bool(forKey: IOSTips.shownKey))
    }

    func testOnlyTheTipDueIsDismissed() throws {
        let defaults: UserDefaults = try freshDefaults()
        IOSTips.dismiss(.save, defaults: defaults)
        XCTAssertEqual(defaults.integer(forKey: IOSTips.stepKey), 0)
        IOSTips.dismiss(.options, defaults: defaults)
        XCTAssertEqual(defaults.integer(forKey: IOSTips.stepKey), IOSTip.library.rawValue)
        XCTAssertFalse(defaults.bool(forKey: IOSTips.shownKey))
    }

    func testProgressStaysAcrossLaunches() throws {
        let defaults: UserDefaults = try freshDefaults()
        IOSTips.dismiss(.options, defaults: defaults)
        IOSTips.dismiss(.library, defaults: defaults)
        XCTAssertEqual(IOSTips.due(shown: defaults.bool(forKey: IOSTips.shownKey), step: defaults.integer(forKey: IOSTips.stepKey)),
                       .save)
    }

    func testShowAgainStartsOver() throws {
        let defaults: UserDefaults = try freshDefaults()
        for tip in IOSTip.allCases {
            IOSTips.dismiss(tip, defaults: defaults)
        }
        IOSTips.reset(defaults: defaults)
        XCTAssertEqual(IOSTips.due(shown: defaults.bool(forKey: IOSTips.shownKey), step: defaults.integer(forKey: IOSTips.stepKey)),
                       .options)
    }

    func testKeysAndLaunchArguments() {
        XCTAssertEqual(IOSTips.shownKey, "tips.shown")
        XCTAssertEqual(IOSTips.stepKey, "tips.step")
        XCTAssertTrue(IOSLaunchOptions.hidesTips(["-noTips"]))
        XCTAssertTrue(IOSLaunchOptions.hidesTips(["-demoScanner"]))
        XCTAssertFalse(IOSLaunchOptions.hidesTips([]))
    }
}
#endif
