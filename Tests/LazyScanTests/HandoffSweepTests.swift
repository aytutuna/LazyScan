import Foundation
import XCTest
@testable import LazyScanKit

// The launch sweep of the Lazy Print hand-off files: a day-old file goes, a fresh one stays.

@MainActor
final class HandoffSweepTests: XCTestCase {
    func testSweepDeletesDayOldFilesOnly() throws {
        let manager: FileManager = FileManager.default
        let folder: URL = manager.temporaryDirectory.appendingPathComponent("LazyScan-print", isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let old: URL = folder.appendingPathComponent("sweep-test-old.pdf")
        let fresh: URL = folder.appendingPathComponent("sweep-test-fresh.pdf")
        try Data([1]).write(to: old)
        try Data([1]).write(to: fresh)
        defer {
            try? manager.removeItem(at: old)
            try? manager.removeItem(at: fresh)
        }
        let twoDaysAgo: Date = Date().addingTimeInterval(-2 * 86400)
        try manager.setAttributes([.modificationDate: twoDaysAgo], ofItemAtPath: old.path)

        AppState.sweepHandoffs()

        XCTAssertFalse(manager.fileExists(atPath: old.path))
        XCTAssertTrue(manager.fileExists(atPath: fresh.path))
    }
}
