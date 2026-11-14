#if os(iOS)
import Foundation
import XCTest
@testable import LazyScanIOS
@testable import LazyScanKit

// The Home Screen icon's items: the types Info.plist lists and the kinds they open the camera on.

final class IOSQuickActionTests: XCTestCase {
    func testEveryItemOfTheInfoPlistIsAnAction() throws {
        let root: URL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let plist: URL = root.appendingPathComponent("ios/LazyScaniOS/Info.plist")
        let data: Data = try Data(contentsOf: plist)
        let info: [String: Any] = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let items: [[String: Any]] = try XCTUnwrap(info["UIApplicationShortcutItems"] as? [[String: Any]])
        let types: [String] = items.compactMap { (item: [String: Any]) -> String? in
            item["UIApplicationShortcutItemType"] as? String
        }
        let actions: [IOSQuickAction?] = types.map { (type: String) -> IOSQuickAction? in
            IOSQuickAction(shortcutType: type)
        }
        XCTAssertEqual(actions, [.document, .receipts, .idCard, .saved])
    }

    func testKinds() {
        XCTAssertEqual(IOSQuickAction.document.kind, .document)
        XCTAssertEqual(IOSQuickAction.receipts.kind, .receipts)
        XCTAssertEqual(IOSQuickAction.idCard.kind, .idCard)
        XCTAssertNil(IOSQuickAction.saved.kind)
    }

    func testAnUnknownTypeIsNoAction() {
        XCTAssertNil(IOSQuickAction(shortcutType: "com.lazyscan.lazyscan.quick.other"))
        XCTAssertNil(IOSQuickAction(shortcutType: "document"))
    }

    func testEveryCameraKindIsOneTheCameraOffers() {
        for action in IOSQuickAction.allCases {
            if let kind = action.kind {
                XCTAssertTrue(IOSShell.cameraKinds.contains(kind))
            }
        }
    }
}
#endif
