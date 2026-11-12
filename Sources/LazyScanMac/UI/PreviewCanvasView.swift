#if os(macOS)
import AppKit
import LazyScanKit
import CoreGraphics
import SwiftUI

/// Central preview area: shows the overview / last scan, hosts the marquee selection
/// (only meaningful over an overview image, which maps 1:1 to the flatbed), and draws
/// informational outlines for detected photos. Once the queue has pages a bar above it switches
/// the canvas to one queued page, read from its spool file and shown as it will be saved.
struct PreviewCanvasView: View {
    @EnvironmentObject var state: AppState
    /// The language's direction, read outside the left-to-right wrap around the image.
    @Environment(\.layoutDirection) private var direction

    /// Downsampled copy of `state.canvasImage` actually handed to SwiftUI.
    @State private var displayImage: CGImage?
    /// In-flight marquee drag, captured on the first `onChanged`.
    @State private var dragState: CanvasDragState?
    /// The viewed page at the size the canvas draws it, and its true pixel size.
    @State private var pageImage: CGImage?
    @State private var pageSize: CGSize?
    @State private var pageLoading = false
    @State private var pageFailed = false
    /// The page `pageSize` and `pageFull` belong to.
    @State private var pageID: UUID?
    /// The page at its true size, drawn instead of `pageImage` once it is zoomed past that copy.
    @State private var pageFull: CGImage?
    @State private var zoom = PageZoom()
    @State private var viewport = CGSize.zero
    /// The zoom a drag or a pinch started from.
    @State private var panStart: PageZoom?
    @State private var magnifyStart: PageZoom?
    @FocusState private var canvasFocused: Bool
    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if !state.scannedPages.isEmpty {
                modeBar
                Divider()
            }
            canvas
        }
        .task(id: pageKey) { await loadPage() }
    }

    private var canvas: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            if state.viewsPage {
                pageLayer
            } else if let image = state.canvasImage {
                GeometryReader { geo in
                    let frame = fittedImageFrame(imageSize: CGSize(width: image.width, height: image.height),
                                                 in: canvasBounds(for: geo.size))
                    imageLayer(frame: frame)
                    if state.overviewImage != nil {
                        // A feeder scan ignores the selection: it is hidden then, not cleared.
                        if state.settings.source == .flatbed {
                            selectionLayer(frame: frame, viewSize: geo.size)
                        }
                    } else if !state.detectedPhotos.isEmpty {
                        detectedPhotosOverlay(image: image, frame: frame)
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
            } else {
                emptyState
            }
        }
        .clipped()
        // Live preview of the overview: re-render whenever it OR the adjustment settings
        // change, so slider edits are visible without a new preview. A scanned page is
        // shown as saved, adjustments already applied.
        .task(id: PreviewRenderKey(revision: state.canvasRevision,
                                   adjustments: state.settings.adjustments,
                                   colorMode: state.settings.colorMode)) {
            guard let base = state.canvasImage else {
                displayImage = nil
                return
            }
            // Coalesce slider drags: every tick re-keys this task, which cancels the
            // superseded one during this sleep — before its render ever starts.
            guard (try? await Task.sleep(nanoseconds: 80_000_000)) != nil else { return }
            let adjustments = state.settings.adjustments
            let colorMode = state.settings.colorMode
            let adjusts = state.overviewImage != nil
            let rendered = await Task.detached(priority: .userInitiated) {
                let down = canvasDownsample(base, maxDimension: 2600)
                return adjusts ? ImagePipeline.apply(adjustments, to: down, colorMode: colorMode) : down
            }.value
            // A newer settings change may have superseded this render.
            if !Task.isCancelled {
                displayImage = rendered
            }
        }
    }

    // MARK: Page view

    private var modeBar: some View {
        HStack(spacing: 10) {
            Picker("Canvas view", selection: showsPage) {
                Text("Preview").tag(false)
                Text("Page").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if state.viewsPage {
                stepButtons
            }
            Spacer()
            if let caption = pageCaption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if state.viewsPage {
                zoomControls
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(.bar)
    }

    /// The arrow keys' symbols: left goes back in a left-to-right language and forward in a right-to-left one.
    private var previousKey: String { direction == .rightToLeft ? "\u{2192}" : "\u{2190}" }
    private var nextKey: String { direction == .rightToLeft ? "\u{2190}" : "\u{2192}" }

    private var stepButtons: some View {
        HStack(spacing: 2) {
            Button { state.stepViewedPage(by: -1) } label: {
                Label("Previous Page", systemImage: "chevron.backward")
            }
            .disabled(!canStep(-1))
            .help(String(localized: "Previous page (\(previousKey))"))
            Button { state.stepViewedPage(by: 1) } label: {
                Label("Next Page", systemImage: "chevron.forward")
            }
            .disabled(!canStep(1))
            .help(String(localized: "Next page (\(nextKey))"))
        }
        .labelStyle(.iconOnly)
    }

    private func canStep(_ offset: Int) -> Bool {
        guard let viewed = state.viewedPage else { return false }
        return (1...state.scannedPages.count).contains(viewed.number + offset)
    }

    private var zoomControls: some View {
        let zoomOutOff = !(geometry?.canZoomOut(zoom) ?? false)
        let zoomInOff = !(geometry?.canZoomIn(zoom) ?? false)
        return HStack(spacing: 6) {
            Toggle(isOn: fitSelected) { Text("Fit") }
                .toggleStyle(.button)
                .disabled(geometry == nil)
                .help("Fit the page in the window (\u{2318}9)")
            Toggle(isOn: actualSizeSelected) { Text(1.0, format: .percent) }
                .toggleStyle(.button)
                .disabled(geometry == nil)
                .help("Show the page at actual size (\u{2318}0)")
            Button { zoomOut() } label: { Label("Zoom Out", systemImage: "minus.magnifyingglass") }
                .labelStyle(.iconOnly)
                .disabled(zoomOutOff)
                .help("Zoom out (\u{2318}\u{2212})")
            Button { zoomIn() } label: { Label("Zoom In", systemImage: "plus.magnifyingglass") }
                .labelStyle(.iconOnly)
                .disabled(zoomInOff)
                .help("Zoom in (\u{2318}+)")
            zoomReadout
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var zoomReadout: some View {
        if pageFailed {
            Text("Full size not available")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let geometry {
            Text(Double(geometry.percent(of: zoom)), format: .percent.precision(.fractionLength(0)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .trailing)
                .accessibilityLabel("Zoom")
        }
    }

    private var fitSelected: Binding<Bool> {
        Binding(get: { geometry?.isFit(zoom) ?? true }, set: { _ in setZoom(PageZoom()) })
    }

    private var actualSizeSelected: Binding<Bool> {
        Binding(get: { geometry?.isActualSize(zoom) ?? false }, set: { _ in actualSize() })
    }

    /// The viewed page's geometry once its size is known; nil while it loads or cannot be read.
    private var geometry: PageZoomGeometry? {
        guard let pixels = pageSize, !pageFailed, viewport.width > 0, viewport.height > 0 else { return nil }
        return PageZoomGeometry(pixels: pixels, viewport: viewport, displayScale: displayScale)
    }

    /// Buttons, menu items and a double-click ease to the new zoom unless Reduce Motion is on.
    private func setZoom(_ new: PageZoom) {
        if reduceMotion {
            zoom = new
        } else {
            withAnimation(.easeOut(duration: 0.15)) { zoom = new }
        }
    }

    private func actualSize() {
        guard let geometry else { return }
        setZoom(geometry.actualSize(zoom))
    }

    private func zoomIn() {
        guard let geometry else { return }
        setZoom(geometry.zoomedIn(zoom))
    }

    private func zoomOut() {
        guard let geometry else { return }
        setZoom(geometry.zoomedOut(zoom))
    }

    private var zoomActions: PageZoomActions {
        PageZoomActions(fit: { setZoom(PageZoom()) },
                        actualSize: { actualSize() },
                        zoomIn: { zoomIn() },
                        zoomOut: { zoomOut() })
    }

    /// A point of the canvas relative to its center, which the zoom keeps still.
    private func anchor(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - viewport.width / 2, y: point.y - viewport.height / 2)
    }

    private var showsPage: Binding<Bool> {
        Binding(get: { state.viewsPage },
                set: { if $0 { state.showPage() } else { state.showPreview() } })
    }

    /// "Page 3 of 8, 1654 by 2339 px" with the size once the page is read.
    private var pageCaption: String? {
        guard let viewed = state.viewedPage else { return nil }
        let total = state.scannedPages.count
        guard let size = pageSize else { return String(localized: "Page \(viewed.number) of \(total)") }
        return String(localized: "Page \(viewed.number) of \(total) \u{00B7} \(Int(size.width)) \u{00D7} \(Int(size.height)) px")
    }

    /// Everything the viewed picture depends on; nil while the canvas is on the preview.
    private var pageKey: PageViewKey? {
        guard let page = state.viewedPage?.page else { return nil }
        return PageViewKey(id: page.id, file: page.fileURL, turns: page.rotationQuarterTurns,
                           original: page.showsOriginal, undone: page.upright?.undone == true)
    }

    private var viewedSkipped: Bool {
        guard let viewed = state.viewedPage else { return false }
        let plan = DocumentSplitter.plan(state.scannedPages, options: state.settings.document)
        return plan.pages[viewed.number - 1].role != .content
    }

    private func loadPage() async {
        guard let viewed = state.viewedPage else {
            pageImage = nil
            pageFull = nil
            pageSize = nil
            pageID = nil
            zoom = PageZoom()
            pageLoading = false
            pageFailed = false
            return
        }
        let page = viewed.page
        let number = viewed.number
        // The same page read again (turned, or its original shown) keeps its zoom while the shape holds.
        if pageID != page.id {
            pageSize = nil
            pageFull = nil
            zoom = PageZoom()
        }
        pageLoading = true
        pageFailed = false
        let read: (image: CGImage, full: CGImage)? = await Task.detached(priority: .userInitiated) { () -> (image: CGImage, full: CGImage)? in
            guard let full = try? AppState.fullImage(of: page, number: number) else { return nil }
            return (canvasDownsample(full, maxDimension: 2600), full)
        }.value
        if Task.isCancelled { return }
        pageLoading = false
        guard let read else {
            pageImage = nil
            pageFull = nil
            pageSize = nil
            pageFailed = true
            return
        }
        let size = CGSize(width: read.full.width, height: read.full.height)
        if let old = pageSize, old != size { zoom = PageZoom() }
        pageID = page.id
        pageImage = read.image
        pageFull = read.full
        pageSize = size
    }

    private var pageLayer: some View {
        ZStack {
            GeometryReader { geo in
                if let image = pageImage, !pageFailed {
                    pageView(image, in: geo.size)
                }
            }
            if pageFailed {
                pageError
                    .environment(\.layoutDirection, direction)
            } else if pageLoading {
                pageSpinner
                    .environment(\.layoutDirection, direction)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .background(GeometryReader { geo in
            Color.clear.onChange(of: geo.size, initial: true) { _, size in viewport = size }
        })
        .background(PageScrollCatcher { delta, point, zooms in scrolled(by: delta, at: point, zooms: zooms) })
        .contentShape(Rectangle())
        .gesture(doubleClick)
        .onTapGesture { canvasFocused = true }
        .gesture(panGesture)
        .simultaneousGesture(magnifyGesture)
        .focusable()
        .focused($canvasFocused)
        .focusEffectDisabled()
        .onAppear { canvasFocused = true }
        .onChange(of: state.viewedPageID) { canvasFocused = true }
        // The arrows follow the strip: in a right-to-left language the left arrow goes to the next page.
        .onKeyPress(.leftArrow) { stepKey(direction == .rightToLeft ? 1 : -1) }
        .onKeyPress(.rightArrow) { stepKey(direction == .rightToLeft ? -1 : 1) }
        .onKeyPress(.escape) {
            state.showPreview()
            return .handled
        }
        .accessibilityAction(named: "Next Page") { state.stepViewedPage(by: 1) }
        .accessibilityAction(named: "Previous Page") { state.stepViewedPage(by: -1) }
        .help("Left and right arrow keys change page. Scroll to move around, pinch or Option-scroll to zoom, double-click to switch between Fit and 100%.")
        .focusedSceneValue(\.pageZoom, zoomActions)
    }

    /// The page at the zoom's scale, moved by its pan. Once it covers more screen pixels than the downsampled
    /// copy has, it is drawn from the full read. The shadow goes while zoomed, when the page is far larger
    /// than the canvas.
    private func pageView(_ image: CGImage, in size: CGSize) -> some View {
        let pixels = pageSize ?? CGSize(width: image.width, height: image.height)
        let geometry = PageZoomGeometry(pixels: pixels, viewport: size, displayScale: displayScale)
        let scale = geometry.scale(of: zoom)
        let pan = geometry.clampedPan(zoom.pan, scale: scale)
        let shown = max(pixels.width, pixels.height) * scale * displayScale
        let source = shown > CGFloat(max(image.width, image.height)) ? (pageFull ?? image) : image
        let shadow: CGFloat = zoom.scale == nil ? 10 : 0
        return Image(source, scale: 1, label: Text(pageLabel))
            .resizable()
            .interpolation(.high)
            .frame(width: pixels.width * scale, height: pixels.height * scale)
            .overlay(alignment: .topLeading) { skippedPill }
            .overlay(Rectangle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: shadow, y: shadow / 2.5)
            .position(x: size.width / 2 + pan.width, y: size.height / 2 + pan.height)
            .accessibilityValue(Text(Double(geometry.percent(of: zoom)), format: .percent.precision(.fractionLength(0))))
    }

    private func stepKey(_ offset: Int) -> KeyPress.Result {
        state.stepViewedPage(by: offset)
        return .handled
    }

    private var doubleClick: some Gesture {
        SpatialTapGesture(count: 2).onEnded { value in
            guard let geometry else { return }
            setZoom(geometry.toggled(zoom, about: anchor(value.location)))
        }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                guard let geometry, zoom.scale != nil else { return }
                let start = panStart ?? zoom
                panStart = start
                zoom = geometry.panned(start, by: value.translation)
            }
            .onEnded { _ in panStart = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard let geometry else { return }
                let start = magnifyStart ?? zoom
                magnifyStart = start
                zoom = geometry.zoomed(start, to: geometry.scale(of: start) * value.magnification,
                                       about: anchor(value.startLocation))
            }
            .onEnded { _ in magnifyStart = nil }
    }

    /// Scrolling pans a zoomed page; with Option held it zooms around the pointer.
    private func scrolled(by delta: CGSize, at point: CGPoint, zooms: Bool) {
        guard let geometry else { return }
        if zooms {
            zoom = geometry.zoomed(zoom, to: geometry.scale(of: zoom) * exp(delta.height * 0.01),
                                   about: anchor(point))
        } else {
            zoom = geometry.panned(zoom, by: delta)
        }
    }

    private var pageLabel: String {
        guard let viewed = state.viewedPage else { return "" }
        let label = String(localized: "Page \(viewed.number) of \(state.scannedPages.count), as it will be saved")
        return viewedSkipped ? label + String(localized: ", skipped") : label
    }

    @ViewBuilder
    private var skippedPill: some View {
        if viewedSkipped {
            Text("Skipped")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.regularMaterial, in: Capsule())
                .padding(8)
        }
    }

    private var pageSpinner: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.large)
            Text("Loading page \(state.viewedPage?.number ?? 0)")
                .font(.callout)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }

    private var pageError: some View {
        VStack(spacing: 10) {
            Text("Page \(state.viewedPage?.number ?? 0) can't be opened")
                .font(.headline)
            Text("Its saved scan is missing or unreadable. Scan the page again.")
                .foregroundStyle(.secondary)
            Button("Show Preview") { state.showPreview() }
        }
        .multilineTextAlignment(.center)
        .padding(30)
        .frame(maxWidth: 480)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "scanner")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.secondary)
            if let line = startLine {
                Text(line)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            if demoSelected {
                Text("This is the demo scanner: it scans sample pages. Your own scanner appears in the sidebar once it is found.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(40)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// What to do first; none while the task banner above already says it.
    private var startLine: String? {
        if state.activeTaskDefinition != nil || state.isTurningOverByHand { return nil }
        let action: String = state.primaryActionLabel
        if state.previewUnavailableReason == nil {
            return String(localized: "Click Preview below to see the flatbed, or \(action) to go straight ahead")
        }
        if state.settings.source == .documentFeeder {
            return String(localized: "Load the pages in the feeder and click \(action) below")
        }
        return String(localized: "Click \(action) below to start")
    }

    private var demoSelected: Bool {
        let selected: ScannerInfo? = state.devices.first(where: { $0.id == state.selectedDeviceID })
        return selected?.isDemo == true
    }

    // MARK: Image

    private func imageLayer(frame: CGRect) -> some View {
        Group {
            if let displayImage {
                Image(decorative: displayImage, scale: 1)
                    .resizable()
                    .interpolation(.high)
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .overlay(Rectangle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        .position(x: frame.midX, y: frame.midY)
    }

    // MARK: Selection (overview only)

    private func selectionLayer(frame: CGRect, viewSize: CGSize) -> some View {
        ZStack {
            if let sel = state.selectionRect {
                let rect = viewRect(forNormalized: sel, in: frame)
                dimmedExterior(around: rect, viewSize: viewSize)
                Rectangle()
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                    .position(x: rect.midX, y: rect.midY)
                    .allowsHitTesting(false)
                selectionHandles(rect: rect)
                sizeChip(selection: sel, rect: rect, viewSize: viewSize)
                clearChip
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { state.selectionRect = nil }
        .gesture(selectionDrag(frame: frame))
    }

    /// Four rects dimming everything outside the selection.
    private func dimmedExterior(around rect: CGRect, viewSize: CGSize) -> some View {
        Path { p in
            let full = CGRect(origin: .zero, size: viewSize)
            p.addRect(CGRect(x: 0, y: 0, width: full.width, height: max(0, rect.minY)))                                // top
            p.addRect(CGRect(x: 0, y: rect.maxY, width: full.width, height: max(0, full.height - rect.maxY)))          // bottom
            p.addRect(CGRect(x: 0, y: rect.minY, width: max(0, rect.minX), height: rect.height))                       // left
            p.addRect(CGRect(x: rect.maxX, y: rect.minY, width: max(0, full.width - rect.maxX), height: rect.height))  // right
        }
        .fill(Color.black.opacity(0.35))
        .allowsHitTesting(false)
    }

    private func selectionHandles(rect: CGRect) -> some View {
        ForEach(SelectionHandle.allCases, id: \.self) { handle in
            Rectangle()
                .fill(Color.accentColor)
                .overlay(Rectangle().strokeBorder(Color.white, lineWidth: 1))
                .frame(width: 7, height: 7)
                .position(handle.point(in: rect))
                .allowsHitTesting(false)
        }
    }

    private func sizeChip(selection: CGRect, rect: CGRect, viewSize: CGSize) -> some View {
        Group {
            if let caps = state.capabilities {
                let width = Double(selection.width * caps.flatbedSizeInches.width)
                    .formatted(.number.precision(.fractionLength(1)))
                let height = Double(selection.height * caps.flatbedSizeInches.height)
                    .formatted(.number.precision(.fractionLength(1)))
                Text("\(width) × \(height) in")
                    .environment(\.layoutDirection, direction)
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: Capsule())
                    .position(x: min(max(rect.midX, 50), max(50, viewSize.width - 50)),
                              y: min(rect.maxY + 16, max(12, viewSize.height - 14)))
                    .allowsHitTesting(false)
            }
        }
    }

    private var clearChip: some View {
        Button {
            state.selectionRect = nil
        } label: {
            Label("Clear selection", systemImage: "xmark.circle.fill")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Remove the scan area selection (or double-click the preview)")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(10)
        .environment(\.layoutDirection, direction)
    }

    private func selectionDrag(frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragState == nil {
                    dragState = beginDrag(at: value.startLocation, frame: frame)
                }
                if let dragState {
                    state.selectionRect = updatedSelection(dragState, value: value, frame: frame)
                }
            }
            .onEnded { value in
                if let ds = dragState {
                    var rect = updatedSelection(ds, value: value, frame: frame)
                    if case .creating = ds.mode, let r = rect, r.width < 0.01 || r.height < 0.01 {
                        rect = nil // Degenerate drag: treat as no selection.
                    }
                    state.selectionRect = rect
                }
                dragState = nil
            }
    }

    private func beginDrag(at start: CGPoint, frame: CGRect) -> CanvasDragState {
        if let sel = state.selectionRect {
            let rect = viewRect(forNormalized: sel, in: frame)
            for handle in SelectionHandle.allCases {
                let p = handle.point(in: rect)
                if hypot(p.x - start.x, p.y - start.y) <= 10 {
                    return CanvasDragState(mode: .resizing(handle: handle, original: sel))
                }
            }
            if rect.contains(start) {
                return CanvasDragState(mode: .moving(original: sel))
            }
        }
        return CanvasDragState(mode: .creating)
    }

    private func updatedSelection(_ ds: CanvasDragState, value: DragGesture.Value, frame: CGRect) -> CGRect? {
        guard frame.width > 0, frame.height > 0 else { return state.selectionRect }
        let dx = (value.location.x - value.startLocation.x) / frame.width
        let dy = (value.location.y - value.startLocation.y) / frame.height

        switch ds.mode {
        case .creating:
            let a = normalizedPoint(value.startLocation, in: frame)
            let b = normalizedPoint(value.location, in: frame)
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                          width: abs(a.x - b.x), height: abs(a.y - b.y))

        case .moving(let orig):
            let x = clampUnit(orig.minX + dx, 0, max(0, 1 - orig.width))
            let y = clampUnit(orig.minY + dy, 0, max(0, 1 - orig.height))
            return CGRect(x: x, y: y, width: min(orig.width, 1), height: min(orig.height, 1))

        case .resizing(let handle, let orig):
            let minSide: CGFloat = 0.04
            var minX = orig.minX, maxX = orig.maxX, minY = orig.minY, maxY = orig.maxY
            if handle.movesLeft { minX = clampUnit(orig.minX + dx, 0, max(0, maxX - minSide)) }
            if handle.movesRight { maxX = clampUnit(orig.maxX + dx, min(1, minX + minSide), 1) }
            if handle.movesTop { minY = clampUnit(orig.minY + dy, 0, max(0, maxY - minSide)) }
            if handle.movesBottom { maxY = clampUnit(orig.maxY + dy, min(1, minY + minSide), 1) }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    // MARK: Detected photo outlines (informational, scan image only)

    private func detectedPhotosOverlay(image: CGImage, frame: CGRect) -> some View {
        // Regions are in FULL-resolution pixel coordinates, but the canvas holds only a
        // downsampled preview — map through the recorded true pixel size.
        let pixelSize = state.lastScanPixelSize
            ?? CGSize(width: max(image.width, 1), height: max(image.height, 1))
        let sx = frame.width / pixelSize.width
        let sy = frame.height / pixelSize.height
        return ForEach(Array(state.detectedPhotos.enumerated()), id: \.element.id) { index, photo in
            let pts = photo.region.corners.map {
                CGPoint(x: frame.minX + $0.x * sx, y: frame.minY + $0.y * sy)
            }
            let center = CGPoint(x: frame.minX + photo.region.center.x * sx,
                                 y: frame.minY + photo.region.center.y * sy)
            ZStack {
                Path { p in
                    guard pts.count == 4 else { return }
                    p.move(to: pts[0])
                    p.addLine(to: pts[1])
                    p.addLine(to: pts[2])
                    p.addLine(to: pts[3])
                    p.closeSubpath()
                }
                .stroke(Color.accentColor, lineWidth: 1.5)
                Text("\(index + 1)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Circle().fill(Color.accentColor))
                    .position(center)
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - File-private render key

/// What the viewed page's picture is read from and turned by; a new value reads it again.
fileprivate struct PageViewKey: Hashable {
    var id: UUID
    var file: URL?
    var turns: Int
    var original: Bool
    var undone: Bool
}

/// Identity of one live-preview render: the canvas image revision plus everything the
/// pipeline consumes. `.task(id:)` keyed on this re-renders exactly when needed.
fileprivate struct PreviewRenderKey: Equatable {
    var revision: Int
    var adjustments: AdjustmentSettings
    var colorMode: ColorMode
}

// MARK: - File-private geometry helpers

/// The in-flight marquee interaction, decided from where the drag started.
fileprivate struct CanvasDragState {
    enum Mode {
        case creating
        case moving(original: CGRect)
        case resizing(handle: SelectionHandle, original: CGRect)
    }
    var mode: Mode
}

/// The 8 square resize handles of the marquee, addressed by their unit position on the rect.
fileprivate enum SelectionHandle: CaseIterable, Hashable {
    case topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight

    var unit: CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: 0, y: 0)
        case .top: return CGPoint(x: 0.5, y: 0)
        case .topRight: return CGPoint(x: 1, y: 0)
        case .left: return CGPoint(x: 0, y: 0.5)
        case .right: return CGPoint(x: 1, y: 0.5)
        case .bottomLeft: return CGPoint(x: 0, y: 1)
        case .bottom: return CGPoint(x: 0.5, y: 1)
        case .bottomRight: return CGPoint(x: 1, y: 1)
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + unit.x * rect.width, y: rect.minY + unit.y * rect.height)
    }

    var movesLeft: Bool { unit.x == 0 }
    var movesRight: Bool { unit.x == 1 }
    var movesTop: Bool { unit.y == 0 }
    var movesBottom: Bool { unit.y == 1 }
}

/// Bounds the image is fitted into: the canvas with a comfortable margin.
func canvasBounds(for size: CGSize) -> CGRect {
    let inset = CGRect(origin: .zero, size: size).insetBy(dx: 24, dy: 24)
    return (inset.isNull || inset.isEmpty) ? CGRect(origin: .zero, size: size) : inset
}

/// Aspect-fit frame (view coordinates) for an image of `imageSize` centered in `bounds`.
/// All selection math is done relative to this rect.
fileprivate func fittedImageFrame(imageSize: CGSize, in bounds: CGRect) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
        return bounds
    }
    let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
    let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                  width: size.width, height: size.height)
}

/// Normalized (0...1, top-left origin) selection rect -> view coordinates.
fileprivate func viewRect(forNormalized r: CGRect, in frame: CGRect) -> CGRect {
    CGRect(x: frame.minX + r.minX * frame.width,
           y: frame.minY + r.minY * frame.height,
           width: r.width * frame.width,
           height: r.height * frame.height)
}

/// View-coordinate point -> normalized (clamped 0...1) point relative to the fitted frame.
fileprivate func normalizedPoint(_ p: CGPoint, in frame: CGRect) -> CGPoint {
    CGPoint(x: clampUnit((p.x - frame.minX) / frame.width, 0, 1),
            y: clampUnit((p.y - frame.minY) / frame.height, 0, 1))
}

fileprivate func clampUnit(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
    min(max(v, lo), hi)
}

/// Downsample the (possibly huge) scan for on-screen display.
fileprivate func canvasDownsample(_ image: CGImage, maxDimension: CGFloat) -> CGImage {
    let w = CGFloat(image.width), h = CGFloat(image.height)
    let scale = maxDimension / max(w, h)
    guard scale < 1 else { return image }
    let tw = max(1, Int(w * scale)), th = max(1, Int(h * scale))
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return image }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: tw, height: th))
    return ctx.makeImage() ?? image
}
#endif
