#if os(macOS)
import CoreGraphics
import XCTest
@testable import LazyScanKit
@testable import LazyScanMac

// What Quit names before it asks (`AppDelegate.unsavedWork`): the queue, else an open review, else an ID card
// side, in the words Windows asks with when its window is closed (`UnsavedWorkDescription` in
// MainWindow.xaml.cs, which has no test of its own).

/// A white picture of the test's own.
private func whiteImage() -> CGImage {
    let space: CGColorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: nil, width: 30, height: 40, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 30, height: 40))
    return context.makeImage()!
}

final class AppDelegateTests: XCTestCase {
    @MainActor
    func test_unsavedWork_namesTheQueueFirst_thenTheReview_thenTheCard() throws {
        let folder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppDelegateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let state = AppState(backends: [], presetStore: PresetStore(directory: folder),
                             files: AppStateFiles.all(in: folder))
        XCTAssertNil(AppDelegate.unsavedWork(state))

        let image: CGImage = whiteImage()
        let region = DetectedPhotoRegion(center: CGPoint(x: 15, y: 20), size: CGSize(width: 30, height: 40),
                                         angleDegrees: 0)
        state.idCardFront = DetectedPhoto(region: region, image: image, dpi: 60)
        XCTAssertEqual(AppDelegate.unsavedWork(state), "The ID card has not been saved.")
        state.showPhotoReview = true
        XCTAssertEqual(AppDelegate.unsavedWork(state), "The detected photos have not been saved.")
        state.isReceiptReview = true
        XCTAssertEqual(AppDelegate.unsavedWork(state), "The receipts found have not been saved.")
        state.scannedPages = [ScannedPage(image: image, dpi: 60, colorMode: .color)]
        XCTAssertEqual(AppDelegate.unsavedWork(state), "1 scanned page is still in the queue and not saved.")
        state.scannedPages = (0..<3).map { _ in ScannedPage(image: image, dpi: 60, colorMode: .color) }
        XCTAssertEqual(AppDelegate.unsavedWork(state), "3 scanned pages are still in the queue and not saved.")
    }
}
#endif
