#if os(iOS)
import LazyScanKit
import CoreGraphics
import SwiftUI

/// What the rectangle crop shows and does, without a screen: the page fitted into the view, the rectangle kept
/// as fractions of the page (from the top left) and the eight handles that move its corners and edges. A handle
/// moves by how far the finger moves, so it is never hidden under the finger; the rectangle stays on the page
/// and is never smaller than `minimum` of either side.
struct RectCropModel: Equatable {
    enum Handle: Int, CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight, top, bottom, left, right

        /// The suffix of the handle's accessibility identifier.
        var name: String {
            switch self {
            case .topLeft: return "topLeft"
            case .topRight: return "topRight"
            case .bottomLeft: return "bottomLeft"
            case .bottomRight: return "bottomRight"
            case .top: return "top"
            case .bottom: return "bottom"
            case .left: return "left"
            case .right: return "right"
            }
        }

        var label: String {
            switch self {
            case .topLeft: return String(localized: "Crop handle, top left")
            case .topRight: return String(localized: "Crop handle, top right")
            case .bottomLeft: return String(localized: "Crop handle, bottom left")
            case .bottomRight: return String(localized: "Crop handle, bottom right")
            case .top: return String(localized: "Crop handle, top edge")
            case .bottom: return String(localized: "Crop handle, bottom edge")
            case .left: return String(localized: "Crop handle, left edge")
            case .right: return String(localized: "Crop handle, right edge")
            }
        }

        fileprivate var movesLeft: Bool { self == .topLeft || self == .bottomLeft || self == .left }
        fileprivate var movesRight: Bool { self == .topRight || self == .bottomRight || self == .right }
        fileprivate var movesTop: Bool { self == .topLeft || self == .topRight || self == .top }
        fileprivate var movesBottom: Bool { self == .bottomLeft || self == .bottomRight || self == .bottom }
    }

    /// The smallest the rectangle can be, as a fraction of the page's width and of its height.
    static let minimum: CGFloat = 0.1
    /// How far from a handle's center a touch still takes it (points).
    static let handleHitRadius: CGFloat = 36
    /// The margin around the fitted page (points), so a handle on the page's edge can be reached.
    static let inset: CGFloat = 24
    static let whole = CGRect(x: 0, y: 0, width: 1, height: 1)

    let pageWidth: Int
    let pageHeight: Int
    /// The rectangle the crop opened with: the part kept by an earlier crop, or all of the page.
    let start: CGRect
    private(set) var rect: CGRect
    /// The handle the keyboard moves and the last one touched.
    private(set) var selected: Handle = .topLeft
    /// The handle a finger is moving, if any.
    private(set) var dragging: Handle?
    private var dragStart: CGRect
    private var dragOrigin: CGPoint = .zero

    init(pageWidth: Int, pageHeight: Int, start: CGRect = RectCropModel.whole) {
        self.pageWidth = max(pageWidth, 1)
        self.pageHeight = max(pageHeight, 1)
        self.start = start
        self.rect = start
        self.dragStart = start
    }

    /// Whether the rectangle is all of the page.
    var isWhole: Bool { rect == Self.whole }

    /// Whether the rectangle is not the one the crop opened with, so Crop has something to do.
    var isChanged: Bool { rect != start }

    mutating func reset() {
        rect = Self.whole
    }

    // MARK: Layout

    /// Where the page sits in a view of `size`: as large as fits inside the margin, centered.
    func fittedFrame(in size: CGSize) -> CGRect {
        let availableWidth: CGFloat = max(size.width - Self.inset * 2, 1)
        let availableHeight: CGFloat = max(size.height - Self.inset * 2, 1)
        let scale: CGFloat = min(availableWidth / CGFloat(pageWidth), availableHeight / CGFloat(pageHeight))
        let width: CGFloat = CGFloat(pageWidth) * scale
        let height: CGFloat = CGFloat(pageHeight) * scale
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    /// The rectangle in the view, given where the page sits.
    func viewRect(frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + rect.minX * frame.width, y: frame.minY + rect.minY * frame.height,
               width: rect.width * frame.width, height: rect.height * frame.height)
    }

    /// Where `handle` sits in the view: a corner of the rectangle, or the middle of an edge.
    func point(of handle: Handle, frame: CGRect) -> CGPoint {
        let box: CGRect = viewRect(frame: frame)
        let x: CGFloat = handle.movesLeft ? box.minX : (handle.movesRight ? box.maxX : box.midX)
        let y: CGFloat = handle.movesTop ? box.minY : (handle.movesBottom ? box.maxY : box.midY)
        return CGPoint(x: x, y: y)
    }

    // MARK: Moving

    /// Takes the handle nearest to `point` (within `handleHitRadius`, corners before edges when two are as near);
    /// false when none is near enough, and nothing moves then.
    mutating func beginDrag(at point: CGPoint, frame: CGRect) -> Bool {
        var best: Handle?
        var bestDistance: CGFloat = .infinity
        for handle in Handle.allCases {
            let at: CGPoint = self.point(of: handle, frame: frame)
            let distance: CGFloat = hypot(at.x - point.x, at.y - point.y)
            if distance < bestDistance {
                best = handle
                bestDistance = distance
            }
        }
        guard let best, bestDistance <= Self.handleHitRadius else { return false }
        dragging = best
        selected = best
        dragStart = rect
        dragOrigin = point
        return true
    }

    /// Moves the handle being dragged by how far the finger has gone from where it came down.
    mutating func drag(to point: CGPoint, frame: CGRect) {
        guard let dragging, frame.width > 0, frame.height > 0 else { return }
        rect = Self.moved(dragStart, handle: dragging, dx: (point.x - dragOrigin.x) / frame.width,
                          dy: (point.y - dragOrigin.y) / frame.height)
    }

    mutating func endDrag() {
        dragging = nil
    }

    /// `handle` moved by `dx` and `dy` (fractions of the page) from where it is now.
    mutating func nudge(_ handle: Handle, dx: CGFloat, dy: CGFloat) {
        selected = handle
        rect = Self.moved(rect, handle: handle, dx: dx, dy: dy)
    }

    /// The keyboard's next handle, in the order of `Handle.allCases`, wrapping round.
    mutating func selectNext() {
        let all: [Handle] = Handle.allCases
        selected = all[(selected.rawValue + 1) % all.count]
    }

    /// `rect` with the sides `handle` holds moved by `dx` and `dy`, kept on the page and `minimum` wide and high.
    static func moved(_ rect: CGRect, handle: Handle, dx: CGFloat, dy: CGFloat) -> CGRect {
        var left: CGFloat = rect.minX
        var right: CGFloat = rect.maxX
        var top: CGFloat = rect.minY
        var bottom: CGFloat = rect.maxY
        if handle.movesLeft { left = min(max(left + dx, 0), right - minimum) }
        if handle.movesRight { right = max(min(right + dx, 1), left + minimum) }
        if handle.movesTop { top = min(max(top + dy, 0), bottom - minimum) }
        if handle.movesBottom { bottom = max(min(bottom + dy, 1), top + minimum) }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    // MARK: VoiceOver

    /// "12 percent from the left, 8 percent from the top": where `handle` is on the page.
    func value(of handle: Handle) -> String {
        let x: CGFloat = handle.movesLeft ? rect.minX : (handle.movesRight ? rect.maxX : rect.midX)
        let y: CGFloat = handle.movesTop ? rect.minY : (handle.movesBottom ? rect.maxY : rect.midY)
        let left: Int = Int((x * 100).rounded())
        let top: Int = Int((y * 100).rounded())
        return String(localized: "\(left) percent from the left, \(top) percent from the top")
    }

    /// "Crop area, 80 percent of the page wide, 90 percent high"
    var areaName: String {
        let wide: Int = Int((rect.width * 100).rounded())
        let high: Int = Int((rect.height * 100).rounded())
        return String(localized: "Crop area, \(wide) percent of the page wide, \(high) percent high")
    }
}

