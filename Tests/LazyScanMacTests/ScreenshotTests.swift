#if os(macOS)
import AppKit
import SwiftUI
import XCTest
@testable import LazyScanKit
@testable import LazyScanMac

// Renders the Mac's main views to PNGs for a visual check, in CI and on a developer's Mac. Does nothing
// unless LAZYSCAN_SHOTS_DIR names the folder for the images. LAZYSCAN_SHOTS_RTL=1 lays them out right to left.
// The text is English unless LAZYSCAN_SHOTS_PSEUDO names a qps-ploc.lproj folder (gen_l10n.py --pseudo): under
// swift test Bundle.main is the xctest tool, which has no string tables, so that run answers only the Kit
// lookups (L10n.t) from the folder's Kit.strings. SwiftUI literals stay English there, marked or not, and
// prove nothing either way. The inspector and settings are shot wider in that run so long text is not clipped.

final class ScreenshotTests: XCTestCase {
    private var folder: URL!
    private var outDir: URL!

    private var pseudo: L10n.Override?

    private static let sections = ["task", "scanner", "output", "adjustments", "pages", "split", "archive", "more"]

    override func setUpWithError() throws {
        guard let dir = ProcessInfo.processInfo.environment["LAZYSCAN_SHOTS_DIR"], !dir.isEmpty else {
            throw XCTSkip("LAZYSCAN_SHOTS_DIR is not set")
        }
        outDir = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("LazyScanShots", isDirectory: true)
        // A fixed name, as the inspector shows the save folder.
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let path = ProcessInfo.processInfo.environment["LAZYSCAN_SHOTS_PSEUDO"], !path.isEmpty {
            let table = try XCTUnwrap(NSDictionary(contentsOfFile: path + "/Kit.strings") as? [String: String])
            pseudo = L10n.Override(table: table, language: "qps-ploc")
        }
    }

