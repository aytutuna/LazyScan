import XCTest
import Foundation
@testable import LazyScanKit

// Twin of windows/LazyScan.Core.Tests/LazyPrintUrlTests.cs.
final class LazyPrintUrlTests: XCTestCase {
    func test_build_encodesThePathWhole() {
        XCTAssertEqual(LazyPrintUrl.build(["/Scans/scan.pdf"]), "lazyprint:open?file=%2FScans%2Fscan.pdf")
    }

    func test_build_repeatsFileForEachPathInOrder() {
        XCTAssertEqual(LazyPrintUrl.build(["/a.pdf", "/b.png", "/c.jpg"]),
                       "lazyprint:open?file=%2Fa.pdf&file=%2Fb.png&file=%2Fc.jpg")
    }

    func test_build_encodesSpacesAndSeparators() {
        XCTAssertEqual(LazyPrintUrl.build(["/My Scans/a&b=c+1#.pdf"]),
                       "lazyprint:open?file=%2FMy%20Scans%2Fa%26b%3Dc%2B1%23.pdf")
    }

    func test_build_encodesNonAsciiAsUtf8() {
        XCTAssertEqual(LazyPrintUrl.build(["/Belgeler/şiğli çay.pdf"]),
                       "lazyprint:open?file=%2FBelgeler%2F%C5%9Fi%C4%9Fli%20%C3%A7ay.pdf")
    }

    func test_build_readsBackToTheSamePaths() throws {
        let paths = ["/My Scans/a&b=c+1#.pdf", "/Belgeler/şiğli çay.pdf"]
        let query = try XCTUnwrap(LazyPrintUrl.build(paths).split(separator: "?").last)
        let back = query.split(separator: "&").map { String($0.dropFirst("file=".count)).removingPercentEncoding }
        XCTAssertEqual(back, paths)
    }

    func test_build_makesAnAddressTheSystemCanOpen() throws {
        let address = try XCTUnwrap(URL(string: LazyPrintUrl.build(["/My Scans/şiğli çay.pdf"])))
        XCTAssertEqual(address.scheme, LazyPrintUrl.scheme)
    }
}
