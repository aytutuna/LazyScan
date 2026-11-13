import CoreGraphics
import Foundation
import XCTest
@testable import LazyScanKit

// A camera's queued page cut out of its photo again with another filter or along new corners
// (AppState+Recut.swift). Swift only: the Windows app takes no camera shots.

private struct RecutScorer: OrientationScorer {
    var isAvailable: Bool { false }

    func score(_ image: RgbaImage) throws -> OrientationScore {
        OrientationScore.none
    }
}

private struct RecutBarcodes: BarcodeReader {
    var isAvailable: Bool { false }

    func read(_ image: GrayImage) throws -> [BarcodeReading] {
        []
    }
}

private func pixels(_ image: CGImage) -> [UInt8] {
    RgbaImage(cgImage: image)!.pixels
}

/// The shadowed page on a table, as the camera takes it: the photo and the shot with its corners.
private func shot() -> (photo: CGImage, page: ScannedPage) {
    let table: TablePhoto = CameraSheets.squareOnATable(EnhancerPages.shadowed())
    let photo: CGImage = table.photo.makeCGImage()!
    var page = ScannedPage(image: photo, dpi: CaptureScale.nominalDPI, colorMode: .color)
        .withCapture(CaptureFacts(quad: table.quad, sourceWidth: table.photo.width, sourceHeight: table.photo.height))
    page.source = .photo
    return (photo, page)
}

@MainActor
private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool,
                       file: StaticString = #filePath, line: UInt = #line) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline {
            XCTFail("Timed out after \(timeout) s", file: file, line: line)
            return
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
}

