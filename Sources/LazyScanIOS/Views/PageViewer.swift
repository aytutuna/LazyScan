#if os(iOS)
import LazyScanKit
import CoreGraphics
import ImageIO
import SwiftUI
import UIKit
import VisionKit
import UniformTypeIdentifiers

/// The page the viewer opens on.
struct PageViewerStart: Identifiable {
    let id: UUID
}

/// What the page grid and the page viewer say.
enum PageViewerText {
    static var rotateLabel: String { String(localized: "Rotate") }
    static var filtersLabel: String { String(localized: "Filters") }
    static var adjustLabel: String { String(localized: "Adjust") }
    static var adjustHint: String { String(localized: "Changes brightness and contrast of this page") }
    static var cropLabel: String { String(localized: "Crop") }
    static var markUpLabel: String { String(localized: "Mark Up") }
    static var markUpHint: String { String(localized: "Draws on this page") }
    static var penLabel: String { String(localized: "Pen") }
    static var highlighterLabel: String { String(localized: "Highlighter") }
    static var undoStrokeLabel: String { String(localized: "Undo stroke") }
    static var discardMarksQuestion: String { String(localized: "Discard these marks?") }
    static var discardLabel: String { String(localized: "Discard") }
    static var keepDrawingLabel: String { String(localized: "Keep Drawing") }
    static var drawingAreaLabel: String { String(localized: "Drawing area for the page") }
    static var cropRemovesMarksTitle: String { String(localized: "Cropping removes the marks") }
    static var cropRemovesMarksMessage: String { String(localized: "The marks on this page are taken off when it is cropped.") }
    static var documentLabel: String { String(localized: "Document") }
    static var nameDocumentLabel: String { String(localized: "Name document\u{2026}") }
    static var nameDocumentTitle: String { String(localized: "Name this document") }
    static var retakeLabel: String { String(localized: "Retake") }
    static var retakeHint: String { String(localized: "Takes this page again with the camera") }
    static var textLabel: String { String(localized: "Text") }
    static var textTitle: String { String(localized: "Text on this page") }
    static var readingText: String { String(localized: "Reading the text\u{2026}") }
    static var noText: String { String(localized: "No text found on this page") }
    static var textFailed: String { String(localized: "The text could not be read") }
    static var copyLabel: String { String(localized: "Copy") }
    static var removeLabel: String { String(localized: "Remove") }
    static var removeAllLabel: String { String(localized: "Remove All") }
    static var actionsLabel: String { String(localized: "Actions") }
    static var openHint: String { String(localized: "Opens the page") }
    static var removeQuestion: String { String(localized: "Remove this page?") }
    static var deleteMessage: String { String(localized: "It is taken out of the pages to save.") }
    static var selectLabel: String { String(localized: "Select") }
    static var selectAllLabel: String { String(localized: "Select All") }
    static var deselectAllLabel: String { String(localized: "Deselect All") }
    static var cancelLabel: String { String(localized: "Cancel") }
    static var shareLabel: String { String(localized: "Share") }
    static var moveLabel: String { String(localized: "Move") }
    static var moveToStartLabel: String { String(localized: "Move to Beginning") }
    static var moveToEndLabel: String { String(localized: "Move to End") }
    static var filterLabel: String { String(localized: "Filter") }
    static var applyToAllLabel: String { String(localized: "Apply to All") }
    /// The cards of the grid have a sheet's shape (between A4 and Letter); every page is fitted whole in one.
    static let cardAspect: CGFloat = 0.75

    /// "3 of 7"
    static func title(number: Int, count: Int) -> String {
        String(localized: "\(number) of \(count)")
    }

    /// The filter as VoiceOver says it: the visible label.
    static func filterName(_ filter: CaptureFilter) -> String {
        filter.label
    }

    /// "Page 3"
    static func pageName(_ number: Int) -> String {
        String(localized: "Page \(number)")
    }

    /// "Applying, 7 left" while the pages of a filter run are cut again.
    static func applyingLeft(_ count: Int) -> String {
        String(localized: "Applying, \(count) left")
    }

    /// The page grid's title while pages are picked: "Select Pages", "2 Selected".
    static func selectedTitle(_ count: Int) -> String {
        count == 0 ? String(localized: "Select Pages") : L10n.plural(count, one: "{0} Selected", other: "{0} Selected")
    }

    /// "Remove 3 pages?" for the pages picked in the grid.
    static func removePagesQuestion(_ count: Int) -> String {
        L10n.plural(count, one: "Remove {0} page?", other: "Remove {0} pages?")
    }

    /// "Remove all 3 pages?" for Remove All in the page grid.
    static func removeAllQuestion(_ count: Int) -> String {
        L10n.plural(count, one: "Remove {0} page?|all", other: "Remove all {0} pages?")
    }
}

