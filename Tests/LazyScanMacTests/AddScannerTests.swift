#if os(macOS)
import LazyScanKit
import XCTest
@testable import LazyScanMac

// Add by address on the Mac: the Windows messages, the question about a certificate seen for the first time
// and about a changed one, and the scanner added once the check answers.

@MainActor
private final class FakeAddressChecker: MacAddressChecking {
    var results: [EsclAddressCheck] = []
    var firstUses: [String?] = []
    var added: [ScannerAddress] = []
    var trusted: [String] = []

    func checkAddress(_ address: ScannerAddress, firstUse: String?) async throws -> EsclAddressCheck {
        firstUses.append(firstUse)
        if results.count > 1 {
            return results.removeFirst()
        }
        return results[0]
    }

    func addAddress(_ address: ScannerAddress, capabilities: EsclCapabilities) -> String {
        added.append(address)
        return "escl:added"
    }

    func trustCertificate(_ certificate: EsclCertificateError, deviceUuid: String?, name: String) {
        trusted.append(certificate.fingerprint)
    }
}

final class AddScannerTests: XCTestCase {
    private func certificate(_ verdict: EsclTrustVerdict) -> EsclCertificateError {
        EsclCertificateError(verdict: verdict, deviceName: "192.168.1.50", deviceUuid: nil, authority: "192.168.1.50:443",
                             fingerprint: verdict == .changed ? "bbbb" : "aaaa", subject: "CN=Scanner")
    }

    private func answers(_ address: ScannerAddress) -> EsclAddressCheck {
        EsclAddressCheck(address: address, capabilities: EsclCapabilities(makeAndModel: "Office MFP", uuid: "u-1"),
                         certificate: nil, error: nil)
    }

    @MainActor
    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool,
                           file: StaticString = #filePath, line: UInt = #line) async throws {
        let deadline: Date = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out after \(timeout) s", file: file, line: line)
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @MainActor
    func test_saysWhatIsWrongWithTheAddress_asWindowsDoes() async {
        let model = MacAddScannerModel(checker: FakeAddressChecker())
        let cases: [String: String] = [
            "": "Enter the scanner's IP address or host name.",
            "300.1.1.1": "“300.1.1.1” is not a valid IP address or host name.",
            "my scanner": "An address cannot contain spaces.",
            "scanner:0": "The port must be a number from 1 to 65535.",
            "ftp://10.0.0.7": "Use an address that starts with http:// or https://, or just the IP address or host name.",
        ]
        for text in cases.keys.sorted() {
            model.text = text
            let added: Bool = await model.add()
            XCTAssertFalse(added, text)
            XCTAssertEqual(model.message, cases[text], text)
            XCTAssertFalse(model.isChecking)
        }
        model.textChanged()
        XCTAssertNil(model.message)
    }

    @MainActor
    func test_addsTheScannerThatAnswers() async throws {
        let address = try ScannerAddress.parse("192.168.1.50")
        let checker = FakeAddressChecker()
        checker.results = [answers(address)]
        let model = MacAddScannerModel(checker: checker)
        model.text = "192.168.1.50"
        let added: Bool = await model.add()
        XCTAssertTrue(added)
        XCTAssertEqual(checker.added, [address])
        XCTAssertEqual(model.addedDeviceID, "escl:added")
        XCTAssertNil(model.message)
    }

    @MainActor
    func test_whenNothingAnswers_saysSo() async throws {
        let address = try ScannerAddress.parse("192.168.1.50")
        let checker = FakeAddressChecker()
        checker.results = [EsclAddressCheck(address: address, capabilities: nil, certificate: nil, error: nil)]
        let model = MacAddScannerModel(checker: checker)
        model.text = "192.168.1.50"
        let added: Bool = await model.add()
        XCTAssertFalse(added)
        XCTAssertEqual(model.message, "No scanner answered at https://192.168.1.50.")
        XCTAssertEqual(checker.firstUses, [nil, nil])
        XCTAssertTrue(checker.added.isEmpty)
        XCTAssertFalse(model.isChecking)
    }

