#if os(iOS)
import LazyScanKit
import CoreGraphics
import SwiftUI

/// What Mark Up shows and does, without a screen: the page fitted into the view, the strokes being drawn on
/// it, and the tool and color picked. A stroke is kept as points of the page picture before any turn
/// (`MarkPoint`), so it follows the page when that is turned, and the strokes drawn on an earlier visit are
/// still here to undo. The working strokes are the page's marks on the version of the page shown; marks left
/// on the other version are replaced once a stroke is drawn.
struct MarkUpModel: Equatable {
    static let penInks: [MarkInk] = [.black, .blue, .red, .green]
    static let highlighterInks: [MarkInk] = [.yellow, .green, .pink, .orange]
    /// The margin around the fitted page (points).
    static let inset: CGFloat = 12

    let quarterTurns: Int
    private let pageSize: CGSize
    private let start: PageMarks
    private(set) var marks: PageMarks
    private(set) var tool: MarkTool = .pen
    private(set) var colorIndex: Int = 0
    private(set) var drawing: Bool = false

    /// `pageSize` is the picture as shown, already turned by `quarterTurns`.
    init(marks: PageMarks?, showsOriginal: Bool, quarterTurns: Int, pageSize: CGSize) {
        let kept: PageMarks = marks.flatMap { (own: PageMarks) -> PageMarks? in
            own.onOriginal == showsOriginal ? own : nil
        } ?? PageMarks(onOriginal: showsOriginal)
        self.quarterTurns = quarterTurns
        self.pageSize = pageSize
        self.start = kept
        self.marks = kept
    }

    var inks: [MarkInk] { tool == .pen ? Self.penInks : Self.highlighterInks }

    var ink: MarkInk { inks[colorIndex] }

    var canUndo: Bool { !marks.isEmpty }

    /// Whether the strokes are not the ones the screen opened with, so Done has something to keep.
    var isChanged: Bool { marks != start }

    mutating func select(_ tool: MarkTool) {
        self.tool = tool
    }

    mutating func pick(color index: Int) {
        colorIndex = min(max(index, 0), inks.count - 1)
    }

    mutating func undo() {
        marks.removeLast()
    }

