import XCTest
import Foundation
@testable import LazyScanKit

// Mirrors windows/LazyScan.Core.Tests/PairingSessionTests.cs (same clock steps, same answers).

final class PairingSessionTests: XCTestCase {
    /// 2026-10-20T08:30:00Z.
    private let opened = Date(timeIntervalSince1970: 1_792_485_000)

    private func makeSession() throws -> PairingSession {
        try PairingSession(opened: opened, token: CompanionVectors.token)
    }

    private func minutes(_ value: Double) -> Date { opened.addingTimeInterval(value * 60) }

    func testToken_IsTheGivenBytesOrRandom() throws {
        XCTAssertEqual(try makeSession().token, CompanionVectors.tokenText)
        let a = try PairingSession(opened: opened)
        let b = try PairingSession(opened: opened)
        XCTAssertNotEqual(a.token, b.token)
        XCTAssertEqual(CompanionProtocol.decodeBase64Url(a.token)?.count, 16)
        XCTAssertThrowsError(try PairingSession(opened: opened, token: Data(count: 15)))
    }

    func testRightToken_IsAcceptedOnce() throws {
        let session = try makeSession()
        XCTAssertEqual(session.state(at: opened), .open)
        XCTAssertEqual(session.redeem(CompanionVectors.tokenText, now: minutes(1)), .accepted)
        XCTAssertEqual(session.state(at: minutes(1)), .used)
        XCTAssertEqual(session.redeem(CompanionVectors.tokenText, now: minutes(2)), .alreadyUsed)
        XCTAssertEqual(session.redeem("wrong", now: minutes(2)), .alreadyUsed)
        XCTAssertEqual(session.remaining(at: minutes(2)), 0)
    }

    func testToken_ExpiresAfterFiveMinutes() throws {
        let session = try makeSession()
        XCTAssertEqual(session.remaining(at: opened), 300)
        XCTAssertEqual(session.remaining(at: minutes(5).addingTimeInterval(-1)), 1)
        XCTAssertEqual(session.state(at: minutes(5)), .expired)
        XCTAssertEqual(session.redeem(CompanionVectors.tokenText, now: minutes(5)), .expired)
        XCTAssertEqual(session.redeem(CompanionVectors.tokenText, now: minutes(1)), .expired)
        XCTAssertEqual(try makeSession().redeem(CompanionVectors.tokenText, now: minutes(5).addingTimeInterval(-0.001)), .accepted)
    }

    func testWrongTokens_DoNotCloseTheSession() throws {
        let session = try makeSession()
        let almost = String(CompanionVectors.tokenText.dropLast()) + "x"
        for i in 1...6 {
            XCTAssertEqual(session.redeem(almost, now: opened), .wrongToken)
            XCTAssertEqual(session.failedAttempts, i)
            XCTAssertEqual(session.state(at: opened), .open)
        }
        XCTAssertEqual(session.redeem(CompanionVectors.tokenText, now: opened), .accepted)
    }

    func testMalformedTokens_CountAsWrong() throws {
        let session = try makeSession()
        XCTAssertEqual(session.redeem("", now: opened), .wrongToken)
        XCTAssertEqual(session.redeem("AAECAwQFBgcICQoLDA0ODw==", now: opened), .wrongToken)
        XCTAssertEqual(session.redeem(CompanionVectors.tokenText + "AA", now: opened), .wrongToken)
        XCTAssertEqual(session.failedAttempts, 3)
        XCTAssertEqual(session.redeem(CompanionVectors.tokenText, now: opened), .accepted)
    }

    func testClose_RefusesTheToken() throws {
        let session = try makeSession()
        session.close()
        XCTAssertEqual(session.state(at: opened), .closed)
        XCTAssertEqual(session.redeem(CompanionVectors.tokenText, now: opened), .closed)
        let used = try makeSession()
        _ = used.redeem(CompanionVectors.tokenText, now: opened)
        used.close()
        XCTAssertEqual(used.state(at: opened), .used)
    }

    func testCode_IsTheGivenDigitsOrRandom() throws {
        let session = try PairingSession(opened: opened, token: CompanionVectors.token, code: "482913")
        XCTAssertEqual(session.code, "482913")
        XCTAssertEqual(session.formattedCode, "482 913")
        let random = try PairingSession(opened: opened)
        XCTAssertEqual(random.code.count, 6)
        XCTAssertTrue(random.code.allSatisfy { $0 >= "0" && $0 <= "9" })
        XCTAssertEqual(try PairingSession(opened: opened, code: "000042").formattedCode, "000 042")
        for bad in ["", "12345", "1234567", "12a456", "12 456"] {
            XCTAssertThrowsError(try PairingSession(opened: opened, code: bad))
        }
    }

    func testRightCode_KeepsTheSessionOpenForTheToken() throws {
        let session = try PairingSession(opened: opened, token: CompanionVectors.token, code: "482913")
        XCTAssertEqual(session.checkCode("482913", now: minutes(1)), .right)
        XCTAssertEqual(session.checkCode("482 913", now: minutes(2)), .right)
        XCTAssertEqual(session.state(at: minutes(2)), .open)
        XCTAssertEqual(session.failedCodes, 0)
        XCTAssertEqual(session.redeem(CompanionVectors.tokenText, now: minutes(3)), .accepted)
        XCTAssertEqual(session.checkCode("482913", now: minutes(3)), .alreadyUsed)
    }

    func testWrongCodes_CloseTheSessionAtTheFifth() throws {
        let session = try PairingSession(opened: opened, token: CompanionVectors.token, code: "482913")
        for i in 1...4 {
            XCTAssertEqual(session.checkCode("482914", now: opened), .wrong)
            XCTAssertEqual(session.failedCodes, i)
            XCTAssertEqual(session.state(at: opened), .open)
        }
        XCTAssertEqual(session.checkCode("000000", now: opened), .tooManyAttempts)
        XCTAssertEqual(session.state(at: opened), .closed)
        XCTAssertEqual(session.checkCode("482913", now: opened), .closed)
        XCTAssertEqual(session.redeem(CompanionVectors.tokenText, now: opened), .closed)
    }

    func testRightCode_DoesNotWipeTheWrongOnes() throws {
        let session = try PairingSession(opened: opened, code: "482913")
        for _ in 1...4 {
            XCTAssertEqual(session.checkCode("111111", now: opened), .wrong)
        }
        XCTAssertEqual(session.checkCode("482913", now: opened), .right)
        XCTAssertEqual(session.checkCode("111111", now: opened), .tooManyAttempts)
    }

    func testMalformedCodes_CountAsWrong() throws {
        let session = try PairingSession(opened: opened, code: "482913")
        XCTAssertEqual(session.checkCode(nil, now: opened), .wrong)
        XCTAssertEqual(session.checkCode("", now: opened), .wrong)
        XCTAssertEqual(session.checkCode("48291", now: opened), .wrong)
        XCTAssertEqual(session.checkCode("4829133", now: opened), .wrong)
        XCTAssertEqual(session.failedCodes, 4)
        XCTAssertEqual(session.failedAttempts, 0)
    }

    func testCode_ExpiresWithTheSession() throws {
        let session = try PairingSession(opened: opened, code: "482913")
        XCTAssertEqual(session.checkCode("482913", now: minutes(5)), .expired)
        XCTAssertEqual(session.checkCode("482913", now: minutes(1)), .expired)
        XCTAssertEqual(session.failedCodes, 0)
    }
}
