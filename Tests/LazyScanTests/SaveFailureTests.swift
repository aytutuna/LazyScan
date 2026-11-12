import XCTest
@testable import LazyScanKit

// Twin of windows/LazyScan.Core.Tests/SaveErrorsTests.cs: the same cases.

final class SaveFailureTests: XCTestCase {
    private let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Scans", isDirectory: true)

    private func posix(_ code: Int32) -> Error {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }

    override func setUpWithError() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testDiskFullNamesTheFolderAndKeepsThePages() {
        XCTAssertEqual(SaveFailure.message(posix(ENOSPC), folder: folder),
                       "There is not enough space to save in “Scans”. The pages are still in the queue.")
        let cocoa = CocoaError(.fileWriteOutOfSpace)
        XCTAssertEqual(SaveFailure.message(cocoa, folder: folder),
                       "There is not enough space to save in “Scans”. The pages are still in the queue.")
    }

    func testReadOnlyOrRefusedFolder() {
        let expected = "Files cannot be saved in “Scans”. It may be read-only. Choose another folder. The pages are still in the queue."
        XCTAssertEqual(SaveFailure.message(posix(EACCES), folder: folder), expected)
        XCTAssertEqual(SaveFailure.message(posix(EROFS), folder: folder), expected)
        XCTAssertEqual(SaveFailure.message(CocoaError(.fileWriteNoPermission), folder: folder), expected)
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileWriteUnknown.rawValue,
                              userInfo: [NSUnderlyingErrorKey: posix(EACCES)])
        XCTAssertEqual(SaveFailure.message(wrapped, folder: folder), expected)
    }

    func testMissingFolder() {
        let gone = folder.appendingPathComponent("Gone", isDirectory: true)
        let expected = "The folder “Gone” was not found. Choose another folder. The pages are still in the queue."
        XCTAssertEqual(SaveFailure.message(posix(ENOENT), folder: gone), expected)
        XCTAssertEqual(SaveFailure.message(nil, folder: gone), expected)
    }

    func testUnknownReasonStillNamesTheFolderNotTheTempFile() {
        let text = SaveFailure.message(NSError(domain: "test", code: 1,
                                               userInfo: [NSLocalizedDescriptionKey: "The file .1234.pdf.tmp is bad."]),
                                       folder: folder)
        XCTAssertEqual(text, "Could not save in “Scans”. The pages are still in the queue.")
    }

    func testNotSavedReasonDoesNotRepeatThePagesNote() {
        let error = ScanError.exportFailed(SaveFailure.message(posix(ENOSPC), folder: folder))
        XCTAssertEqual(SavePlan.failureReason(error), "There is not enough space to save in “Scans”.")
    }
}
