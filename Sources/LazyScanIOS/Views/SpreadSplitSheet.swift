#if os(iOS)
import LazyScanKit
import CoreGraphics
import SwiftUI

/// Splitting a book's spread again by hand, as on the Mac (`AppState.spreadEditor(for:)`): the spread as
/// taken with the cut drawn across it, a slider and a drag on the picture that move the cut, a Pages lie
/// picker that turns the cut across the scan or down it, and Split (Split here for a spread cut in
/// two already, which also has Keep as one page). Under the slider, Split all unsplit spreads here cuts every
/// spread kept whole at the same place (`AppState.splitUnsplitSpreads`), and is not there when none is.
/// Split, Split all and Keep as one page are off while the app is busy.
/// The pages in the strip are replaced by the new ones (`AppState.splitSpread`, `joinSpread`).
struct SpreadSplitSheet: View {
    @EnvironmentObject private var state: AppState
    let source: SpreadEditorSource
    let onClose: @MainActor () -> Void
    @State private var fraction: Double
    @State private var axis: GutterAxis
    private static let range: ClosedRange<Double> = 0.1...0.9

    init(source: SpreadEditorSource, onClose: @escaping @MainActor () -> Void) {
        self.source = source
        self.onClose = onClose
        _fraction = State(initialValue: source.fraction)
        _axis = State(initialValue: source.axis)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pages lie")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Pages lie", selection: $axis) {
                        Text("Side by Side").tag(GutterAxis.vertical)
                        Text("Stacked").tag(GutterAxis.horizontal)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityHint(Text("Side by side: the spine runs up and down the scan. Stacked: the book lay on its side."))
                    .accessibilityIdentifier("spread.axis")
                }
                GeometryReader { (proxy: GeometryProxy) in
                    picture(in: proxy.size)
                }
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityElement()
                .accessibilityLabel(Text("Spread \(source.spreadNumber)"))
                .accessibilityValue(Text(cutValue))
                .accessibilityAdjustableAction { (direction: AccessibilityAdjustmentDirection) in
                    nudge(direction)
                }
                Slider(value: $fraction, in: Self.range)
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityLabel(Text("Where the spread is cut"))
                    .accessibilityValue(Text("\(Int((fraction * 100).rounded())) percent"))
                    .accessibilityIdentifier("spread.cut")
                if unsplitCount > 0 {
                    Button("Split all unsplit spreads here") {
                        state.splitUnsplitSpreads(including: source.pageID, axis: axis, fraction: fraction)
                        onClose()
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.isBusy)
                    .accessibilityValue(Text(unsplitValue))
                    .accessibilityIdentifier("spread.splitAll")
                }
                if source.isSplit {
                    Button("Keep as one page") {
                        state.joinSpread(id: source.pageID)
                        onClose()
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.isBusy)
                    .accessibilityIdentifier("spread.keep")
                }
            }
            .padding(16)
            .navigationTitle("Spread \(source.spreadNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onClose()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(splitLabel) {
                        state.splitSpread(id: source.pageID, axis: axis, fraction: fraction)
                        onClose()
                    }
                    .disabled(state.isBusy)
                    .accessibilityIdentifier("spread.split")
                }
            }
        }
    }

    private func picture(in size: CGSize) -> some View {
        let fitted: CGRect = SpreadSplitSheet.fittedRect(width: source.preview.width,
                                                         height: source.preview.height, in: size)
        let grip: CGPoint = gripCenter(in: fitted)
        return ZStack(alignment: .topLeading) {
            Image(decorative: source.preview, scale: 1)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
            Path { (path: inout Path) in
                if axis == .vertical {
                    let x: CGFloat = fitted.minX + fitted.width * CGFloat(fraction)
                    path.move(to: CGPoint(x: x, y: fitted.minY))
                    path.addLine(to: CGPoint(x: x, y: fitted.maxY))
                } else {
                    let y: CGFloat = fitted.minY + fitted.height * CGFloat(fraction)
                    path.move(to: CGPoint(x: fitted.minX, y: y))
                    path.addLine(to: CGPoint(x: fitted.maxX, y: y))
                }
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            Circle()
                .fill(Color.accentColor)
                .overlay(Circle().stroke(Color.white, lineWidth: 3))
                .frame(width: 28, height: 28)
                .position(grip)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { (value: DragGesture.Value) in
            moveCut(to: value.location, in: fitted)
        })
    }

    private func gripCenter(in fitted: CGRect) -> CGPoint {
        if axis == .vertical {
            return CGPoint(x: fitted.minX + fitted.width * CGFloat(fraction), y: fitted.midY)
        }
        return CGPoint(x: fitted.midX, y: fitted.minY + fitted.height * CGFloat(fraction))
    }

    private func moveCut(to location: CGPoint, in fitted: CGRect) {
        guard fitted.width > 0, fitted.height > 0 else { return }
        let share: Double = axis == .vertical ? Double((location.x - fitted.minX) / fitted.width)
                                              : Double((location.y - fitted.minY) / fitted.height)
        fraction = min(max(share, Self.range.lowerBound), Self.range.upperBound)
    }

    private func nudge(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment: fraction = min(fraction + 0.01, Self.range.upperBound)
        case .decrement: fraction = max(fraction - 0.01, Self.range.lowerBound)
        @unknown default: break
        }
    }

    private var cutValue: String {
        let percent: Int = Int((fraction * 100).rounded())
        if axis == .vertical {
            return String(localized: "Cut at \(percent) percent, pages side by side")
        }
        return String(localized: "Cut at \(percent) percent, pages stacked")
    }

    private var unsplitCount: Int { state.unsplitSpreadCount }

    private var unsplitValue: String {
        L10n.plural(unsplitCount, one: "{0} spread", other: "{0} spreads")
    }

    private var splitLabel: String {
        source.isSplit ? String(localized: "Split here") : String(localized: "Split")
    }

    /// Where a picture of `width` × `height` lies when fitted into `size`, centred.
    static func fittedRect(width: Int, height: Int, in size: CGSize) -> CGRect {
        guard width > 0, height > 0, size.width > 0, size.height > 0 else { return .zero }
        let scale: CGFloat = min(size.width / CGFloat(width), size.height / CGFloat(height))
        let w: CGFloat = CGFloat(width) * scale
        let h: CGFloat = CGFloat(height) * scale
        return CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h)
    }
}
#endif
