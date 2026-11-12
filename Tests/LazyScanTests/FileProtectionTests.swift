import Foundation
import XCTest
@testable import LazyScanKit

final class FileProtectionTests: XCTestCase {
    func testCreatesTheFolderAndItsParents() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("a", isDirectory: true).appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectoryCompleteUnlessOpen(at: folder)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        try FileManager.default.createDirectoryCompleteUnlessOpen(at: folder)
    }

    #if os(iOS) && !targetEnvironment(simulator)
    func testTheFolderIsCompleteUnlessOpen() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectoryCompleteUnlessOpen(at: folder)
        let attributes = try FileManager.default.attributesOfItem(atPath: folder.path)
        XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .completeUnlessOpen)
    }
    #endif
}