    @MainActor
    func test_asksBeforeTrustingANewCertificate() async throws {
        let address = try ScannerAddress.parse("https://192.168.1.50")
        let checker = FakeAddressChecker()
        checker.results = [
            EsclAddressCheck(address: address, capabilities: nil, certificate: certificate(.unknown), error: nil),
            answers(address),
        ]
        let model = MacAddScannerModel(checker: checker)
        model.text = "https://192.168.1.50"

        let refusing: Task<Bool, Never> = Task { @MainActor () -> Bool in
            await model.add()
        }
        try await waitUntil(5) { model.certificateQuestion != nil }
        XCTAssertEqual(model.message, "Confirm the scanner's certificate to continue.")
        model.answerCertificate(false)
        let refused: Bool = await refusing.value
        XCTAssertFalse(refused)
        XCTAssertEqual(model.message, "The scanner was not added, because its certificate was not trusted.")
        XCTAssertTrue(checker.added.isEmpty)

        checker.results = [
            EsclAddressCheck(address: address, capabilities: nil, certificate: certificate(.unknown), error: nil),
            answers(address),
        ]
        let trusting: Task<Bool, Never> = Task { @MainActor () -> Bool in
            await model.add()
        }
        try await waitUntil(5) { model.certificateQuestion != nil }
        model.answerCertificate(true)
        let trusted: Bool = await trusting.value
        XCTAssertTrue(trusted)
        XCTAssertEqual(checker.firstUses.suffix(2), [nil, "aaaa"])
        XCTAssertEqual(checker.added, [address])
        XCTAssertTrue(checker.trusted.isEmpty)
    }

    @MainActor
    func test_pinsAChangedCertificateOnlyWhenTheUserTrustsIt() async throws {
        let address = try ScannerAddress.parse("https://192.168.1.50")
        let changed = certificate(.changed)
        let checker = FakeAddressChecker()
        checker.results = [
            EsclAddressCheck(address: address, capabilities: nil, certificate: changed, error: nil),
            answers(address),
        ]
        let model = MacAddScannerModel(checker: checker)
        model.text = "https://192.168.1.50"
        let trusting: Task<Bool, Never> = Task { @MainActor () -> Bool in
            await model.add()
        }
        try await waitUntil(5) { model.certificateQuestion != nil }
        model.answerCertificate(true)
        let trusted: Bool = await trusting.value
        XCTAssertTrue(trusted)
        XCTAssertEqual(checker.trusted, ["bbbb"])
        XCTAssertEqual(checker.added, [address])
    }

    @MainActor
    func test_closingTheSheetAbandonsTheQuestion() async throws {
        let address = try ScannerAddress.parse("https://192.168.1.50")
        let checker = FakeAddressChecker()
        checker.results = [EsclAddressCheck(address: address, capabilities: nil, certificate: certificate(.unknown), error: nil)]
        let model = MacAddScannerModel(checker: checker)
        model.text = "https://192.168.1.50"
        var finished: [Bool] = []
        model.start { (added: Bool) in finished.append(added) }
        try await waitUntil(5) { model.certificateQuestion != nil }
        model.cancel()
        try await waitUntil(5) { !finished.isEmpty }
        XCTAssertEqual(finished, [false])
        XCTAssertTrue(checker.added.isEmpty)
        XCTAssertTrue(checker.trusted.isEmpty)
        XCTAssertNil(model.certificateQuestion)
    }

    func test_certificateTexts() {
        let first = certificate(.unknown)
        XCTAssertEqual(MacCertificateText.title(first), "Trust the scanner at 192.168.1.50:443?")
        XCTAssertEqual(MacCertificateText.trustButton(first), "Trust and add")
        XCTAssertTrue(MacCertificateText.message(first).contains("macOS cannot vouch for such certificates"))
        XCTAssertTrue(MacCertificateText.message(first).contains("Fingerprint\nAA:AA"))
        let changed = certificate(.changed)
        XCTAssertEqual(MacCertificateText.title(changed), "Scanner certificate changed")
        XCTAssertEqual(MacCertificateText.trustButton(changed), "Trust the new certificate")
        XCTAssertTrue(MacCertificateText.message(changed).contains("New fingerprint\nBB:BB"))
    }
}
#endif