    /// Runs `body` with the Kit lookups answered from the pseudo table, or as they are without one.
    @MainActor
    private func inLanguage<T>(_ body: () async throws -> T) async rethrows -> T {
        guard let pseudo else { return try await body() }
        return try await L10n.$override.withValue(pseudo, operation: body)
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
        // The pseudo run lists the demo scanner, so the sidebar has a scanner row to read.
        let backends: [any ScannerBackend] = pseudo == nil ? [] : [MockScannerBackend()]
        let first = AppState(backends: backends, presetStore: PresetStore(directory: folder),
                             files: AppStateFiles.all(in: folder))
        var settings = ScanSettings()
        settings.intent = .document
        settings.documentMultiPage = true
        settings.taskId = nil
        // No date or counter in the file name preview.
        settings.namingTemplate = "Scan"
        settings.destinationPath = folder.path
        first.settings = settings
        // With settings on disk the next state is not a first run, so the window opens on the scanner view.
        try await Task.sleep(nanoseconds: 800_000_000)
        let state = AppState(backends: backends, presetStore: PresetStore(directory: folder),
                             files: AppStateFiles.all(in: folder))
        if pseudo != nil { await inLanguage { state.start() } }
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

    /// Hosts `view` in a titled window parked far off screen (a borderless one never loaded the sidebar rows) and lets it settle.
    @MainActor
    private func render<V: View>(size: CGSize, rtl: Bool, _ view: V) async throws -> NSBitmapImageRep {
        let root = view
            .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
            .frame(width: size.width, height: size.height)
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
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
        let rep = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.orderOut(nil)
        window.contentView = nil
        return rep
    }

    /// Renders `view` and writes it as `name`.png.
    @MainActor
    private func shoot<V: View>(_ name: String, size: CGSize, _ view: V) async throws {
        let rtl = ProcessInfo.processInfo.environment["LAZYSCAN_SHOTS_RTL"] == "1"
        let rep = try await inLanguage { try await render(size: size, rtl: rtl, view) }
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try png.write(to: outDir.appendingPathComponent("\(name).png"))
    }

    @MainActor
    func test_scanScreen() async throws {
        let state = try await makeState(pages: 3)
        try await shoot("scan-screen", size: CGSize(width: 1100, height: 720),
                        ContentView().environmentObject(state))
    }

    @MainActor
    func test_sidebar() async throws {
        let state = try await makeState(pages: 0)
        try await shoot("sidebar", size: CGSize(width: 260, height: 400),
                        SidebarView().environmentObject(state))
    }

    @MainActor
    func test_inspector() async throws {
        let state = try await makeState(pages: 0)
        try await shoot("inspector", size: CGSize(width: pseudo == nil ? 340 : 800, height: 720),
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
        try await shoot("settings", size: CGSize(width: pseudo == nil ? 340 : 800, height: 1600),
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
        let state = try await makeState(pages: 0)
        let thumbnail = page(width: 255, height: 330).image
        let day = Date(timeIntervalSince1970: 1_767_225_600)
        state.scanHistory = [ScanIntent.document, .photo, .document].enumerated().map { i, intent in
            ScanHistoryEntry(date: day.addingTimeInterval(Double(-i) * 3_700), intent: intent, dpi: 300,
                             thumbnail: thumbnail, pixelSize: CGSize(width: 2550, height: 3300),
                             id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(i + 1)")!)
        }
        try await shoot("history", size: CGSize(width: 900, height: 600),
                        ScanHistoryView().environmentObject(state))
    }

    /// The corner editor pins its stage left to right, which the drag geometry relies on: laid out right
    /// to left, the stage (photo, outline and handles) must render exactly as it does left to right.
    /// Only the render is compared; the gesture's own location mapping is not driven here.
    @MainActor
    func test_cornerEditor_stageStaysPutRightToLeft() async throws {
        let state = try await makeState(pages: 0)
        let width = 600
        let height = 450
        var pixels = [UInt8](repeating: 20, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if x > 40 && x < 330 && y > 50 && y < 400 {
                    pixels[i] = 255
                    pixels[i + 1] = 255
                    pixels[i + 2] = 255
                }
                pixels[i + 3] = 255
            }
        }
        // Not symmetric, so a mirrored handle or outline lands somewhere else.
        let corners = Quad(topLeft: CGPoint(x: 42, y: 52), topRight: CGPoint(x: 328, y: 70),
                           bottomRight: CGPoint(x: 310, y: 398), bottomLeft: CGPoint(x: 60, y: 380))
        let plan = PhotoImportPlan(action: .review, corners: corners, reason: .unsure,
                                   detection: PhotoDocumentDetection.nothing)
        let request = PhotoCornersRequest(photo: RgbaImage(width: width, height: height, pixels: pixels),
                                          plan: plan, fileName: "IMG_0001.HEIC", number: 1, count: 2)
        var reps: [NSBitmapImageRep] = []
        for rtl in [false, true] {
            reps.append(try await render(size: CGSize(width: 760, height: 620), rtl: rtl,
                                         PhotoCornersEditorView(request: request).environmentObject(state)))
        }
        let (ltr, rtl) = (reps[0], reps[1])
        XCTAssertEqual(ltr.pixelsWide, rtl.pixelsWide)
        XCTAssertEqual(ltr.pixelsHigh, rtl.pixelsHigh)
        let data = try XCTUnwrap(ltr.bitmapData)
        let other = try XCTUnwrap(rtl.bitmapData)
        let rowBytes = ltr.bytesPerRow
        // The stage lies between the header and footer, which differ between the two. The photo's dark
        // border fills most of the width on its rows, which text does not.
        let dark = (0..<ltr.pixelsHigh).filter { y in
            (0..<ltr.pixelsWide).filter { x in
                ltr.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB).map { $0.redComponent < 0.15 } ?? false
            }.count > ltr.pixelsWide / 2
        }
        let first = try XCTUnwrap(dark.first)
        let last = try XCTUnwrap(dark.last)
        XCTAssertGreaterThan(last - first, ltr.pixelsHigh / 2)
        for y in first...last {
            XCTAssertEqual(memcmp(data + y * rowBytes, other + y * rowBytes, ltr.pixelsWide * ltr.samplesPerPixel), 0,
                           "row \(y) of the stage differs")
        }
    }
}
#endif
