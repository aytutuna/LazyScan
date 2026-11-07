#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import LazyScanKit
@testable import LazyScanMac

// The Mac App Store screenshots: the window at 1280 x 800 points, drawn at twice that, which is the 2560 x 1600 pixels
// App Store Connect takes, and written without an alpha channel. Does nothing unless LAZYSCAN_STORE_SHOTS_DIR names the
// folder for the images.

final class MacStoreShotsTests: XCTestCase {
    private var folder: URL!
    private var outDir: URL!

    override func setUpWithError() throws {
        guard let dir = ProcessInfo.processInfo.environment["LAZYSCAN_STORE_SHOTS_DIR"], !dir.isEmpty else {
            throw XCTSkip("LAZYSCAN_STORE_SHOTS_DIR is not set")
        }
        outDir = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("LazyScanStoreShots", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        guard let folder else { return }
        // The settings are written 0.4 s after they change: let that write land before the folder goes.
        try await Task.sleep(nanoseconds: 600_000_000)
        try? FileManager.default.removeItem(at: folder)
    }

    /// A light page with dark bars like lines of text.
    private func page(width: Int, height: Int) -> ScannedPage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.94, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1))
        for line in 0..<14 {
            let y = height - height / 8 - line * height / 20
            let w = line % 5 == 4 ? width / 3 : width * 2 / 3
            context.fill(CGRect(x: width / 6, y: y, width: w, height: max(3, height / 90)))
        }
        return ScannedPage(image: context.makeImage()!, dpi: 75, colorMode: .color)
    }

    /// A state with the demo scanner. With `pages` it is past the first run, on the scanner view with that many
    /// pages queued; with none it is a first run, which opens on the start screen.
    @MainActor
    private func makeState(pages: Int) async throws -> AppState {
        let backends: [any ScannerBackend] = [MockScannerBackend()]
        if pages == 0 {
            let fresh = AppState(backends: backends, presetStore: PresetStore(directory: folder),
                                 files: AppStateFiles.all(in: folder))
            fresh.start()
            return fresh
        }
        let first = AppState(backends: backends, presetStore: PresetStore(directory: folder),
                             files: AppStateFiles.all(in: folder))
        var settings = ScanSettings()
        settings.intent = .document
        settings.documentMultiPage = true
        settings.taskId = nil
        settings.namingTemplate = "Scan"
        settings.destinationPath = folder.path
        first.settings = settings
        // With settings on disk the next state is not a first run.
        try await Task.sleep(nanoseconds: 800_000_000)
        let state = AppState(backends: backends, presetStore: PresetStore(directory: folder),
                             files: AppStateFiles.all(in: folder))
        state.start()
        XCTAssertTrue(state.ingest((0..<pages).map { _ in page(width: 510, height: 660) }, source: .scanner))
        let deadline = Date().addingTimeInterval(20)
        while (state.scannedPages.count < pages || state.scanHistory.isEmpty) && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertEqual(state.scannedPages.count, pages)
        return state
    }

    /// Draws the window in `appearance` and writes it as `name`.png: 2560 x 1600 pixels, opaque.
    @MainActor
    private func shoot(_ name: String, appearance: NSAppearance.Name, state: AppState) async throws {
        let size = CGSize(width: 1280, height: 800)
        let root = ContentView()
            .environmentObject(state)
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        window.setFrameOrigin(CGPoint(x: -10000, y: -10000))
        window.orderBack(nil)
        hosting.frame = CGRect(origin: .zero, size: size)
        // Photos load off the main thread: give them time, laying out again as they land.
        for _ in 0..<10 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        hosting.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2560, pixelsHigh: 1600,
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        window.contentView = nil
        try write(try XCTUnwrap(rep.cgImage), as: name)
    }

    /// The picture drawn onto an opaque bitmap, so the PNG has no alpha channel.
    private func write(_ image: CGImage, as name: String) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let flat = try XCTUnwrap(context.makeImage())
        let url = outDir.appendingPathComponent("\(name).png")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, flat, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertEqual(flat.width, 2560)
        XCTAssertEqual(flat.height, 1600)
        XCTAssertEqual(flat.alphaInfo, .noneSkipLast)
    }

    @MainActor
    func test_start() async throws {
        let state = try await makeState(pages: 0)
        try await shoot("mac-start-light", appearance: .aqua, state: state)
    }

    @MainActor
    func test_scanner_light() async throws {
        let state = try await makeState(pages: 3)
        try await shoot("mac-scanner-light", appearance: .aqua, state: state)
    }

    @MainActor
    func test_scanner_dark() async throws {
        let state = try await makeState(pages: 3)
        try await shoot("mac-scanner-dark", appearance: .darkAqua, state: state)
    }
}
#endif