/// One page at a time over the whole screen, fitted whole within the safe area: pinch or double-tap to zoom,
/// swipe to the next page, "3 of 7" over it and Done, and the grid's note on a page saving leaves out (or
/// may) on a badge in its corner. Its toolbar shows the filters of a camera's page (a row of small pictures
/// of this page with each, `AppState.filterPreviews`), turns it a quarter, opens the corner editor on its
/// photo for Crop (`AppState.pageCropStart`, `recropPage`), takes it again with the camera (Retake, `onRetake`, for a page
/// from a photo), shows the text on it (`PageTextSheet`), keeps or
/// skips it (`PageStripCell.toggle`), for a book's page splits its spread again (`onEditSpread`) or joins its
/// two pages, starts a new document at it, joins it to the one before and names its document (the Document
/// menu, `DocumentMenuItems`), and deletes it once asked; the edits are off
/// while the app is busy, and the filters, Crop and Remove also while a share or a send reads the pages
/// (`AppState.readsQueue`).
/// Filters (`PageRecut.canRecut`; not for a photo) and Crop (`PageRecut.canCrop`) cut a camera's page out of its
/// photo again. A page with no capture facts (a scan, an imported PDF, the pages of a book's spread taken whole;
/// `PageRecut.canEdit`) has Original, Grayscale and B&W, and Crop opens the rectangle crop (`RectCropView`).
struct PageViewer: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Opens the split sheet for the spread the page shown was cut from; nil where the viewer cannot.
    let onEditSpread: (@MainActor (UUID) -> Void)?
    /// Shows the camera to take a page again (the page's id); nil where the viewer cannot, as in the scanner's mode.
    let onRetake: (@MainActor (UUID) -> Void)?
    let onClose: () -> Void
    @State private var selection: UUID?
    @State private var showsFilters: Bool = false
    /// The Adjust segment of the filter slot is shown instead of the filters.
    @State private var showsAdjust: Bool = false
    /// Brightness and contrast moved since the page was last cut, on the slider's -100...100 scale: shown at once
    /// and cut in when the finger lifts; dropped once the page is cut or the page shown changes.
    @State private var adjustDraft: [IOSAdjustment: Double] = [:]
    @State private var previews: [CaptureFilter: CGImage] = [:]
    /// The previews are being made; once they are in, a filter without one shows a plain tile.
    @State private var loadingPreviews: Bool = false
    @State private var asksDelete: Bool = false
    /// The page whose document is being named.
    @State private var namingPage: UUID?
    /// The page whose text is shown.
    @State private var textOf: PageViewerStart?
    @State private var crop: IOSCropRequest?
    @State private var rectCrop: RectCropRequest?
    @State private var preparesCrop: Bool = false
    @State private var markUp: MarkUpRequest?
    @State private var asksCropWithMarks: Bool = false
    /// The pages' pictures with their marks drawn in, kept until the picture or the marks change.
    @State private var markedPictures: MarkedPictures = MarkedPictures()
    /// The page's rotation when the corner editor's picture was turned for it.
    @State private var cropRotation: Int = 0
    /// The filter tapped last for each page, shown as chosen while the page is cut again.
    @State private var requested: [UUID: CaptureFilter] = [:]
    /// The page shown and the ones either side of it read from their spool files, sharper than the queue's previews.
    @State private var sharpCache: SharpCache = SharpCache()
    /// Set by a memory warning: only the page shown is read until the plan changes.
    @State private var shownOnly: Bool = false
    /// The pager's longest side so far, in points: it only grows, so turning the phone reads nothing again.
    @State private var viewSide: CGFloat = 0
    /// The zoom of each page pinched or double tapped, to the tenth the readout shows; a page not in it is at 1.
    @State private var zooms: [UUID: Double] = [:]
    /// The zoom readout is up: while pinching, and a second after a pinch or a double tap.
    @State private var showsZoom: Bool = false

    /// What a page is read from: its spool file, at `side` pixels on its longer side (`pixels` in all), turned
    /// `turns`. `preview` is the queue's preview the page has: turned, cut again, swapped or replaced, a page
    /// gets a new one, so a picture read before is never shown for it.
    struct SharpRead: Equatable {
        let page: UUID
        let preview: ObjectIdentifier
        let url: URL
        let side: Int
        let turns: Int
        let pixels: Int
    }

    /// The pages read sharper that the viewer holds: at most `limit`, and a big one alone.
    struct SharpCache {
        struct Entry {
            let read: SharpRead
            /// Kept alive with the picture, so `read.preview` cannot come back as another preview's identifier.
            let preview: CGImage
            let image: CGImage
        }

        static let limit: Int = 3
        /// A page read over this many pixels is held alone: three of them would take a few hundred MB.
        static let bigPixels: Int = 20_000_000

        private(set) var entries: [Entry] = []

        /// The pages to hold read with the page shown `current`: it and the ones either side of it, or only it
        /// when it is big; a big page either side is left out.
        static func kept(current: SharpRead?, neighbours: [SharpRead]) -> [SharpRead] {
            if let current, current.pixels > Self.bigPixels { return [current] }
            let small: [SharpRead] = neighbours.filter { (read: SharpRead) -> Bool in read.pixels <= Self.bigPixels }
            guard let current else { return small }
            return [current] + small
        }

        func image(for read: SharpRead) -> CGImage? {
            entries.first(where: { (entry: Entry) -> Bool in entry.read == read })?.image
        }

        /// Lets go of every picture not read for one of `reads`.
        mutating func keep(_ reads: [SharpRead]) {
            entries.removeAll { (entry: Entry) -> Bool in !reads.contains(entry.read) }
        }

        /// Lets go of every picture but the one read for `page` (the page shown), on a memory warning.
        mutating func keepOnly(_ page: UUID?) {
            entries.removeAll { (entry: Entry) -> Bool in entry.read.page != page }
        }

        /// Holds `image`, read for `read` from the page whose preview is `preview`, in place of what was read
        /// for that page before; the oldest go past `limit`, and all the others with a big one.
        mutating func add(_ image: CGImage, read: SharpRead, preview: CGImage) {
            let big: Bool = read.pixels > Self.bigPixels
            entries.removeAll { (entry: Entry) -> Bool in big || entry.read.page == read.page }
            entries.append(Entry(read: read, preview: preview, image: image))
            if entries.count > Self.limit {
                entries.removeFirst(entries.count - Self.limit)
            }
        }
    }

    init(startID: UUID, onEditSpread: (@MainActor (UUID) -> Void)? = nil, onRetake: (@MainActor (UUID) -> Void)? = nil,
         onClose: @escaping () -> Void) {
        self.onEditSpread = onEditSpread
        self.onRetake = onRetake
        self.onClose = onClose
        _selection = State(initialValue: startID)
    }

    /// The page after `id` once it is deleted, or the one before it when it was the last; nil when none is left.
    nonisolated static func pageAfterRemoving(_ id: UUID, from ids: [UUID]) -> UUID? {
        guard let index = ids.firstIndex(of: id) else { return nil }
        if index + 1 < ids.count { return ids[index + 1] }
        return index > 0 ? ids[index - 1] : nil
    }

    /// The longer side, in pixels, the page shown is read at from its spool file: three times the view's, so
    /// a zoom stays sharp, but no more than the page has; 0 when the queue's preview has as many already.
    nonisolated static func sharpSide(view: Int, page: Int, preview: Int) -> Int {
        let side: Int = min(view * 3, page)
        return side > preview ? side : 0
    }

    /// The pixels of a page `page` pixels large read at `side` pixels on its longer side.
    nonisolated static func readPixels(side: Int, page: CGSize) -> Int {
        let long: Double = Double(max(page.width, page.height, 1))
        let short: Double = Double(min(page.width, page.height))
        return Int(Double(side) * Double(side) * short / long)
    }

    /// The picture in the spool file `url`, at most `maxSide` pixels on its longer side and turned as
    /// `AppState.fullImage(of:number:)` turns the file; nil when it cannot be read.
    nonisolated static func readPage(_ url: URL, maxSide: Int, quarterTurns: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return ImagePipeline.rotate(image, quarterTurns: quarterTurns)
    }

    /// Whether two pictures have the same proportions, but for the rounding of a smaller copy's sides.
    nonisolated static func sameShape(_ a: CGSize, _ b: CGSize) -> Bool {
        abs(a.width * b.height - b.width * a.height) <= max(a.width, a.height, b.width, b.height)
    }

    private var current: ScannedPage? {
        state.scannedPages.first(where: { (page: ScannedPage) -> Bool in page.id == selection })
    }

    private var number: Int {
        let index: Int? = state.scannedPages.firstIndex(where: { (page: ScannedPage) -> Bool in page.id == selection })
        return (index ?? 0) + 1
    }

    private var canRecut: Bool {
        current.map { (page: ScannedPage) -> Bool in PageRecut.canRecut(page) } ?? false
    }

    private var canCrop: Bool {
        current.map { (page: ScannedPage) -> Bool in PageRecut.canCrop(page) } ?? false
    }

    private var canEdit: Bool {
        current.map { (page: ScannedPage) -> Bool in PageRecut.canEdit(page) } ?? false
    }

    private var offersFilters: Bool { canRecut || canEdit }

    /// Brightness and contrast are cut in from the page's photo, so only a camera's page that can be cropped has them.
    private var offersAdjust: Bool { canCrop }

    private var offersSlot: Bool { offersFilters || offersAdjust }

    private var offersCrop: Bool { canCrop || canEdit }

    private var canRetake: Bool {
        guard onRetake != nil, let page = current else { return false }
        return AppState.canRetake(page)
    }

    /// The page shown as the grid has it, for its Keep or Skip.
    private var currentCell: PageStripCell? {
        let cells: [PageStripCell] = PageStripCell.cells(state.scannedPages, options: state.settings.document)
        return cells.first(where: { (cell: PageStripCell) -> Bool in cell.id == selection })
    }

    /// Each page's note as the grid shows it ("Blank, skipped", "Separator"), by page.
    private var pageNotes: [UUID: String] {
        var notes: [UUID: String] = [:]
        for cell in PageStripCell.cells(state.scannedPages, options: state.settings.document) {
            notes[cell.id] = cell.note
        }
        return notes
    }

    /// What `page` is read from for a sharper picture; nil for a page without a spool file, or one whose preview
    /// is as sharp as the view needs.
    private func sharpRead(of page: ScannedPage) -> SharpRead? {
        guard let url = page.fileURL, let size = page.fullPixelSize else { return nil }
        let side: Int = Self.sharpSide(view: Int(viewSide * displayScale), page: Int(max(size.width, size.height)),
                                       preview: max(page.image.width, page.image.height))
        guard side > 0 else { return nil }
        return SharpRead(page: page.id, preview: ObjectIdentifier(page.image), url: url, side: side,
                         turns: page.rotationQuarterTurns, pixels: Self.readPixels(side: side, page: size))
    }

    /// What the viewer holds read sharper: the page shown, then the next and the one before (`SharpCache.kept`).
    private var sharpPlan: [SharpRead] {
        let pages: [ScannedPage] = state.scannedPages
        guard let index = pages.firstIndex(where: { (page: ScannedPage) -> Bool in page.id == selection }) else { return [] }
        var neighbours: [SharpRead] = []
        for other in [index + 1, index - 1] where other >= 0 && other < pages.count {
            if let read = sharpRead(of: pages[other]) {
                neighbours.append(read)
            }
        }
        return SharpCache.kept(current: sharpRead(of: pages[index]), neighbours: neighbours)
    }

    /// What the filter previews are made from: the page, its turn and its corners (not its filter); for a page
    /// with no capture facts the part of its picture kept.
    private var previewKey: String {
        guard let page = current, showsFilters, offersFilters else { return "" }
        let basis: String = canEdit ? String(describing: page.geometry?.edit?.rect) : String(describing: page.capture?.quad) + String(describing: page.capture?.adjustments)
        return "\(page.id.uuidString) \(page.rotationQuarterTurns) \(basis)"
    }

    var body: some View {
        NavigationStack {
            pager
                .background(Color(uiColor: .systemGroupedBackground))
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if showsFilters, offersSlot, let page = current {
                        filterSlot(page)
                    }
                }
                .navigationTitle(PageViewerText.title(number: number, count: state.scannedPages.count))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            onClose()
                        }
                        .accessibilityIdentifier("viewer.done")
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        actions
                    }
                }
                .toolbarBackground(Visibility.visible, for: .bottomBar)
        }
        .confirmationDialog(PageViewerText.removeQuestion, isPresented: $asksDelete, titleVisibility: .visible) {
            Button(PageViewerText.removeLabel, role: .destructive) {
                deleteCurrent()
            }
            .accessibilityIdentifier("viewer.confirmDelete")
        } message: {
            Text(PageViewerText.deleteMessage)
        }
        .confirmationDialog(PageViewerText.cropRemovesMarksTitle, isPresented: $asksCropWithMarks, titleVisibility: .visible) {
            Button(PageViewerText.cropLabel, action: openCrop)
        } message: {
            Text(PageViewerText.cropRemovesMarksMessage)
        }
        .modifier(DocumentNameAlert(state: state, page: $namingPage))
        .sheet(item: $textOf) { (shown: PageViewerStart) in
            PageTextSheet(pageID: shown.id)
                .environmentObject(state)
        }
        .fullScreenCover(item: $crop) { (request: IOSCropRequest) in
            CornerEditorView(request: request.request, onAnswer: { (answer: PhotoCornersAnswer) -> Void in
                finishCrop(request, answer: answer)
            }, fixesCrop: true)
        }
        .fullScreenCover(item: $rectCrop) { (request: RectCropRequest) in
            RectCropView(image: request.image, start: request.start, onAnswer: { (rect: CGRect?) -> Void in
                finishRectCrop(request, rect: rect)
            })
        }
        .fullScreenCover(item: $markUp) { (request: MarkUpRequest) in
            MarkUpView(image: request.image, marks: request.marks, quarterTurns: request.quarterTurns,
                       showsOriginal: request.showsOriginal, canFinish: !state.isBusy, onAnswer: { (marks: PageMarks?) -> Void in
                finishMarkUp(request, marks: marks)
            })
        }
        .onChange(of: state.scannedPages.count) { (_: Int, _: Int) in
            markedPictures.keep(Set(state.scannedPages.map { (page: ScannedPage) -> UUID in page.id }))
            if let request = markUp, !state.scannedPages.contains(where: { (page: ScannedPage) -> Bool in page.id == request.id }) {
                markUp = nil
            }
        }
        .onChange(of: selection) { (_: UUID?, _: UUID?) in
            adjustDraft = [:]
            if !offersAdjust { showsAdjust = false }
        }
        .task(id: previewKey) {
            await loadPreviews()
        }
        .task(id: sharpPlan) {
            await loadSharp()
        }
        // The neighbours are read again on the next swipe; the page shown stays sharp.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { (_: Notification) in
            shownOnly = true
            sharpCache.keepOnly(selection)
        }
        .modifier(ErrorAlert(state: state))
    }

    // MARK: The pages

    private var pager: some View {
        let notes: [UUID: String] = pageNotes
        return TabView(selection: $selection) {
            ForEach(state.scannedPages) { (page: ScannedPage) in
                pageView(page, note: notes[page.id])
                    .tag(Optional(page.id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // The page being cropped stays on screen while its photo is read.
        .allowsHitTesting(!preparesCrop)
        .overlay(alignment: .top) {
            if showsZoom, let id = selection {
                StatusPill(text: IOSCameraText.zoomLabel(zooms[id] ?? 1), hint: nil)
                    .padding(.top, 12)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("viewer.zoomReadout")
            }
        }
        .accessibilityIdentifier("viewer.pages")
        .onGeometryChange(for: CGFloat.self) { (proxy: GeometryProxy) -> CGFloat in
            max(proxy.size.width, proxy.size.height)
        } action: { (side: CGFloat) in
            if side > viewSide {
                viewSide = side
            }
        }
    }

    private func pageView(_ page: ScannedPage, note: String?) -> some View {
        let index: Int = state.scannedPages.firstIndex(where: { (item: ScannedPage) -> Bool in item.id == page.id }) ?? 0
        let label: String = PageViewerText.title(number: index + 1, count: state.scannedPages.count)
        let spoken: String = note.map { (text: String) -> String in String(localized: "Page \(label), \(text)") } ?? String(localized: "Page \(label)")
        let pageID: UUID = page.id
        return ZoomablePage(image: shownImage(page), isShown: pageID == selection,
                            onZoom: { (zoom: Double, shown: Bool) -> Void in showZoom(of: pageID, zoom, shown: shown) })
            .environment(\.layoutDirection, .leftToRight)
            .overlay {
                if state.recuttingPages.contains(page.id) {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .overlay(alignment: .topLeading) {
                if let note {
                    noteBadge(note)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(spoken))
            .accessibilityValue(Text(IOSCameraText.zoomLabel(zooms[pageID] ?? 1)))
            .accessibilityAddTraits(.isImage)
            .accessibilityAction(named: Text("Next page")) {
                step(by: 1)
            }
            .accessibilityAction(named: Text("Previous page")) {
                step(by: -1)
            }
            .accessibilityIdentifier("viewer.page.\(index + 1)")
    }

    private func showZoom(of id: UUID, _ zoom: Double, shown: Bool) {
        let tenths: Double = (zoom * 10).rounded() / 10
        if zooms[id] != tenths {
            zooms[id] = tenths
        }
        if shown {
            showsZoom = true
        } else {
            withAnimation(reduceMotion ? nil : Animation.easeOut(duration: 0.3)) {
                showsZoom = false
            }
        }
    }

    /// The grid's note on the page, on a badge in the corner as the grid has it.
    private func noteBadge(_ note: String) -> some View {
        Text(note)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.black.opacity(0.65)))
            .padding(12)
            .allowsHitTesting(false)
    }

    /// The page's preview, or its sharper picture once it is read as the page is now.
    private func shownImage(_ page: ScannedPage) -> CGImage {
        markedPictures.picture(pictureOf(page), of: page)
    }

    /// The page's picture without its marks.
    private func pictureOf(_ page: ScannedPage) -> CGImage {
        guard let read = sharpRead(of: page), let sharp = sharpCache.image(for: read) else { return page.image }
        return sharp
    }

    /// Reads the page shown, then the ones either side of it, from their spool files off the main actor, to show
    /// in place of their previews; a swipe then lands on a page read already. What was read for pages no longer
    /// near, or for a page as it was before a change, is let go first.
    private func loadSharp() async {
        shownOnly = false
        sharpCache.keep(sharpPlan)
        // Turns and filters clicked earlier land first, so the files read are the ones the pages end up with.
        await state.pageEditChain?.value
        for read in sharpPlan where sharpCache.image(for: read) == nil {
            guard !Task.isCancelled else { return }
            // A memory warning while this runs leaves the neighbours to the next plan.
            guard !shownOnly || read.page == selection else { return }
            guard let preview = state.scannedPages.first(where: { (page: ScannedPage) -> Bool in page.id == read.page })?.image,
                  ObjectIdentifier(preview) == read.preview else { continue }
            let priority: TaskPriority = read.page == selection ? .userInitiated : .utility
            let image: CGImage? = await Task.detached(priority: priority) { () -> CGImage? in
                PageViewer.readPage(read.url, maxSide: read.side, quarterTurns: read.turns)
            }.value
            // The read can land after a swipe or edit but before SwiftUI cancels this task; one no longer planned
            // would only push out entries that are.
            guard !Task.isCancelled, sharpPlan.contains(read), !shownOnly || read.page == selection else { return }
            if let image {
                sharpCache.add(image, read: read, preview: preview)
            }
        }
    }

    private func step(by offset: Int) {
        guard let index = state.scannedPages.firstIndex(where: { (page: ScannedPage) -> Bool in page.id == selection }) else { return }
        let next: Int = index + offset
        guard next >= 0 && next < state.scannedPages.count else { return }
        show(state.scannedPages[next].id)
    }

    private func show(_ id: UUID) {
        if reduceMotion {
            selection = id
        } else {
            withAnimation {
                selection = id
            }
        }
    }

    // MARK: The toolbar

    @ViewBuilder
    private var actions: some View {
        // The queue's edits do nothing while an import, a scan or a save runs.
        let blocked: Bool = state.isBusy || preparesCrop
        if offersSlot {
            Button(action: toggleFilters) {
                Label(PageViewerText.filtersLabel, systemImage: "camera.filters")
            }
            .accessibilityValue(Text(showsFilters ? String(localized: "Shown") : String(localized: "Hidden")))
            .accessibilityIdentifier("viewer.filters")
            Spacer()
        }
        Button(action: rotateCurrent) {
            Label(PageViewerText.rotateLabel, systemImage: "rotate.right")
        }
        .disabled(blocked)
        .accessibilityIdentifier("viewer.rotate")
        Spacer()
        if offersCrop {
            Button(action: askCrop) {
                Label(PageViewerText.cropLabel, systemImage: "crop")
            }
            .disabled(blocked || state.readsQueue)
            .accessibilityIdentifier("viewer.crop")
            Spacer()
            let marked: Bool = current.map { (page: ScannedPage) -> Bool in MarkedPictures.shows(page) } ?? false
            let markUpSymbol: String = marked ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle"
            Button(action: openMarkUp) {
                Label(PageViewerText.markUpLabel, systemImage: markUpSymbol)
            }
            .disabled(blocked || state.readsQueue)
            .accessibilityHint(Text(PageViewerText.markUpHint))
            .accessibilityIdentifier("viewer.markup")
            Spacer()
        }
        if let page = current, let swapLabel = PageCorrections.toggleLabel(page) {
            let swapSymbol: String = page.showsOriginal ? "arrow.uturn.forward" : "arrow.uturn.backward"
            Button(action: swapCurrent) {
                Label(swapLabel, systemImage: swapSymbol)
            }
            .disabled(blocked)
            .accessibilityIdentifier("viewer.swap")
            Spacer()
        }
        if canRetake {
            Button(action: retakeCurrent) {
                Label(PageViewerText.retakeLabel, systemImage: "camera")
            }
            .disabled(blocked || state.readsQueue)
            .accessibilityHint(Text(PageViewerText.retakeHint))
            .accessibilityIdentifier("viewer.retake")
            Spacer()
        }
        Button(action: showText) {
            Label(PageViewerText.textLabel, systemImage: "text.viewfinder")
        }
        .disabled(preparesCrop)
        .accessibilityIdentifier("viewer.text")
        Spacer()
        if let cell = currentCell, let toggle = cell.toggle {
            Button(action: toggleInclusion) {
                Label(toggle, systemImage: cell.toggleSymbol)
            }
            .disabled(state.isBusy)
            .accessibilityIdentifier("viewer.keep")
            Spacer()
        }
        if let page = current, state.canEditSpread(of: page) {
            if let split = BookPages.splitActionLabel(page), onEditSpread != nil {
                Button(action: splitCurrent) {
                    Label(split, systemImage: "rectangle.split.2x1")
                }
                .disabled(blocked)
                .accessibilityIdentifier("viewer.split")
                Spacer()
            }
            if let join = BookPages.joinActionLabel(page) {
                Button(action: joinCurrent) {
                    Label(join, systemImage: "rectangle")
                }
                .disabled(blocked)
                .accessibilityIdentifier("viewer.join")
                Spacer()
            }
        }
        if let cell = currentCell, cell.hasDocumentMenu {
            Menu {
                DocumentMenuItems(state: state, cell: cell, onName: nameCurrentDocument)
            } label: {
                Label(PageViewerText.documentLabel, systemImage: "scissors")
            }
            .disabled(state.isBusy)
            .accessibilityIdentifier("viewer.document")
            Spacer()
        }
        Button(role: .destructive, action: askDelete) {
            Label(PageViewerText.removeLabel, systemImage: "trash")
        }
        .disabled(state.isBusy || state.readsQueue)
        .accessibilityIdentifier("viewer.delete")
    }

    private func retakeCurrent() {
        guard let id = selection else { return }
        state.startRetake(id: id)
        guard state.retakingID == id else { return }
        onRetake?(id)
    }

    private func splitCurrent() {
        guard let id = selection else { return }
        onEditSpread?(id)
    }

    private func joinCurrent() {
        guard let id = selection else { return }
        state.joinSpread(id: id)
        onClose()
    }

    private func toggleFilters() {
        showsFilters.toggle()
    }

    private func swapCurrent() {
        guard let id = selection else { return }
        state.togglePageGeometry(id: id)
    }

    private func rotateCurrent() {
        guard let id = selection else { return }
        state.rotatePage(id: id)
    }

    private func nameCurrentDocument() {
        namingPage = selection
    }

    private func toggleInclusion() {
        guard let id = selection else { return }
        state.togglePageInclusion(id: id)
    }

    private func showText() {
        guard let id = selection else { return }
        textOf = PageViewerStart(id: id)
    }

    private func askDelete() {
        asksDelete = true
    }

    private func deleteCurrent() {
        guard let id = selection else { return }
        var ids: [UUID] = []
        for page in state.scannedPages {
            ids.append(page.id)
        }
        let next: UUID? = Self.pageAfterRemoving(id, from: ids)
        state.removePage(id: id)
        guard let next, !state.scannedPages.contains(where: { (page: ScannedPage) -> Bool in page.id == id }) else {
            if state.scannedPages.isEmpty { onClose() }
            return
        }
        show(next)
    }

    // MARK: Filters

    /// The filters, and for a camera's page that can be cut again the Adjust sliders beside them; a photo has
    /// no filters, so only the sliders.
    private func filterSlot(_ page: ScannedPage) -> some View {
        let segments: Bool = offersFilters && offersAdjust
        let adjusting: Bool = offersAdjust && (showsAdjust || !offersFilters)
        return VStack(spacing: 0) {
            if segments {
                adjustPicker
            }
            if adjusting {
                adjustRow(page)
            } else {
                filterRow(page)
            }
        }
    }

    private var adjustPicker: some View {
        Picker(PageViewerText.filtersLabel, selection: $showsAdjust) {
            Text(PageViewerText.filtersLabel).tag(false)
            Text(PageViewerText.adjustLabel).tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(.bar)
        .accessibilityHint(Text(PageViewerText.adjustHint))
        .accessibilityIdentifier("viewer.adjust")
    }

    private func filterRow(_ page: ScannedPage) -> some View {
        let working: Bool = state.recuttingPages.contains(page.id)
        let edits: Bool = PageRecut.canEdit(page)
        let chosen: CaptureFilter? = chosenFilter(page, working: working, edits: edits)
        let filters: [CaptureFilter] = edits ? PageRecut.editFilters : CaptureFilter.displayOrder
        return VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(filters, id: \.self) { (filter: CaptureFilter) in
                        filterButton(filter, page: page, chosen: filter == chosen)
                    }
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
            }
            if state.scannedPages.count > 1, let chosen {
                applyToAllButton(chosen)
            }
        }
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("viewer.filterRow")
    }

    private func adjustRow(_ page: ScannedPage) -> some View {
        let working: Bool = state.recuttingPages.contains(page.id)
        let off: Bool = state.isBusy || state.readsQueue || working
        let stored: AdjustmentSettings = PageRecut.adjustments(of: page)
        let neutral: Bool = [IOSAdjustment.brightness, IOSAdjustment.contrast].allSatisfy { (kind: IOSAdjustment) -> Bool in
            (adjustDraft[kind] ?? kind.amount(stored)).rounded() == 0
        }
        let controls = VStack(spacing: 12) {
            adjustSlider(.brightness, page: page, stored: stored, working: working, off: off)
            adjustSlider(.contrast, page: page, stored: stored, working: working, off: off)
            HStack {
                Spacer()
                Button(IOSSettingsText.resetLabel) {
                    resetAdjust(page)
                }
                .frame(minHeight: 44)
                .disabled(off || neutral)
                .accessibilityIdentifier("adjust.reset")
            }
        }
        let scrolls: Bool = typeSize.isAccessibilitySize
        return Group {
            if scrolls {
                ScrollView { controls }.frame(maxHeight: 240)
            } else {
                controls
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .onChange(of: working) { (_: Bool, now: Bool) in
            if !now { adjustDraft = [:] }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("viewer.adjustRow")
    }

    private func adjustSlider(_ kind: IOSAdjustment, page: ScannedPage, stored: AdjustmentSettings, working: Bool,
                              off: Bool) -> some View {
        let value: Double = adjustDraft[kind] ?? kind.amount(stored)
        let binding = Binding<Double>(get: { value }, set: { (now: Double) in adjustDraft[kind] = now })
        let recutting: Bool = working && adjustDraft[kind] != nil
        let roomy: Bool = typeSize.isAccessibilitySize
        let layout: AnyLayout = roomy ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout())
        return VStack(spacing: 0) {
            layout {
                Text(kind.label)
                    .font(.callout)
                if !roomy {
                    Spacer()
                }
                if recutting {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                } else {
                    Text(IOSAdjustment.amountText(value))
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(Color.secondary)
                }
            }
            HStack(spacing: 8) {
                Text(IOSAdjustment.amountText(-100))
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
                Slider(value: binding, in: -100...100, step: 1, onEditingChanged: { (editing: Bool) in
                    if !editing { commitAdjust(page) }
                })
                .disabled(off)
                .accessibilityLabel(Text(kind.label))
                .accessibilityValue(Text(IOSAdjustment.amountText(value)))
                .accessibilityAdjustableAction { (direction: AccessibilityAdjustmentDirection) in
                    var moved: Double = value
                    switch direction {
                    case .increment: moved += 5
                    case .decrement: moved -= 5
                    @unknown default: break
                    }
                    adjustDraft[kind] = min(100, max(-100, moved))
                    commitAdjust(page)
                }
                .accessibilityIdentifier("adjust.\(kind.rawValue)")
                Text(IOSAdjustment.amountText(100))
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)
            }
            .frame(minHeight: 44)
        }
    }

    /// Cuts the page again with the brightness and contrast moved, from its photo.
    private func commitAdjust(_ page: ScannedPage) {
        let stored: AdjustmentSettings = PageRecut.adjustments(of: page)
        var adjustments: AdjustmentSettings = stored
        for (kind, amount) in adjustDraft {
            adjustments = kind.setting(amount, in: adjustments)
        }
        guard adjustments != stored else {
            adjustDraft = [:]
            return
        }
        state.setPageAdjustments(id: page.id, adjustments)
    }

    private func resetAdjust(_ page: ScannedPage) {
        adjustDraft = [.brightness: 0, .contrast: 0]
        commitAdjust(page)
    }

    private func applyToAllButton(_ filter: CaptureFilter) -> some View {
        let left: Int = state.filterPagesLeft
        let title: String = left > 0 ? PageViewerText.applyingLeft(left) : PageViewerText.applyToAllLabel
        let off: Bool = state.isBusy || state.readsQueue || left > 0 || !state.recuttingPages.isEmpty
        return Button(title) {
            applyToAll(filter)
        }
        .disabled(off)
        .accessibilityIdentifier("viewer.applyToAll")
    }

    private func applyToAll(_ filter: CaptureFilter) {
        var ids: [UUID] = []
        for page in state.scannedPages {
            ids.append(page.id)
        }
        state.setPagesFilter(ids: ids, filter)
    }


    /// The filter shown as chosen: the one tapped while the page is cut again, else the page's own.
    private func chosenFilter(_ page: ScannedPage, working: Bool, edits: Bool) -> CaptureFilter? {
        let own: CaptureFilter? = edits ? PageRecut.editFilter(of: page) : PageRecut.filter(of: page)
        return (working ? requested[page.id] : nil) ?? own
    }

    private func filterButton(_ filter: CaptureFilter, page: ScannedPage, chosen: Bool) -> some View {
        Button {
            choose(filter, page: page)
        } label: {
            VStack(spacing: 4) {
                filterPicture(filter)
                    .frame(width: 60, height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(chosen ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: chosen ? 3 : 1))
                Text(filter.label)
                    .font(.caption)
                    .foregroundStyle(chosen ? Color.accentColor : Color.primary)
            }
            .frame(minWidth: 64, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.isBusy || state.readsQueue)
        .accessibilityLabel(Text(PageViewerText.filterName(filter)))
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .accessibilityIdentifier("filter.\(filter.rawValue)")
    }

    /// A camera's page is cut again with `filter`. A page with no capture facts gets it from the picture it had
    /// before its first edit, so one filter does not pile on another; Original takes the filter off.
    private func choose(_ filter: CaptureFilter, page: ScannedPage) {
        if PageRecut.canEdit(page) {
            guard filter != PageRecut.editFilter(of: page) else { return }
            requested[page.id] = filter
            state.filterPage(id: page.id, filter)
        } else {
            requested[page.id] = filter
            state.setPageFilter(id: page.id, filter)
        }
    }

    @ViewBuilder
    private func filterPicture(_ filter: CaptureFilter) -> some View {
        if let picture = previews[filter] {
            Image(decorative: picture, scale: 1)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(uiColor: .secondarySystemBackground))
                .overlay {
                    if loadingPreviews {
                        ProgressView()
                    } else {
                        Image(systemName: "photo")
                            .foregroundStyle(Color.secondary)
                    }
                }
        }
    }

    private func loadPreviews() async {
        guard let id = current?.id, !previewKey.isEmpty else { return }
        previews = [:]
        loadingPreviews = true
        let made: [CaptureFilter: CGImage] = await state.filterPreviews(id: id, maxSide: 160)
        guard !Task.isCancelled else { return }
        previews = made
        loadingPreviews = false
    }

    // MARK: Mark Up

    private func openMarkUp() {
        guard let page = current, !preparesCrop else { return }
        markUp = MarkUpRequest(id: page.id, image: pictureOf(page), marks: page.marks,
                               quarterTurns: page.rotationQuarterTurns, showsOriginal: page.showsOriginal)
    }

    /// Done keeps the strokes on the page; Cancel and a Done with nothing changed leave it as it is.
    private func finishMarkUp(_ request: MarkUpRequest, marks: PageMarks?) {
        markUp = nil
        if let marks {
            state.setMarks(marks, for: request.id)
        }
    }

    // MARK: Crop

    /// Crop cuts the page again and takes its marks off, so a marked page asks first.
    private func askCrop() {
        if current?.marks != nil {
            asksCropWithMarks = true
        } else {
            openCrop()
        }
    }

    private func openCrop() {
        guard let id = selection, !preparesCrop else { return }
        preparesCrop = true
        if let page = current, PageRecut.canEdit(page) {
            Task { @MainActor in
                let start: PageEditStart? = await state.pageEditStart(id: id)
                preparesCrop = false
                if let start {
                    rectCrop = RectCropRequest(id: id, image: start.image, start: start.rect, rotation: start.rotation)
                } else {
                    state.errorMessage = PageRecut.failedMessage
                }
            }
            return
        }
        let name: String = PageViewerText.pageName(number)
        Task { @MainActor in
            let request: IOSCropRequest? = await cropRequest(id: id, name: name)
            preparesCrop = false
            if let request {
                let cropped: ScannedPage? = state.scannedPages.first(where: { (page: ScannedPage) -> Bool in page.id == id })
                cropRotation = cropped?.rotationQuarterTurns ?? 0
                crop = request
            } else {
                state.errorMessage = PageRecut.failedMessage
            }
        }
    }

    /// The corner editor's request on the page's photo, read and turned off the main actor.
    private func cropRequest(id: UUID, name: String) async -> IOSCropRequest? {
        guard let start = await state.pageCropStart(id: id) else { return nil }
        let source: CGImage = start.source
        let pixels: RgbaImage? = await Task.detached(priority: .userInitiated) { () -> RgbaImage? in
            RgbaImage(cgImage: source)
        }.value
        guard let picture = pixels else { return nil }
        let plan = PhotoImportPlan(action: .review, corners: start.corners, reason: PhotoReviewReason.none,
                                   detection: PhotoDocumentDetection.nothing)
        // One "photo": the editor's counter then shows the page's name.
        let request = PhotoCornersRequest(photo: picture, plan: plan, fileName: name, number: 1, count: 1, kind: start.kind)
        return IOSCropRequest(photoID: id, request: request)
    }

    /// Crop cuts the page to the rectangle; Cancel changes nothing.
    private func finishRectCrop(_ request: RectCropRequest, rect: CGRect?) {
        rectCrop = nil
        if let rect {
            state.cropPage(id: request.id, to: rect, rotation: request.rotation)
        }
    }

    /// Use corners cuts the page again along them, Use whole photo along the whole photo; Cancel changes nothing.
    private func finishCrop(_ request: IOSCropRequest, answer: PhotoCornersAnswer) {
        crop = nil
        // The crop keeps the page's filter: an earlier tap is not the one to show while it runs.
        requested[request.photoID] = nil
        switch answer.choice {
        case .useCorners:
            if let corners = answer.corners {
                state.recropPage(id: request.photoID, corners: corners, rotation: cropRotation)
            }
        case .wholePhoto:
            let photo: RgbaImage = request.request.photo
            state.recropPage(id: request.photoID, corners: PhotoImport.wholePhoto(width: photo.width, height: photo.height),
                             rotation: cropRotation)
        case .skip:
            break
        }
    }
}

/// The page pictures with their marks drawn in (`PageMarkRenderer`), for the viewer to show: one for each page,
/// made again when the picture or the marks change.
final class MarkedPictures {
    private struct Entry {
        let base: CGImage
        let marks: PageMarks
        let turns: Int
        let picture: CGImage
    }

    private var entries: [UUID: Entry] = [:]

    /// Whether the marks of `page` are on the version of it that is shown.
    static func shows(_ page: ScannedPage) -> Bool {
        guard let marks = page.marks else { return false }
        return !marks.isEmpty && marks.onOriginal == page.showsOriginal
    }

    func picture(_ base: CGImage, of page: ScannedPage) -> CGImage {
        guard Self.shows(page), let marks = page.marks else {
            entries[page.id] = nil
            return base
        }
        if let entry = entries[page.id], entry.base === base, entry.marks == marks, entry.turns == page.rotationQuarterTurns {
            return entry.picture
        }
        let picture: CGImage = PageMarkRenderer.burned(base, marks: marks, quarterTurns: page.rotationQuarterTurns,
                                                       showsOriginal: page.showsOriginal)
        entries[page.id] = Entry(base: base, marks: marks, turns: page.rotationQuarterTurns, picture: picture)
        return picture
    }

    func keep(_ ids: Set<UUID>) {
        entries = entries.filter { (id: UUID, _: Entry) -> Bool in ids.contains(id) }
    }
}

/// A page fitted whole in the space it is given, zoomed with a pinch or a double tap (back with another), and
/// panned while zoomed; not zoomed, a swipe goes to the page viewer's next page. Where the device has Live Text,
/// its text can be selected and its links, numbers and codes tapped.
struct ZoomablePage: UIViewRepresentable {
    let image: CGImage
    let isShown: Bool
    /// Told the zoom while it changes under a pinch or a double tap, and once more, shown false, a second later.
    var onZoom: (Double, Bool) -> Void = { (_: Double, _: Bool) -> Void in }

    func makeCoordinator() -> LiveTextCoordinator {
        LiveTextCoordinator()
    }

    func makeUIView(context: Context) -> ZoomingImageView {
        let view: ZoomingImageView = ZoomingImageView()
        if IOSQuickScanModel.deviceSupportsLiveText() {
            view.imageView.isUserInteractionEnabled = true
            let interaction: ImageAnalysisInteraction = ImageAnalysisInteraction()
            interaction.preferredInteractionTypes = .automatic
            view.imageView.addInteraction(interaction)
            context.coordinator.interaction = interaction
        }
        return view
    }

    func updateUIView(_ view: ZoomingImageView, context: Context) {
        view.onZoom = onZoom
        view.show(image)
        if isShown {
            context.coordinator.analyzeIfNew(image)
        } else {
            context.coordinator.cancel()
        }
    }

    static func dismantleUIView(_ uiView: ZoomingImageView, coordinator: LiveTextCoordinator) {
        coordinator.cancel()
        // The viewer keeps the zoom per page; the page comes back at 1 when its view is made again.
        if uiView.zoomScale != 1 {
            DispatchQueue.main.async {
                uiView.onZoom(1, false)
            }
        }
    }
}

final class ZoomingImageView: UIScrollView, UIScrollViewDelegate {
    let imageView: UIImageView = UIImageView()
    private var shown: CGImage?
    /// The size the page was last fitted to.
    private var fittedSize: CGSize = .zero
    var onZoom: (Double, Bool) -> Void = { (_: Double, _: Bool) -> Void in }
    private var hideZoom: Task<Void, Never>?

    init() {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .white
        imageView.layer.shadowColor = UIColor.black.cgColor
        imageView.layer.shadowOpacity = 0.2
        imageView.layer.shadowRadius = 4
        imageView.layer.shadowOffset = CGSize(width: 0, height: 1)
        // The page read from its file is several times the screen; without mipmaps its print aliases until zoomed.
        imageView.layer.minificationFilter = .trilinear
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show(_ image: CGImage) {
        guard image !== shown else { return }
        // The page read sharper, or cut again with another filter, keeps its zoom; a page turned or cropped is fitted again.
        let kept: Bool = shown.map { (old: CGImage) -> Bool in
            PageViewer.sameShape(CGSize(width: old.width, height: old.height), CGSize(width: image.width, height: image.height))
        } ?? false
        shown = image
        imageView.image = UIImage(cgImage: image)
        guard !kept else { return }
        fittedSize = .zero
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != fittedSize {
            fit()
        }
        centre()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centre()
        // A zoom set in code (a page fitted again) says nothing.
        if isZooming || isZoomBouncing {
            hideZoom?.cancel()
            onZoom(Double(zoomScale), true)
        }
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        flashZoom(scale)
    }

    /// Reports `scale` as the zoom now, then, a second later, that the readout can go.
    private func flashZoom(_ scale: CGFloat) {
        hideZoom?.cancel()
        onZoom(Double(scale), true)
        hideZoom = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled, let view = self else { return }
            view.onZoom(Double(view.zoomScale), false)
        }
    }

    /// The page at zoom 1, as large as it fits.
    private func fit() {
        fittedSize = bounds.size
        guard let size = imageView.image?.size, size.width > 0, size.height > 0,
              bounds.width > 0, bounds.height > 0 else { return }
        if zoomScale != 1 {
            // The readout and the page's spoken zoom drop back to 1 once this layout pass is done.
            DispatchQueue.main.async { [weak self] in
                self?.onZoom(1, false)
            }
        }
        zoomScale = 1
        let scale: CGFloat = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        imageView.frame = CGRect(origin: .zero, size: fitted)
        contentSize = fitted
    }

    /// Keeps a page smaller than the view in its middle.
    private func centre() {
        let x: CGFloat = max((bounds.width - contentSize.width) / 2, 0)
        let y: CGFloat = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(top: y, left: x, bottom: y, right: x)
    }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        let animated: Bool = !UIAccessibility.isReduceMotionEnabled
        if zoomScale > minimumZoomScale {
            setZoomScale(minimumZoomScale, animated: animated)
            flashZoom(minimumZoomScale)
            return
        }
        let point: CGPoint = gesture.location(in: imageView)
        let scale: CGFloat = 2.5
        let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
        zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height),
             animated: animated)
        flashZoom(min(scale, maximumZoomScale))
    }
}

/// The text on a page of the viewer, read as Quick scan's Copy text reads its shot (`AppState.readText`) once
/// the page's edits under way have landed: selectable, with Copy (on this device only, as Copy text) and Share.
struct PageTextSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    let pageID: UUID
    /// The text read; nil while it is read.
    @State private var text: String?
    /// Why it could not be read.
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(PageViewerText.textTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            dismiss()
                        }
                        .accessibilityIdentifier("text.done")
                    }
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button(action: copy) {
                            Label(PageViewerText.copyLabel, systemImage: "doc.on.doc")
                        }
                        .disabled(found == nil)
                        .accessibilityIdentifier("text.copy")
                        Spacer()
                        ShareLink(item: found ?? "") {
                            Label(PageViewerText.shareLabel, systemImage: "square.and.arrow.up")
                        }
                        .disabled(found == nil)
                        .accessibilityIdentifier("text.share")
                    }
                }
        }
        .task {
            await read()
        }
    }

    private var found: String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    @ViewBuilder
    private var content: some View {
        if let problem {
            ContentUnavailableView(PageViewerText.textFailed, systemImage: "exclamationmark.triangle",
                                   description: Text(problem))
        } else if let found {
            ScrollView {
                Text(found)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .accessibilityIdentifier("text.body")
        } else if text != nil {
            ContentUnavailableView(PageViewerText.noText, systemImage: "text.magnifyingglass")
                .accessibilityIdentifier("text.none")
        } else {
            ProgressView(PageViewerText.readingText)
        }
    }

    private func read() async {
        guard text == nil, problem == nil else { return }
        await state.pageEditChain?.value
        if Task.isCancelled { return }
        guard let index = state.scannedPages.firstIndex(where: { (item: ScannedPage) -> Bool in item.id == pageID }) else {
            text = ""
            return
        }
        let page: ScannedPage = state.scannedPages[index]
        // Closing the sheet cancels its task and the read with it: one not begun yet never starts, and the
        // text of one under way is dropped.
        let reading: Task<String, Error> = Task.detached(priority: .userInitiated) { () throws -> String in
            try Task.checkCancellation()
            return try AppState.readText(page, number: index + 1)
        }
        do {
            text = try await withTaskCancellationHandler {
                try await reading.value
            } onCancel: {
                reading.cancel()
            }
        } catch is CancellationError {
            return
        } catch {
            // The Kit's message starts with the title: the description is the reason alone.
            let lead: String = L10n.bare(L10n.t("The text could not be read: {0}", ""))
            let message: String = L10n.bare(error.localizedDescription)
            problem = message.hasPrefix(lead) ? String(message.dropFirst(lead.count)) : message
        }
    }

    private func copy() {
        guard let found else { return }
        let item: [String: Any] = [UTType.utf8PlainText.identifier: found]
        UIPasteboard.general.setItems([item], options: [UIPasteboard.OptionsKey.localOnly: true])
    }
}
#endif
