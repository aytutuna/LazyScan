#if os(iOS)
import AVFoundation
import CoreGraphics
import Foundation
import XCTest
@testable import LazyScanIOS
@testable import LazyScanKit

// The camera's availability and its one-line reasons (the Simulator has none), what the scan screen
// offers to save (`IOSShell`); the launch option the import UI test uses.

/// A white page of `width` × `height` with a dark bar.
private func scannedPicture(width: Int, height: Int) -> CGImage {
    let ctx: CGContext = ImportTestSupport.context(width: width, height: height)
    ctx.setFillColor(CGColor(srgbRed: 0.97, green: 0.97, blue: 0.96, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 1))
    ctx.fill(CGRect(x: width / 8, y: height / 2, width: width * 3 / 4, height: max(4, height / 30)))
    return ctx.makeImage()!
}

final class IOSCaptureTests: XCTestCase {
    func test_cameraAvailability_andItsReasons() {
        XCTAssertEqual(IOSCameraAvailability.resolve(isSupported: false, authorization: .authorized), .noCamera)
        XCTAssertEqual(IOSCameraAvailability.resolve(isSupported: false, authorization: .denied), .noCamera)
        XCTAssertEqual(IOSCameraAvailability.resolve(isSupported: true, authorization: .denied), .denied)
        XCTAssertEqual(IOSCameraAvailability.resolve(isSupported: true, authorization: .restricted), .restricted)
        XCTAssertEqual(IOSCameraAvailability.resolve(isSupported: true, authorization: .notDetermined), .available)
        XCTAssertEqual(IOSCameraAvailability.resolve(isSupported: true, authorization: .authorized), .available)
        XCTAssertNil(IOSCameraAvailability.available.reason)
        XCTAssertTrue(IOSCameraAvailability.available.isAvailable)
        XCTAssertEqual(IOSCameraAvailability.noCamera.reason, "No camera here")
        XCTAssertEqual(IOSCameraAvailability.denied.reason, "Camera access is off")
        XCTAssertEqual(IOSCameraAvailability.restricted.reason, "Camera not allowed")
        XCTAssertTrue(IOSCameraAvailability.denied.opensSettings)
        XCTAssertFalse(IOSCameraAvailability.noCamera.opensSettings)
        // Each reason is a few words, as the start screen's are.
        for availability in [IOSCameraAvailability.noCamera, .denied, .restricted] {
            let words: Int = (availability.reason ?? "").split(separator: " ").count
            XCTAssertLessThanOrEqual(words, 4)
        }
    }

    func test_save_writesPictures_whileTheQueueIsSavedAsJPEG() {
        var settings = ScanSettings()
        settings.format = .pdf
        XCTAssertFalse(IOSShell.savesImages(settings))
        settings.format = .jpeg
        XCTAssertTrue(IOSShell.savesImages(settings))
        settings.format = .word
        XCTAssertFalse(IOSShell.savesImages(settings))

        let first = ScannedPage(image: scannedPicture(width: 40, height: 50), dpi: 100, colorMode: .color)
        let second = ScannedPage(image: scannedPicture(width: 40, height: 50), dpi: 100, colorMode: .color)
        let plan: SavePlan = SavePlan.make([first, second], options: ScanSettings().document)
        XCTAssertEqual(plan.pageCount, 2)
        settings.format = .jpeg
        XCTAssertEqual(IOSShell.saveTitle(settings, plan: plan), "Save JPEG (2 pages)")
        settings.format = .pdf
        XCTAssertEqual(IOSShell.saveTitle(settings, plan: plan), plan.saveTitle(.pdf))
    }

    func test_theImportLaunchOption_carriesOnePhoto() {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        let environment: [String: String] = [IOSLaunchOptions.importFixtureVariable: bytes.base64EncodedString()]
        let options = IOSLaunchOptions(arguments: ["LazyScan", "-demoScanner", "-importFixture"],
                                       environment: environment)
        XCTAssertTrue(options.demoScannerOnly)
        XCTAssertEqual(options.launchImport, IOSImportItem(name: "fixture.png", data: bytes, kind: .image))
        // Without the argument, or without readable bytes, nothing is imported.
        XCTAssertNil(IOSLaunchOptions(arguments: ["LazyScan"], environment: environment).launchImport)
        XCTAssertNil(IOSLaunchOptions(arguments: ["LazyScan", "-importFixture"],
                                      environment: [IOSLaunchOptions.importFixtureVariable: "%%%"]).launchImport)
        XCTAssertNil(IOSLaunchOptions(arguments: ["LazyScan", "-importFixture"]).launchImport)
        XCTAssertNil(IOSLaunchOptions(demoScannerOnly: true).launchImport)
        XCTAssertEqual(IOSLaunchOptions.importFixtureArgument, "-importFixture")
    }

    func test_theImportLaunchOption_carriesSeveralFiles_aPDFAsOne() {
        let photo = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        let pdf = Data("%PDF-1.4\n%fixture\n".utf8)
        let text: String = photo.base64EncodedString() + "," + pdf.base64EncodedString()
        let options = IOSLaunchOptions(arguments: ["LazyScan", "-demoScanner", "-importFixture", "-importTask", "twoSided"],
                                       environment: [IOSLaunchOptions.importFixtureVariable: text])
        XCTAssertEqual(options.launchImports, [IOSImportItem(name: "fixture.png", data: photo, kind: .image),
                                               IOSImportItem(name: "fixture.pdf", data: pdf, kind: .pdf)])
        XCTAssertEqual(options.launchImport, options.launchImports.first)
        XCTAssertEqual(options.launchTask, .twoSided)
        // A part that does not read is left out; the others come in.
        let mixed = IOSLaunchOptions(arguments: ["LazyScan", "-importFixture"],
                                     environment: [IOSLaunchOptions.importFixtureVariable: "%%%," + pdf.base64EncodedString()])
        XCTAssertEqual(mixed.launchImports.map(\.kind), [.pdf])
        XCTAssertTrue(IOSLaunchOptions(demoScannerOnly: false).launchImports.isEmpty)
    }
}
#endif