    /// Where the page sits in a view of `size`: as large as fits inside the margin, centered.
    func fittedFrame(in size: CGSize) -> CGRect {
        let availableWidth: CGFloat = max(size.width - Self.inset * 2, 1)
        let availableHeight: CGFloat = max(size.height - Self.inset * 2, 1)
        let scale: CGFloat = min(availableWidth / max(pageSize.width, 1), availableHeight / max(pageSize.height, 1))
        let width: CGFloat = pageSize.width * scale
        let height: CGFloat = pageSize.height * scale
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    /// Starts a stroke where a finger came down; false, and nothing drawn, when that is off the page.
    mutating func begin(at location: CGPoint, frame: CGRect) -> Bool {
        guard frame.width > 0, frame.height > 0, frame.contains(location) else { return false }
        marks.begin(tool: tool, ink: ink, at: markPoint(location, frame: frame))
        drawing = true
        return true
    }

    mutating func extend(to location: CGPoint, frame: CGRect) {
        guard drawing, frame.width > 0, frame.height > 0 else { return }
        marks.extend(markPoint(location, frame: frame))
    }

    mutating func end() {
        drawing = false
    }

    /// The point of the page picture before any turn that shows at `location`; a touch past the page's edge
    /// lands on the edge.
    private func markPoint(_ location: CGPoint, frame: CGRect) -> MarkPoint {
        let x: Double = Double(min(max((location.x - frame.minX) / frame.width, 0), 1))
        let y: Double = Double(min(max((location.y - frame.minY) / frame.height, 0), 1))
        return MarkPoint(x: x, y: y).unturned(quarterTurns: quarterTurns)
    }

    /// Where a point of the page picture before any turn sits in the view.
    static func viewPoint(_ point: MarkPoint, quarterTurns: Int, frame: CGRect) -> CGPoint {
        let turned: MarkPoint = point.turned(quarterTurns: quarterTurns)
        return CGPoint(x: frame.minX + CGFloat(turned.x) * frame.width, y: frame.minY + CGFloat(turned.y) * frame.height)
    }

    /// The color of a stroke's ink.
    static func color(_ ink: MarkInk) -> Color {
        let rgb: (red: Double, green: Double, blue: Double) = ink.rgb
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// The color as VoiceOver says it.
    static func name(_ ink: MarkInk) -> String {
        switch ink {
        case .black: return String(localized: "Black")
        case .blue: return String(localized: "Blue")
        case .red: return String(localized: "Red")
        case .green: return String(localized: "Green")
        case .yellow: return String(localized: "Yellow")
        case .pink: return String(localized: "Pink")
        case .orange: return String(localized: "Orange")
        }
    }

    /// "No marks", "1 mark", "3 marks"
    var markCountName: String {
        let count: Int = marks.strokes.count
        return count == 0 ? String(localized: "No marks") : L10n.plural(count, one: "{0} mark", other: "{0} marks")
    }
}

/// The page to draw on, the marks it already has and how the picture was turned and cut when it was shown.
struct MarkUpRequest: Identifiable {
    let id: UUID
    let image: CGImage
    let marks: PageMarks?
    let quarterTurns: Int
    let showsOriginal: Bool
}

/// Mark Up on the iPhone and iPad: the page as saved, fitted to the screen, drawn on with a finger or the Pencil
/// in a pen or a highlighter of four colors; Undo takes off the last stroke. Done answers with the strokes
/// (nil when nothing changed), Cancel with nil, after asking when there is something to lose. What it does is
/// `MarkUpModel`; this view draws it.
struct MarkUpView: View {
    let image: CGImage
    /// False while a save reads the pages: the strokes are kept once it ends.
    let canFinish: Bool
    let onAnswer: @MainActor (PageMarks?) -> Void

    @State private var model: MarkUpModel
    @State private var asksDiscard: Bool = false

    init(image: CGImage, marks: PageMarks?, quarterTurns: Int, showsOriginal: Bool, canFinish: Bool,
         onAnswer: @escaping @MainActor (PageMarks?) -> Void) {
        self.image = image
        self.canFinish = canFinish
        self.onAnswer = onAnswer
        let size = CGSize(width: image.width, height: image.height)
        _model = State(initialValue: MarkUpModel(marks: marks, showsOriginal: showsOriginal, quarterTurns: quarterTurns,
                                                 pageSize: size))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { (geometry: GeometryProxy) in
                    stage(size: geometry.size)
                }
                .environment(\.layoutDirection, .leftToRight)
                strip
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(PageViewerText.markUpLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(PageViewerText.cancelLabel, action: cancel)
                        .accessibilityIdentifier("markup.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: finish)
                        .disabled(!canFinish)
                        .accessibilityIdentifier("markup.done")
                }
            }
        }
        .confirmationDialog(PageViewerText.discardMarksQuestion, isPresented: $asksDiscard, titleVisibility: .visible) {
            Button(PageViewerText.discardLabel, role: .destructive) {
                onAnswer(nil)
            }
            Button(PageViewerText.keepDrawingLabel, role: .cancel) {}
        }
    }

    private func cancel() {
        if model.isChanged {
            asksDiscard = true
        } else {
            onAnswer(nil)
        }
    }

    private func finish() {
        onAnswer(model.isChanged ? model.marks : nil)
    }

    private func stage(size: CGSize) -> some View {
        let frame: CGRect = model.fittedFrame(in: size)
        let marks: PageMarks = model.marks
        let turns: Int = model.quarterTurns
        let picture: CGImage = image
        return Canvas { (context: inout GraphicsContext, _: CGSize) in
            context.draw(Image(decorative: picture, scale: 1), in: frame)
            Self.draw(marks, turns: turns, frame: frame, in: &context)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(drawGesture(frame: frame))
        .accessibilityElement()
        .accessibilityLabel(Text(PageViewerText.drawingAreaLabel))
        .accessibilityValue(Text(model.markCountName))
        .accessibilityIdentifier("markup.canvas")
    }

    private static func draw(_ marks: PageMarks, turns: Int, frame: CGRect, in context: inout GraphicsContext) {
        let shorter: CGFloat = min(frame.width, frame.height)
        for stroke in marks.strokes where !stroke.points.isEmpty {
            let color: Color = MarkUpModel.color(stroke.ink)
            let width: CGFloat = CGFloat(stroke.tool.width) * shorter
            let points: [CGPoint] = stroke.points.map { (point: MarkPoint) -> CGPoint in
                MarkUpModel.viewPoint(point, quarterTurns: turns, frame: frame)
            }
            // The highlighter multiplies with the page, as it does when the page is saved.
            context.blendMode = stroke.tool == .highlighter ? .multiply : .normal
            if points.count == 1 {
                let dot = CGRect(x: points[0].x - width / 2, y: points[0].y - width / 2, width: width, height: width)
                context.fill(Path(ellipseIn: dot), with: .color(color))
                continue
            }
            var path = Path()
            path.addLines(points)
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawGesture(frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { (value: DragGesture.Value) in
                if !model.drawing {
                    // A finger that came down off the page draws nothing.
                    if !model.begin(at: value.startLocation, frame: frame) { return }
                }
                model.extend(to: value.location, frame: frame)
            }
            .onEnded { (_: DragGesture.Value) in
                model.end()
            }
    }

    // MARK: The tool strip

    private var strip: some View {
        HStack(spacing: 0) {
            toolButton(.pen, symbol: "pencil.tip", label: PageViewerText.penLabel, identifier: "markup.pen")
            toolButton(.highlighter, symbol: "highlighter", label: PageViewerText.highlighterLabel,
                       identifier: "markup.highlighter")
            Spacer(minLength: 8)
            ForEach(0..<model.inks.count, id: \.self) { (index: Int) in
                colorDot(index)
            }
            Spacer(minLength: 8)
            Button {
                model.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 44, height: 44)
            }
            .disabled(!model.canUndo)
            .accessibilityLabel(Text(PageViewerText.undoStrokeLabel))
            .accessibilityIdentifier("markup.undo")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private func toolButton(_ tool: MarkTool, symbol: String, label: String, identifier: String) -> some View {
        let selected: Bool = model.tool == tool
        let traits: AccessibilityTraits = selected ? [.isToggle, .isSelected] : .isToggle
        let fill: Color = selected ? Color.accentColor.opacity(0.15) : Color.clear
        let tint: Color = selected ? Color.accentColor : Color.secondary
        return Button {
            model.select(tool)
        } label: {
            Image(systemName: symbol)
                .frame(width: 44, height: 44)
                .foregroundStyle(tint)
                .background(Capsule().fill(fill))
        }
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(traits)
        .accessibilityIdentifier(identifier)
    }

    private func colorDot(_ index: Int) -> some View {
        let ink: MarkInk = model.inks[index]
        let selected: Bool = model.colorIndex == index
        let traits: AccessibilityTraits = selected ? [.isButton, .isSelected] : .isButton
        return Button {
            model.pick(color: index)
        } label: {
            Circle()
                .fill(MarkUpModel.color(ink))
                .frame(width: 24, height: 24)
                .overlay(Circle().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1))
                .padding(3)
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
                .frame(width: 36, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(MarkUpModel.name(ink)))
        .accessibilityAddTraits(traits)
        .accessibilityIdentifier("markup.color.\(index)")
    }
}
#endif
