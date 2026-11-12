import XCTest
@testable import LazyScanKit

@MainActor
final class PhoneWordingTests: XCTestCase {
    private func phoneTexts() -> [String] {
        PhoneWording.choosing(phone: true) {
            var texts: [String] = []
            for format in [OutputFormat.word, .text] {
                for unreadable in [true, false] {
                    for count in [1, 3] {
                        texts.append(TextExport.keptInQueue(format: format, pageCount: count, cancelled: false, textUnreadable: unreadable))
                    }
                }
                texts.append(TextExport.keptInQueue(format: format, pageCount: 2, cancelled: true))
            }
            for count in [1, 3] {
                for cancelled in [false, true] {
                    texts.append(TextExport.pagesKeptInQueue(pageCount: count, written: 0, cancelled: cancelled, saveTitle: "Save PDF"))
                }
            }
            for rest in [1, 3] {
                for cancelled in [false, true] {
                    texts.append(TextExport.pagesKeptInQueue(pageCount: 5, written: 5 - rest, cancelled: cancelled, saveTitle: "Save JPEG (3 pages)"))
                }
            }
            texts.append(SaveFailure.pagesKept)
            texts.append(SavePlan.notSavedMessage("The folder is full."))
            texts.append(PageFilter.nothingToSaveMessage)
            texts.append(PDFProtection.keptInQueueMessage(1))
            texts.append(PDFProtection.keptInQueueMessage(4))
            texts.append(PhotoImport.notOfferedMessage(for: TaskCatalog.apply(.receipt, to: ScanSettings())))
            texts.append(PhotoImport.notOfferedMessage(for: ScanSettings()))
            texts.append(AppState.undoneMessage)
            texts.append(AppState.undoneAppendMessage("Contract.pdf"))
            return texts
        }
    }

    func test_phoneTexts_haveNoQueueNoPressSaveAndNoTask() {
        for text in phoneTexts() {
            let lower = text.lowercased()
            XCTAssertFalse(lower.contains("queue"), text)
            XCTAssertFalse(lower.contains("press "), text)
            XCTAssertFalse(lower.contains("task"), text)
            XCTAssertFalse(lower.contains("save pdf"), text)
            XCTAssertFalse(lower.contains("save word"), text)
        }
    }

    func test_phoneTexts_sayWhatToTap() {
        PhoneWording.choosing(phone: true) {
            XCTAssertEqual(TextExport.keptInQueue(format: .word, pageCount: 3, cancelled: false),
                           "The 3 pages were not saved: tap Save once the text can be read, or choose PDF to save them as scanned.")
            XCTAssertEqual(TextExport.pagesKeptInQueue(pageCount: 1, written: 0, cancelled: false, saveTitle: "Save PDF"),
                           "Not saved \u{2014} the page is still here: tap Save to try again.")
            XCTAssertEqual(TextExport.pagesKeptInQueue(pageCount: 5, written: 2, cancelled: true, saveTitle: "Save JPEG (3 pages)"),
                           "Cancelled. Pages saved: 2 of 5. The other 3 are still here.")
            XCTAssertEqual(TextExport.pagesKeptInQueue(pageCount: 5, written: 2, cancelled: false, saveTitle: "Save JPEG (3 pages)"),
                           "Pages saved: 2 of 5. The other 3 are still here: tap Save to try again.")
            XCTAssertEqual(AppState.undoneMessage, "Save undone: the pages are back.")
            XCTAssertEqual(PhotoImport.notOfferedMessage(for: ScanSettings()),
                           "Photos of documents are added as pages: pick a document type, with Collect pages before saving on, to import them.")
        }
    }

    func test_desktopTexts_keepTheQueueWording() {
        PhoneWording.choosing(phone: false) {
            XCTAssertEqual(TextExport.keptInQueue(format: .word, pageCount: 3, cancelled: false),
                           "The 3 pages are kept in the queue: press Save Word once the text can be read, or choose PDF to save them as scanned.")
            XCTAssertEqual(SaveFailure.pagesKept, "The pages are still in the queue.")
            XCTAssertEqual(AppState.undoneMessage, "Save undone: the pages are in the queue again.")
        }
    }

    func test_clearedStatusLine_saysPagesOnThePhone() {
        PhoneWording.choosing(phone: true) {
            XCTAssertEqual(StatusLine.short("Pages cleared.", StatusDetail(head: .queueCleared(0))), "Pages cleared")
        }
        PhoneWording.choosing(phone: false) {
            XCTAssertEqual(StatusLine.short("Page queue cleared.", StatusDetail(head: .queueCleared(0))), "Queue cleared")
        }
    }
}
