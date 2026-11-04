#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import LazyScanKit
@testable import LazyScanMac

// Renders the Mac's main views to PNGs for a visual check, in CI and on a developer's Mac. Does nothing
// unless LAZYSCAN_SHOTS_DIR names the folder for the images. LAZYSCAN_SHOTS_LANG (a language tag) sets
// AppleLanguages and the views' locale, LAZYSCAN_SHOTS_RTL=1 lays them out right to left.

final class ScreenshotTests: XCTestCase {
    private var folder: URL!
    private var outDir: URL!

    private static let sections = ["task", "scanner", "output", "adjustments", "pages", "split", "archive", "more"]

    override func setUpWithError() throws {
        guard let dir = ProcessInfo.processInfo.environment["LAZYSCAN_SHOTS_DIR"], !dir.isEmpty else {
            throw XCTSkip("LAZYSCAN_SHOTS_DIR is not set")
        }
        outDir = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let lang = ProcessInfo.processInfo.environment["LAZYSCAN_SHOTS_LANG"], !lang.isEmpty {
            UserDefaults.standard.register(defaults: ["AppleLanguages": [lang]])
        }
    }

    override func tearDown() async throws {
        guard let folder else { return }
        // The settings are written 0.4 s after they change: let that write land before the folder goes.
        try await Task.sleep(nanoseconds: 600_000_000)
        try? FileManager.default.removeItem(at: folder)
    }

    /// A light page with dark bars like lines of text, the same on every run.
    private func page(width: Int, height: Int) -> ScannedPage {
        let space: CGColorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
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

    @MainActor
    private func makeState(pages: Int) async throws -> AppState {
        let first = AppState(backends: [], presetStore: PresetStore(directory: folder),
                             files: AppStateFiles.all(in: folder))
        var settings = ScanSettings()
        settings.intent = .document
        settings.documentMultiPage = true
        settings.taskId = nil
        settings.destinationPath = folder.path
        first.settings = settings
        // With settings on disk the next state is not a first run, so the window opens on the scanner view.
        try await Task.sleep(nanoseconds: 800_000_000)
        let state = AppState(backends: [], presetStore: PresetStore(directory: folder),
                             files: AppStateFiles.all(in: folder))
        if pages > 0 {
            XCTAssertTrue(state.ingest((0..<pages).map { _ in page(width: 510, height: 660) }, source: .scanner))
            let deadline = Date().addingTimeInterval(20)
            while (state.scannedPages.count < pages || state.scanHistory.isEmpty) && Date() < deadline {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            XCTAssertEqual(state.scannedPages.count, pages)
        }
        return state
    }

    /// Hosts `view` in a window that is never shown, lets it settle, and writes it as `name`.png.
    @MainActor
    private func shoot<V: View>(_ name: String, size: CGSize, _ view: V) async throws {
        let env = ProcessInfo.processInfo.environment
        let rtl = env["LAZYSCAN_SHOTS_RTL"] == "1"
        let locale = Locale(identifier: env["LAZYSCAN_SHOTS_LANG"] ?? "en")
        let root = view
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
            .environment(\.locale, locale)
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        hosting.frame = CGRect(origin: .zero, size: size)
        // Photos load off the main thread: give them time, laying out again as they land.
        for _ in 0..<10 {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        hosting.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: outDir.appendingPathComponent("\(name).png"))
        window.contentView = nil
    }

    @MainActor
    func test_scanScreen() async throws {
        let state = try await makeState(pages: 3)
        try await shoot("scan-screen", size: CGSize(width: 1100, height: 720),
                        ContentView().environmentObject(state))
    }

    @MainActor
    func test_inspector() async throws {
        let state = try await makeState(pages: 0)
        try await shoot("inspector", size: CGSize(width: 340, height: 720),
                        InspectorView().environmentObject(state))
    }

    @MainActor
    func test_settings_allSectionsOpen() async throws {
        for section in Self.sections {
            UserDefaults.standard.set(true, forKey: "inspector.section.\(section)")
        }
        defer {
            for section in Self.sections {
                UserDefaults.standard.removeObject(forKey: "inspector.section.\(section)")
            }
        }
        let state = try await makeState(pages: 0)
        try await shoot("settings", size: CGSize(width: 340, height: 1600),
                        InspectorView().environmentObject(state))
    }

    @MainActor
    func test_pagesStrip() async throws {
        let state = try await makeState(pages: 4)
        try await shoot("pages-strip", size: CGSize(width: 900, height: 200),
                        PagesStripView().environmentObject(state))
    }

    @MainActor
    func test_cornerEditor() async throws {
        let state = try await makeState(pages: 0)
        let width = 600
        let height = 450
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let inside = x > 110 && x < 490 && y > 50 && y < 400
                let value: UInt8 = inside ? 238 : 96
                let i = (y * width + x) * 4
                pixels[i] = value
                pixels[i + 1] = value
                pixels[i + 2] = inside ? value : 84
                pixels[i + 3] = 255
            }
        }
        let corners = Quad(topLeft: CGPoint(x: 112, y: 52), topRight: CGPoint(x: 488, y: 60),
                           bottomRight: CGPoint(x: 480, y: 398), bottomLeft: CGPoint(x: 120, y: 392))
        let plan = PhotoImportPlan(action: .review, corners: corners, reason: .unsure,
                                   detection: PhotoDocumentDetection.nothing)
        let request = PhotoCornersRequest(photo: RgbaImage(width: width, height: height, pixels: pixels),
                                          plan: plan, fileName: "IMG_0001.HEIC", number: 1, count: 2)
        try await shoot("corner-editor", size: CGSize(width: 760, height: 620),
                        PhotoCornersEditorView(request: request).environmentObject(state))
    }

    @MainActor
    func test_history() async throws {
        let state = try await makeState(pages: 3)
        try await shoot("history", size: CGSize(width: 900, height: 600),
                        ScanHistoryView().environmentObject(state))
    }
}
#endif