/// The page to cut, and the rotation it was shown at, so the crop is refused once the page was turned since.
struct RectCropRequest: Identifiable {
    let id: UUID
    let image: CGImage
    /// The part of the picture kept so far, as fractions from the top left.
    let start: CGRect
    let rotation: Int
}

/// The rectangle crop on the iPhone and iPad, for a page that has no corners to place (a scanner's page, an
/// imported PDF's, a whole spread): the page as shown with a rectangle on it, dragged by eight handles, the
/// outside dimmed. Crop answers with the rectangle as fractions of the page, Cancel with nil. What it does is
/// `RectCropModel`; this view draws it. A keyboard moves the handle picked with Tab by arrow keys, one percent
/// a press and five with Shift.
struct RectCropView: View {
    let image: CGImage
    let onAnswer: @MainActor (CGRect?) -> Void

    @State private var model: RectCropModel
    @FocusState private var focused: Bool

    init(image: CGImage, start: CGRect, onAnswer: @escaping @MainActor (CGRect?) -> Void) {
        self.image = image
        self.onAnswer = onAnswer
        _model = State(initialValue: RectCropModel(pageWidth: image.width, pageHeight: image.height, start: start))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("Drag the edges to keep only the part you want.")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                GeometryReader { (geometry: GeometryProxy) in
                    stage(size: geometry.size)
                }
                .environment(\.layoutDirection, .leftToRight)
                footer
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(PageViewerText.cropLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(PageViewerText.cancelLabel) {
                        onAnswer(nil)
                    }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("crop.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(PageViewerText.cropLabel) {
                        onAnswer(model.rect)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.isChanged)
                    .accessibilityIdentifier("crop.use")
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Reset") {
                model.reset()
            }
            .disabled(model.isWhole)
            .accessibilityHint(Text("Back to the whole page"))
            .accessibilityIdentifier("crop.reset")
            Spacer(minLength: 0)
        }
        .buttonStyle(.bordered)
        .padding(16)
    }

    private func stage(size: CGSize) -> some View {
        let frame: CGRect = model.fittedFrame(in: size)
        let box: CGRect = model.viewRect(frame: frame)
        let points: [CGPoint] = RectCropModel.Handle.allCases.map { (handle: RectCropModel.Handle) -> CGPoint in
            model.point(of: handle, frame: frame)
        }
        return ZStack {
            Color.black.opacity(0.85)
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
            RectCropOutline(frame: frame, box: box, points: points, moving: model.dragging != nil)
            ForEach(RectCropModel.Handle.allCases, id: \.self) { (handle: RectCropModel.Handle) in
                handleElement(handle, at: points[handle.rawValue])
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(handleDrag(frame: frame))
        .focusable()
        .focused($focused)
        .onKeyPress { (press: KeyPress) -> KeyPress.Result in
            keyPressed(press)
        }
        .onAppear {
            focused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(model.areaName))
        .accessibilityIdentifier("crop.stage")
    }

    private func handleDrag(frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { (value: DragGesture.Value) in
                if model.dragging == nil {
                    // A finger that came down away from every handle moves nothing.
                    if !model.beginDrag(at: value.startLocation, frame: frame) { return }
                }
                model.drag(to: value.location, frame: frame)
            }
            .onEnded { (_: DragGesture.Value) in
                model.endDrag()
            }
    }

    /// A handle for VoiceOver: its place in the label, where it is in the value, and a step in each direction.
    private func handleElement(_ handle: RectCropModel.Handle, at point: CGPoint) -> some View {
        Color.clear
            .frame(width: 44, height: 44)
            .position(point)
            .allowsHitTesting(false)
            .accessibilityElement()
            .accessibilityLabel(Text(handle.label))
            .accessibilityValue(Text(model.value(of: handle)))
            .accessibilityAction(named: Text("Move up")) {
                model.nudge(handle, dx: 0, dy: -0.02)
            }
            .accessibilityAction(named: Text("Move down")) {
                model.nudge(handle, dx: 0, dy: 0.02)
            }
            .accessibilityAction(named: Text("Move left")) {
                model.nudge(handle, dx: -0.02, dy: 0)
            }
            .accessibilityAction(named: Text("Move right")) {
                model.nudge(handle, dx: 0.02, dy: 0)
            }
            .accessibilityIdentifier("crop.handle.\(handle.name)")
    }

    private func keyPressed(_ press: KeyPress) -> KeyPress.Result {
        let step: CGFloat = press.modifiers.contains(EventModifiers.shift) ? 0.05 : 0.01
        let handle: RectCropModel.Handle = model.selected
        switch press.key {
        case KeyEquivalent.tab:
            model.selectNext()
        case KeyEquivalent.leftArrow:
            model.nudge(handle, dx: -step, dy: 0)
        case KeyEquivalent.rightArrow:
            model.nudge(handle, dx: step, dy: 0)
        case KeyEquivalent.upArrow:
            model.nudge(handle, dx: 0, dy: -step)
        case KeyEquivalent.downArrow:
            model.nudge(handle, dx: 0, dy: step)
        default:
            return KeyPress.Result.ignored
        }
        return KeyPress.Result.handled
    }
}

/// The page outside the rectangle dimmed, the rectangle's outline, and a grid of thirds while it is moved.
private struct RectCropOutline: View {
    let frame: CGRect
    let box: CGRect
    /// The handles' places, in the order of `RectCropModel.Handle.allCases`.
    let points: [CGPoint]
    let moving: Bool

    var body: some View {
        ZStack {
            Path { (path: inout Path) in
                path.addRect(frame)
                path.addRect(box)
            }
            .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
            if moving {
                Path { (path: inout Path) in
                    for part in [CGFloat(1) / 3, CGFloat(2) / 3] {
                        path.move(to: CGPoint(x: box.minX + box.width * part, y: box.minY))
                        path.addLine(to: CGPoint(x: box.minX + box.width * part, y: box.maxY))
                        path.move(to: CGPoint(x: box.minX, y: box.minY + box.height * part))
                        path.addLine(to: CGPoint(x: box.maxX, y: box.minY + box.height * part))
                    }
                }
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
            }
            Path { (path: inout Path) in
                path.addRect(box)
            }
            .stroke(Color.white, lineWidth: 2)
            ForEach(0..<points.count, id: \.self) { (index: Int) in
                Circle()
                    .fill(Color.accentColor.opacity(0.35))
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                    .frame(width: 20, height: 20)
                    .position(points[index])
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