final class PageRecutTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PageRecutTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try await Task.sleep(nanoseconds: 600_000_000)
        try? FileManager.default.removeItem(at: folder)
    }

    func testOriginalIsTheCutWithNoCleanUp_andTheFiltersGoBackAndForth() throws {
        let (photo, page) = shot()
        let cut: ScannedPage = PerspectiveStep().apply(page)
        let enhanced: ScannedPage = try XCTUnwrap(PageProcessor.forCapture(ScanSettings()).process([page]).pages.first)
        XCTAssertEqual(PageRecut.filter(of: enhanced), .enhanced)

        let original: ScannedPage = try XCTUnwrap(PageRecut.recut(enhanced, photo: photo, filter: .original))
        XCTAssertEqual(pixels(original.image), pixels(cut.image))
        XCTAssertEqual(original.capture?.filter, .original)
        XCTAssertNil(original.capture?.enhancement)
        XCTAssertEqual(original.colorMode, .color)
        XCTAssertEqual(original.dpi, cut.dpi)
        XCTAssertEqual(original.geometry, cut.geometry)
        XCTAssertEqual(original.id, page.id)
        XCTAssertTrue(original.alternate?.image === enhanced.alternate?.image)
        XCTAssertEqual(original.blank, enhanced.blank)

        let gray: ScannedPage = try XCTUnwrap(PageRecut.recut(original, photo: photo, filter: .grayscale))
        XCTAssertEqual(pixels(gray.image), DocumentEnhancer.enhance(RgbaImage(cgImage: cut.image)!, mode: .gray).image.pixels)
        XCTAssertEqual(gray.colorMode, .grayscale)
        XCTAssertEqual(PageRecut.filter(of: gray), .grayscale)
        XCTAssertEqual(try XCTUnwrap(PageRecut.recut(gray, photo: photo, filter: .blackAndWhite)).colorMode, .blackWhite)

        let back: ScannedPage = try XCTUnwrap(PageRecut.recut(gray, photo: photo, filter: .original))
        XCTAssertEqual(pixels(back.image), pixels(cut.image))
        XCTAssertEqual(back.colorMode, .color)
        let again: ScannedPage = try XCTUnwrap(PageRecut.recut(back, photo: photo, filter: .enhanced))
        XCTAssertEqual(pixels(again.image), pixels(enhanced.image))
        XCTAssertEqual(again.capture, enhanced.capture)
    }

    func testARecutOfAPageNeverStraightenedLeavesItSo() throws {
        let (photo, page) = shot()
        let enhanced: ScannedPage = try XCTUnwrap(PageProcessor.forCapture(ScanSettings()).process([page]).pages.first)
        XCTAssertNil(enhanced.capture?.straightened)
        let recut: ScannedPage = try XCTUnwrap(PageRecut.recut(enhanced, photo: photo, filter: .grayscale))
        XCTAssertNil(recut.capture?.straightened)
    }

    func testAPageTurnedUpright_isCutInTheTurnItsFileHolds() throws {
        let (photo, page) = shot()
        let enhanced: ScannedPage = try XCTUnwrap(PageProcessor.forCapture(ScanSettings()).process([page]).pages.first)
        let turned: ScannedPage = enhanced.turnedUpright(1)
        let stored: CGImage = ImagePipeline.rotate(photo, quarterTurns: 1)
        let recut: ScannedPage = try XCTUnwrap(PageRecut.recut(turned, photo: stored, filter: .enhanced))
        XCTAssertEqual(pixels(recut.image), pixels(turned.image))
        XCTAssertEqual(recut.upright, turned.upright)
        // A smaller copy of the photo gives the page at its size.
        let small: CGImage = AppState.makePreview(stored, maxSide: stored.width / 2)!
        let preview: ScannedPage = try XCTUnwrap(PageRecut.recut(turned, photo: small, filter: .original))
        XCTAssertLessThan(preview.image.width, recut.image.width)
        XCTAssertGreaterThan(preview.image.width, preview.image.height)
    }

    func testCrop_cutsAlongNewCorners_andKeepsTheFilter() throws {
        let (photo, page) = shot()
        var settings = ScanSettings()
        settings.taskOptions.cameraFilter = .original
        let original: ScannedPage = try XCTUnwrap(PageProcessor.forCapture(settings).process([page]).pages.first)
        let facts: CaptureFacts = try XCTUnwrap(page.capture)
        let inner = Quad(topLeft: CGPoint(x: 80, y: 80), topRight: CGPoint(x: 260, y: 80),
                         bottomRight: CGPoint(x: 260, y: 330), bottomLeft: CGPoint(x: 80, y: 330))
        let cropped: ScannedPage = try XCTUnwrap(PageRecut.recut(original, photo: photo, filter: .original, corners: inner))
        XCTAssertEqual(cropped.capture?.quad, inner)
        XCTAssertEqual(cropped.geometry?.quad, inner)
        XCTAssertEqual(cropped.capture?.filter, .original)
        XCTAssertLessThan(cropped.image.width, original.image.width)
        // Corners placed on the photo turned as the page is shown are put back on the photo as taken.
        for turns in 0..<4 {
            let shown: Quad = facts.oriented(PhotoOrientation(quarterTurns: turns, mirrored: false)).quad
            XCTAssertLessThan(PageRecut.cornersAsTaken(shown, facts: facts, quarterTurns: turns).maxCornerDistance(facts.quad), 1e-9)
        }
    }

    func testAPhotoPrint_hasNoFilter_butIsCutAgainAlongNewCorners() throws {
        let (photo, page) = shot()
        let facts: CaptureFacts = try XCTUnwrap(page.capture)
        let print: ScannedPage = page.withCapture(CaptureFacts(quad: facts.quad, sourceWidth: page.image.width,
                                                               sourceHeight: page.image.height, kind: .photo))
        let cut: ScannedPage = EnhanceStep(mode: nil).apply(PerspectiveStep().apply(print))
        XCTAssertNil(PageRecut.filter(of: cut))
        let inner = Quad(topLeft: CGPoint(x: 80, y: 80), topRight: CGPoint(x: 260, y: 80),
                         bottomRight: CGPoint(x: 260, y: 330), bottomLeft: CGPoint(x: 80, y: 330))
        let cropped: ScannedPage = try XCTUnwrap(PageRecut.recut(cut, photo: photo, filter: nil, corners: inner))
        XCTAssertEqual(cropped.capture?.quad, inner)
        XCTAssertEqual(cropped.geometry?.quad, inner)
        XCTAssertNil(cropped.capture?.filter)
        XCTAssertNotNil(cropped.capture?.enhancement)
    }

    func testAListedPhoto_keepsItsAdjustments_forACropAfterTheSettingsChange() throws {
        let (_, page) = shot()
        let facts: CaptureFacts = try XCTUnwrap(page.capture)
        let print: ScannedPage = page.withCapture(CaptureFacts(quad: facts.quad, sourceWidth: page.image.width,
                                                               sourceHeight: page.image.height, kind: .photo))
        var settings: ScanSettings = TaskCatalog.apply(.photos, to: ScanSettings())
        settings.colorMode = .grayscale
        let cut: ScannedPage = try XCTUnwrap(PageProcessor.forCapture(settings).process([print]).pages.first)
        let listed: [ScannedPage] = try AppState.listObjects([cut], flow: .photoSplit, settings: settings, flag: CancelFlag())
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.capture?.adjustedColorMode, .grayscale)
        settings.colorMode = .color
        let step: AdjustmentStep = try XCTUnwrap(PageRecut.adjustment(for: try XCTUnwrap(listed.first)))
        XCTAssertEqual(step.colorMode, .grayscale)
        // Nothing to take where the photo was given none.
        let plain: [ScannedPage] = try AppState.listObjects([cut], flow: .photoSplit, settings: ScanSettings(), flag: CancelFlag())
        XCTAssertNil(plain.first.flatMap { (item: ScannedPage) -> AdjustmentStep? in PageRecut.adjustment(for: item) })
    }

    func testAListedReceipt_isMadeEasyToRead() throws {
        let (_, page) = shot()
        let facts: CaptureFacts = try XCTUnwrap(page.capture)
        let slip: ScannedPage = page.withCapture(CaptureFacts(quad: facts.quad, sourceWidth: page.image.width,
                                                              sourceHeight: page.image.height, kind: .receipt))
        let settings: ScanSettings = TaskCatalog.apply(.receipt, to: ScanSettings())
        let cut: ScannedPage = try XCTUnwrap(PageProcessor.forCapture(settings).process([slip]).pages.first)
        let listed: [ScannedPage] = try AppState.listObjects([cut], flow: .receiptSplit, settings: settings, flag: CancelFlag())
        XCTAssertEqual(listed.count, 1)
        XCTAssertNotEqual(pixels(try XCTUnwrap(listed.first).image), pixels(cut.image))
        XCTAssertEqual(listed.first?.geometry?.basis, .perspective)
    }

    func testOnlyACameraPageWithAFilterCanBeCutAgain() throws {
        let (_, page) = shot()
        let scanned = ScannedPage(image: page.image, dpi: 300, colorMode: .color)
        XCTAssertNil(PageRecut.filter(of: scanned))
        XCTAssertFalse(PageRecut.canRecut(scanned))
        let enhanced: ScannedPage = try XCTUnwrap(PageProcessor.forCapture(ScanSettings()).process([page]).pages.first)
        // In memory only, it has no files to cut from and to replace.
        XCTAssertFalse(PageRecut.canRecut(enhanced))
        // A photo print is a photo: no filter.
        let print: ScannedPage = page.withCapture(CaptureFacts(quad: page.capture!.quad, sourceWidth: page.image.width,
                                                                sourceHeight: page.image.height, kind: .photo))
        XCTAssertNil(PageRecut.filter(of: EnhanceStep(mode: .auto).apply(PerspectiveStep().apply(print))))
        // Queued before filters: the clean-up it had.
        var older: CaptureFacts = try XCTUnwrap(enhanced.capture)
        older.filter = nil
        older.enhancement = .gray
        XCTAssertEqual(PageRecut.filter(of: enhanced.withCapture(older)), .grayscale)
        XCTAssertEqual(PageRecut.filterNote(.blackAndWhite, number: 3), "Page 3: B&W.")
        XCTAssertEqual(PageRecut.cropNote(number: 2), "Page 2 is cut out again.")
    }

    @MainActor
    func testAFilterForSeveralPages_reachesEachOfThem_andCountsDown() async throws {
        let state = AppState(presetStore: PresetStore(directory: folder), orientationScorer: RecutScorer(),
                             barcodeReader: RecutBarcodes(), files: AppStateFiles.all(in: folder))
        XCTAssertTrue(state.startTask(.document))
        state.settings.taskOptions.cameraFilter = .original
        state.settings.destinationPath = folder.path
        XCTAssertTrue(state.ingest([shot().page], source: .photo))
        try await waitUntil(timeout: 60) { !state.isBusy && state.scannedPages.count == 1 }
        XCTAssertTrue(state.ingest([shot().page], source: .photo))
        try await waitUntil(timeout: 60) { !state.isBusy && state.scannedPages.count == 2 }
        defer { state.deleteSpoolFiles(of: state.scannedPages) }
        let ids: [UUID] = state.scannedPages.map { (page: ScannedPage) -> UUID in page.id }

        state.setPagesFilter(ids: ids, .grayscale)
        XCTAssertEqual(state.filterPagesLeft, 2)
        try await waitUntil(timeout: 60) { state.pageEditChain == nil }
        XCTAssertEqual(state.filterPagesLeft, 0)
        XCTAssertEqual(state.scannedPages.map { (page: ScannedPage) -> CaptureFilter? in page.capture?.filter }, [.grayscale, .grayscale])
        XCTAssertEqual(state.scannedPages.map { (page: ScannedPage) -> UUID in page.id }, ids)
    }

    @MainActor
    func testAQueuedPage_takesAnotherFilter_keepsItsPhoto_andTheRecordKeepsIt() async throws {
        var files = AppStateFiles.all(in: folder)
        files.keepsQueue = true
        let state = AppState(presetStore: PresetStore(directory: folder), orientationScorer: RecutScorer(),
                             barcodeReader: RecutBarcodes(), files: files)
        XCTAssertTrue(state.startTask(.document))
        state.settings.taskOptions.cameraFilter = .original
        state.settings.destinationPath = folder.path
        let (photo, taken) = shot()
        XCTAssertTrue(state.ingest([taken], source: .photo))
        try await waitUntil(timeout: 60) { !state.isBusy && state.scannedPages.count == 1 }
        defer { state.deleteSpoolFiles(of: state.scannedPages) }
        let page: ScannedPage = state.scannedPages[0]
        XCTAssertEqual(PageRecut.filter(of: page), .original)
        XCTAssertTrue(PageRecut.canRecut(page))
        let firstFile: URL = try XCTUnwrap(page.fileURL)
        let photoFile: URL = try XCTUnwrap(page.alternate?.fileURL)
        let firstPixels: [UInt8] = pixels(try XCTUnwrap(AppState.imageInFile(firstFile)))

        state.setPageFilter(id: page.id, .grayscale)
        try await waitUntil(timeout: 60) { state.scannedPages.first?.capture?.filter == .grayscale }
        let gray: ScannedPage = state.scannedPages[0]
        XCTAssertEqual(gray.id, page.id)
        XCTAssertEqual(gray.colorMode, .grayscale)
        XCTAssertNotEqual(gray.fileURL, firstFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(gray.fileURL).path))
        XCTAssertEqual(gray.alternate?.fileURL, photoFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: photoFile.path))
        XCTAssertEqual(state.statusMessage, "Page 1: Grayscale.")
        XCTAssertTrue(state.recuttingPages.isEmpty)

        // Gray, then Enhanced and back to Gray before the first lands: the last tap wins.
        state.setPageFilter(id: page.id, .enhanced)
        state.setPageFilter(id: page.id, .grayscale)
        try await waitUntil(timeout: 60) { state.pageEditChain == nil }
        XCTAssertEqual(state.scannedPages.first?.capture?.filter, .grayscale)
        XCTAssertEqual(state.scannedPages.first?.colorMode, .grayscale)

        let data = try Data(contentsOf: state.spoolDirectory.appendingPathComponent(QueueRecord.fileName))
        let record: QueueRecord = try JSONDecoder().decode(QueueRecord.self, from: data)
        XCTAssertEqual(record.pages.first?.capture?.filter, .grayscale)
        XCTAssertEqual(record.pages.first?.file, state.scannedPages.first?.fileURL?.lastPathComponent)

        state.setPageFilter(id: page.id, .original)
        try await waitUntil(timeout: 60) { state.scannedPages.first?.capture?.filter == .original }
        let back: ScannedPage = state.scannedPages[0]
        XCTAssertEqual(back.colorMode, .color)
        XCTAssertEqual(pixels(try XCTUnwrap(AppState.imageInFile(try XCTUnwrap(back.fileURL)))), firstPixels)

        let previews: [CaptureFilter: CGImage] = await state.filterPreviews(id: page.id, maxSide: 80)
        XCTAssertEqual(Set(previews.keys), Set(CaptureFilter.allCases))

        let cropStart: PhotoCropStart? = await state.pageCropStart(id: page.id)
        let start: PhotoCropStart = try XCTUnwrap(cropStart)
        XCTAssertEqual(start.source.width, photo.width)
        XCTAssertLessThan(start.corners.maxCornerDistance(try XCTUnwrap(taken.capture).quad), 1e-9)
        let inner = Quad(topLeft: CGPoint(x: 80, y: 80), topRight: CGPoint(x: 260, y: 80),
                         bottomRight: CGPoint(x: 260, y: 330), bottomLeft: CGPoint(x: 80, y: 330))
        // Corners placed while the page had another turn are not used.
        state.recropPage(id: page.id, corners: inner, rotation: 1)
        XCTAssertNil(state.pageEditChain)
        state.recropPage(id: page.id, corners: inner, rotation: 0)
        try await waitUntil(timeout: 60) { state.scannedPages.first?.geometry?.quad == inner }
        XCTAssertEqual(state.scannedPages[0].capture?.filter, .original)
        XCTAssertEqual(state.statusMessage, "Page 1 is cut out again.")
    }

    @MainActor
    func testWhileTheQueueIsRead_thePageIsNotCutAgain() async throws {
        let state = AppState(presetStore: PresetStore(directory: folder), orientationScorer: RecutScorer(),
                             barcodeReader: RecutBarcodes(), files: AppStateFiles.all(in: folder))
        XCTAssertTrue(state.startTask(.document))
        state.settings.taskOptions.cameraFilter = .original
        state.settings.destinationPath = folder.path
        let (_, taken) = shot()
        XCTAssertTrue(state.ingest([taken], source: .photo))
        try await waitUntil(timeout: 60) { !state.isBusy && state.scannedPages.count == 1 }
        defer { state.deleteSpoolFiles(of: state.scannedPages) }
        let page: ScannedPage = state.scannedPages[0]
        XCTAssertTrue(PageRecut.canRecut(page))
        let file: URL = try XCTUnwrap(page.fileURL)
        let inner = Quad(topLeft: CGPoint(x: 80, y: 80), topRight: CGPoint(x: 260, y: 80),
                         bottomRight: CGPoint(x: 260, y: 330), bottomLeft: CGPoint(x: 80, y: 330))

        // A share or a send reading the spooled pages: the page keeps its file.
        state.queueReaders = 1
        state.setPageFilter(id: page.id, .grayscale)
        state.recropPage(id: page.id, corners: inner, rotation: 0)
        XCTAssertNil(state.pageEditChain)
        XCTAssertEqual(state.scannedPages.first?.fileURL, file)
        state.queueReaders = 0

        state.setPageFilter(id: page.id, .grayscale)
        try await waitUntil(timeout: 60) { state.scannedPages.first?.capture?.filter == .grayscale }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    /// 40 × 20 pixels, the top half red and the bottom half blue.
    private func halves() -> CGImage {
        var data = [UInt8]()
        for y in 0..<20 {
            for _ in 0..<40 {
                data += y < 10 ? [200, 40, 40, 255] : [40, 40, 200, 255]
            }
        }
        return RgbaImage(width: 40, height: 20, pixels: data).makeCGImage()!
    }

    func testFileRect_putsTheRectangleBackOnThePictureBeforeTheTurn() {
        let left = CGRect(x: 0, y: 0, width: 0.5, height: 1)
        XCTAssertEqual(PageRecut.fileRect(left, quarterTurns: 0), left)
        XCTAssertEqual(PageRecut.fileRect(left, quarterTurns: 1), CGRect(x: 0, y: 0.5, width: 1, height: 0.5))
        XCTAssertEqual(PageRecut.fileRect(left, quarterTurns: 2), CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
        XCTAssertEqual(PageRecut.fileRect(left, quarterTurns: 3), CGRect(x: 0, y: 0, width: 1, height: 0.5))
        XCTAssertEqual(PageRecut.fileRect(PageRecut.fileRect(left, quarterTurns: 1), quarterTurns: 3), left)
    }

    func testEdit_cropsTheBase_andKeepsItAsTheOtherVersion() throws {
        let file = URL(fileURLWithPath: "/spool/a.tiff")
        let page = ScannedPage(image: halves(), dpi: 200, colorMode: .color, fileURL: file)
        let left = CGRect(x: 0, y: 0, width: 0.5, height: 1)

        let cut: ScannedPage = try XCTUnwrap(PageRecut.edit(page, base: halves(), baseFile: file,
                                                            edit: PageEdit(rect: left, colorMode: .color)))
        XCTAssertEqual(cut.image.width, 20)
        XCTAssertEqual(cut.image.height, 20)
        XCTAssertEqual(cut.dpi, 200)
        XCTAssertEqual(cut.alternate?.fileURL, file)
        XCTAssertEqual(cut.alternate?.fullPixelSize, CGSize(width: 40, height: 20))
        XCTAssertEqual(cut.geometry?.cropped, true)
        XCTAssertEqual(cut.geometry?.edit?.rect, left)
        XCTAssertTrue(cut.canSwapVersions)
        XCTAssertEqual(pixels(cut.image).prefix(4), [200, 40, 40, 255])

        let bottom = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        let lower: ScannedPage = try XCTUnwrap(PageRecut.edit(page, base: halves(), baseFile: file,
                                                              edit: PageEdit(rect: bottom, colorMode: .color)))
        XCTAssertEqual(lower.image.height, 10)
        XCTAssertEqual(pixels(lower.image).prefix(4), [40, 40, 200, 255])
    }

    func testEdit_filtersTheBase_andTheColorModeFollowsTheFilter() throws {
        let file = URL(fileURLWithPath: "/spool/b.tiff")
        var page = ScannedPage(image: halves(), dpi: 200, colorMode: .color, fileURL: file)
        page.geometry = PageGeometry(cropped: true, angleDegrees: 0, basis: .pageEdges)

        let gray: ScannedPage = try XCTUnwrap(PageRecut.edit(page, base: halves(), baseFile: file,
                                                             edit: PageEdit(filter: .grayscale, colorMode: .color)))
        XCTAssertEqual(gray.colorMode, .grayscale)
        XCTAssertEqual(gray.image.width, 40)
        XCTAssertEqual(gray.geometry?.cropped, true)
        let flat: [UInt8] = pixels(gray.image)
        XCTAssertEqual(flat[0], flat[1])
        XCTAssertEqual(flat[1], flat[2])
        let blue: Int = 19 * 40 * 4
        XCTAssertFalse(Set(flat[blue..<blue + 3]).isSubset(of: [0, 255]))

        let binary: ScannedPage = try XCTUnwrap(PageRecut.edit(gray, base: halves(), baseFile: file,
                                                               edit: PageEdit(filter: .blackAndWhite, colorMode: .color)))
        XCTAssertEqual(binary.colorMode, .blackWhite)
        XCTAssertTrue(Set(pixels(binary.image).prefix(3)).isSubset(of: [0, 255]))
        XCTAssertEqual(Array(pixels(binary.image)[blue..<blue + 3]), [0, 0, 0])

        let plain: ScannedPage = try XCTUnwrap(PageRecut.edit(binary, base: halves(), baseFile: file,
                                                              edit: PageEdit(colorMode: .color)))
        XCTAssertEqual(plain.colorMode, .color)
        XCTAssertEqual(pixels(plain.image).prefix(4), [200, 40, 40, 255])

        XCTAssertNil(PageRecut.edit(page, base: halves(), baseFile: file,
                                    edit: PageEdit(rect: CGRect(x: 2, y: 2, width: 1, height: 1), colorMode: .color)))
    }

    func testAPageWithNoCaptureFacts_isEdited_shownAsSaved_orOnceEdited() {
        let file = URL(fileURLWithPath: "/spool/c.tiff")
        let plain = ScannedPage(image: halves(), dpi: 200, colorMode: .color, fileURL: file)
        XCTAssertTrue(PageRecut.canEdit(plain))
        XCTAssertFalse(PageRecut.canEdit(ScannedPage(image: halves(), dpi: 200, colorMode: .color)))
        var swapped = plain
        swapped.showsOriginal = true
        XCTAssertFalse(PageRecut.canEdit(swapped))
        swapped.geometry = PageGeometry(cropped: true, angleDegrees: 0, basis: .pageEdges, edit: PageEdit(colorMode: .color))
        XCTAssertTrue(PageRecut.canEdit(swapped))
        XCTAssertFalse(PageRecut.canEdit(plain.withCapture(CaptureFacts(quad: Quad(topLeft: .zero, topRight: .zero,
                                                                                  bottomRight: .zero, bottomLeft: .zero),
                                                                        sourceWidth: 40, sourceHeight: 20))))
    }

    @MainActor
    private func scannerState() throws -> (state: AppState, page: ScannedPage) {
        var files = AppStateFiles.all(in: folder)
        files.keepsQueue = true
        let state = AppState(presetStore: PresetStore(directory: folder), orientationScorer: RecutScorer(),
                             barcodeReader: RecutBarcodes(), files: files)
        XCTAssertTrue(state.startTask(.document))
        try FileManager.default.createDirectory(at: state.spoolDirectory, withIntermediateDirectories: true)
        let whole = ScannedPage(image: halves(), dpi: 200, colorMode: .color)
        let page: ScannedPage = try XCTUnwrap(AppState.spoolRecut(whole, to: state.spoolDirectory))
        state.scannedPages = [page]
        return (state, page)
    }

    @MainActor
    func testAScannerPage_getsFilterPreviews_ofOriginalGrayscaleAndBlackAndWhite() async throws {
        let (state, page) = try scannerState()
        defer { state.deleteSpoolFiles(of: state.scannedPages) }

        let previews: [CaptureFilter: CGImage] = await state.filterPreviews(id: page.id, maxSide: 20)
        XCTAssertEqual(Set(previews.keys), [.original, .grayscale, .blackAndWhite])
        let gray: [UInt8] = pixels(try XCTUnwrap(previews[.grayscale]))
        XCTAssertEqual(gray[0], gray[1])
        XCTAssertEqual(gray[1], gray[2])
        XCTAssertEqual(pixels(try XCTUnwrap(previews[.original])).prefix(4), [200, 40, 40, 255])
    }

    @MainActor
    func testAScannerPage_isCropped_andFiltered_eachFromThePictureBeforeTheFirstEdit() async throws {
        let (state, page) = try scannerState()
        defer { state.deleteSpoolFiles(of: state.scannedPages) }
        let firstFile: URL = try XCTUnwrap(page.fileURL)
        let top = CGRect(x: 0, y: 0.25, width: 1, height: 0.5)

        // A crop made while the page had another turn is not used.
        state.cropPage(id: page.id, to: top, rotation: 1)
        XCTAssertNil(state.pageEditChain)
        state.cropPage(id: page.id, to: top, rotation: 0)
        try await waitUntil(timeout: 60) { state.scannedPages.first?.fileURL != firstFile }
        try await waitUntil(timeout: 60) { state.pageEditChain == nil }
        let cropped: ScannedPage = state.scannedPages[0]
        XCTAssertEqual(AppState.imageInFile(try XCTUnwrap(cropped.fileURL))?.height, 10)
        XCTAssertEqual(cropped.fullPixelSize, CGSize(width: 40, height: 10))
        XCTAssertEqual(cropped.alternate?.fileURL, firstFile)
        XCTAssertEqual(cropped.geometry?.edit?.rect, top)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstFile.path))
        XCTAssertEqual(state.statusMessage, "Page 1 is cropped.")
        XCTAssertTrue(state.recuttingPages.isEmpty)
        XCTAssertEqual(PageRecut.editFilter(of: cropped), .original)

        state.filterPage(id: page.id, .blackAndWhite)
        try await waitUntil(timeout: 60) { state.scannedPages.first?.fileURL != cropped.fileURL }
        try await waitUntil(timeout: 60) { state.pageEditChain == nil }
        let binary: ScannedPage = state.scannedPages[0]
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(cropped.fileURL).path))
        XCTAssertEqual(binary.alternate?.fileURL, firstFile)
        XCTAssertEqual(binary.colorMode, .blackWhite)
        XCTAssertEqual(PageRecut.editFilter(of: binary), .blackAndWhite)
        XCTAssertEqual(state.statusMessage, "Page 1: B&W.")
        let record: QueueRecord = try JSONDecoder().decode(QueueRecord.self, from: Data(contentsOf: state.spoolDirectory.appendingPathComponent(QueueRecord.fileName)))
        XCTAssertEqual(record.pages.first?.geometry?.edit, binary.geometry?.edit)

        // Grayscale after B&W is made from the picture before the edits, not from the black and white one.
        state.filterPage(id: page.id, .grayscale)
        try await waitUntil(timeout: 60) { state.scannedPages.first?.fileURL != binary.fileURL }
        try await waitUntil(timeout: 60) { state.pageEditChain == nil }
        let gray: ScannedPage = state.scannedPages[0]
        let grayPixels: [UInt8] = pixels(try XCTUnwrap(AppState.imageInFile(try XCTUnwrap(gray.fileURL))))
        let blueRow: Int = 9 * 40 * 4
        XCTAssertEqual(grayPixels[blueRow], grayPixels[blueRow + 1])
        XCTAssertFalse(Set(grayPixels[blueRow..<blueRow + 3]).isSubset(of: [0, 255]))
        XCTAssertEqual(gray.colorMode, .grayscale)
        XCTAssertEqual(gray.alternate?.fileURL, firstFile)

        // Original takes the filter off and keeps the crop.
        state.filterPage(id: page.id, .original)
        try await waitUntil(timeout: 60) { state.scannedPages.first?.fileURL != gray.fileURL }
        try await waitUntil(timeout: 60) { state.pageEditChain == nil }
        let back: ScannedPage = state.scannedPages[0]
        XCTAssertEqual(back.colorMode, .color)
        XCTAssertEqual(pixels(try XCTUnwrap(AppState.imageInFile(try XCTUnwrap(back.fileURL)))).prefix(4), [200, 40, 40, 255])
        XCTAssertEqual(AppState.imageInFile(try XCTUnwrap(back.fileURL))?.height, 10)

        // Crop opens on the whole picture with the part kept chosen; the whole rectangle undoes the crop.
        let editStart: PageEditStart? = await state.pageEditStart(id: page.id)
        let start: PageEditStart = try XCTUnwrap(editStart)
        XCTAssertEqual(start.image.height, 20)
        XCTAssertEqual(start.rect, top)
        state.cropPage(id: page.id, to: CGRect(x: 0, y: 0, width: 1, height: 1), rotation: 0)
        try await waitUntil(timeout: 60) { state.scannedPages.first?.fileURL != back.fileURL }
        try await waitUntil(timeout: 60) { state.pageEditChain == nil }
        XCTAssertEqual(AppState.imageInFile(try XCTUnwrap(state.scannedPages[0].fileURL))?.height, 20)
        XCTAssertNil(state.scannedPages[0].geometry?.edit?.rect)

        // Shown as scanned, the page can still be edited, and shows the edit again.
        state.togglePageGeometry(id: page.id)
        try await waitUntil(timeout: 60) { state.scannedPages.first?.showsOriginal == true }
        try await waitUntil(timeout: 60) { state.pageEditChain == nil }
        XCTAssertEqual(state.scannedPages[0].fileURL, firstFile)
        XCTAssertTrue(PageRecut.canEdit(state.scannedPages[0]))
        XCTAssertEqual(PageRecut.editFilter(of: state.scannedPages[0]), .original)
        state.filterPage(id: page.id, .grayscale)
        try await waitUntil(timeout: 60) { state.scannedPages.first?.showsOriginal == false }
        try await waitUntil(timeout: 60) { state.pageEditChain == nil }
        XCTAssertEqual(state.scannedPages[0].alternate?.fileURL, firstFile)
        XCTAssertEqual(state.scannedPages[0].colorMode, .grayscale)
    }
}
