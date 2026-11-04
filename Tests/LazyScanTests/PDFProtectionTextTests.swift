import XCTest
@testable import LazyScanKit

final class PDFProtectionTextTests: XCTestCase {
    /// The generated Turkish Kit table, as the iPhone bundle ships it.
    private static func turkishTable() throws -> [String: String] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("l10n/out/ios/tr.lproj/Kit.strings")
        return try XCTUnwrap(NSDictionary(contentsOf: file) as? [String: String])
    }

    func test_english_isTheDefault() {
        XCTAssertEqual(PDFProtection.dialogTitle, "Set a PDF password")
        XCTAssertEqual(PDFProtection.keptInQueueMessage(1),
                       "Not saved: no password was given for the protected PDF. The page is in the queue: save with a password, or turn the password off.")
        XCTAssertEqual(PDFProtection.keptInQueueMessage(3),
                       "Not saved: no password was given for the protected PDF. The 3 pages are in the queue: save with a password, or turn the password off.")
    }

    func test_turkish_texts() throws {
        try L10n.withTable(Self.turkishTable(), language: "tr") {
            XCTAssertEqual(PDFProtection.optionLabel, "Parola koruması")
            XCTAssertEqual(PDFProtection.dialogTitle, "PDF parolası belirleyin")
            XCTAssertEqual(PDFProtection.notWithArchivalReason, "PDF/A ile kullanılamaz")
            XCTAssertEqual(PDFProtection.notSavedMessage, "Kaydedilmedi: korumalı PDF için parola girilmedi.")
            XCTAssertEqual(PDFProtection.permissionsShortNote, "Bazı uygulamalar bu ayarları yok sayar.")
            let texts = [PDFProtection.optionHint, PDFProtection.optionHelp, PDFProtection.dialogMessage,
                         PDFProtection.dialogHelp, PDFProtection.permissionsNote]
            XCTAssertTrue(texts.allSatisfy { !$0.isEmpty && !$0.hasPrefix("PDFs") && !$0.hasPrefix("Most") })
        }
    }

    func test_turkish_keptInQueue_nounStaysSingular() throws {
        try L10n.withTable(Self.turkishTable(), language: "tr") {
            XCTAssertEqual(PDFProtection.keptInQueueMessage(1),
                           "Kaydedilmedi: korumalı PDF için parola girilmedi. Sayfa kuyrukta: parolayla kaydedin ya da parola korumasını kapatın.")
            XCTAssertEqual(PDFProtection.keptInQueueMessage(3),
                           "Kaydedilmedi: korumalı PDF için parola girilmedi. 3 sayfa kuyrukta: parolayla kaydedin ya da parola korumasını kapatın.")
            XCTAssertTrue(PDFProtection.keptInQueueMessage(1234).contains("1.234 sayfa kuyrukta"))
        }
    }
}
