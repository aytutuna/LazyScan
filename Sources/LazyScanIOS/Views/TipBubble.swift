#if os(iOS)
import SwiftUI
import UIKit

/// The one-time tips, in the order they are shown: Options, the Library and Save on the camera screen, then My
/// computer inside the Options sheet.
enum IOSTip: Int, CaseIterable {
    case options
    case library
    case save
    case computer

    var text: String {
        switch self {
        case .options: return String(localized: "Scan types, presets and page settings are in Options.")
        case .library: return String(localized: "Saved scans and pages.")
        case .save: return String(localized: "Save your scan here.")
        case .computer: return String(localized: "Send scans to your computer.")
        }
    }

    var identifier: String {
        switch self {
        case .options: return "tip.options"
        case .library: return "tip.library"
        case .save: return "tip.save"
        case .computer: return "tip.computer"
        }
    }
}

/// Which tip is due, kept in the user's defaults: `shownKey` once the last tip is dismissed, `stepKey` the
/// tip due next, so a relaunch does not repeat the ones already dismissed.
enum IOSTips {
    static let shownKey = "tips.shown"
    static let stepKey = "tips.step"

    /// No tips under `-demoScanner` or `-noTips`.
    static let off: Bool = IOSLaunchOptions.hidesTips(ProcessInfo.processInfo.arguments)

    static var gotItLabel: String { String(localized: "Got it") }
    static var showAgainLabel: String { String(localized: "Show the tips again") }
    static var showAgainDone: String { String(localized: "Tips will show again") }

    /// The tip due; nil once all of them have been shown.
    static func due(shown: Bool, step: Int) -> IOSTip? {
        shown ? nil : IOSTip(rawValue: step)
    }

    /// The tip due now, as the defaults say; nil when tips are off.
    static func current(defaults: UserDefaults = UserDefaults.standard) -> IOSTip? {
        guard !off else { return nil }
        return due(shown: defaults.bool(forKey: shownKey), step: defaults.integer(forKey: stepKey))
    }

    /// Dismisses `tip` when it is the one due, which makes the next one due.
    static func dismiss(_ tip: IOSTip, defaults: UserDefaults = UserDefaults.standard) {
        guard due(shown: defaults.bool(forKey: shownKey), step: defaults.integer(forKey: stepKey)) == tip else { return }
        if let next = IOSTip(rawValue: tip.rawValue + 1) {
            defaults.set(next.rawValue, forKey: stepKey)
        } else {
            defaults.set(true, forKey: shownKey)
        }
    }

    /// Makes every tip due again.
    static func reset(defaults: UserDefaults = UserDefaults.standard) {
        defaults.removeObject(forKey: shownKey)
        defaults.removeObject(forKey: stepKey)
    }
}

/// The frames of the controls the tips point at, by tip, in the space of the view that reads them.
struct TipAnchorKey: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] = [:]

    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { (_: Anchor<CGRect>, new: Anchor<CGRect>) -> Anchor<CGRect> in new }
    }
}

private struct ShownTipKey: EnvironmentKey {
    static let defaultValue: IOSTip? = nil
}

extension EnvironmentValues {
    /// The tip on screen in this part of the app, so a tap counts only for the tip being shown.
    var shownTip: IOSTip? {
        get { self[ShownTipKey.self] }
        set { self[ShownTipKey.self] = newValue }
    }
}

/// Tapping the control a tip points at counts as dismissing that tip, while that tip is the one shown.
struct TipTap: ViewModifier {
    let tip: IOSTip
    @Environment(\.shownTip) private var shownTip: IOSTip?

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(TapGesture().onEnded {
                if !IOSTips.off && shownTip == tip {
                    IOSTips.dismiss(tip)
                }
            })
    }
}

/// A control a tip points at: the camera screen reads its frame, and a tap on it dismisses the tip.
struct TipAnchor: ViewModifier {
    let tip: IOSTip

    func body(content: Content) -> some View {
        content
            .anchorPreference(key: TipAnchorKey.self, value: Anchor<CGRect>.Source.bounds) { (anchor: Anchor<CGRect>) -> [Int: Anchor<CGRect>] in
                [tip.rawValue: anchor]
            }
            .modifier(TipTap(tip: tip))
    }
}

extension View {
    func tipAnchor(_ tip: IOSTip) -> some View {
        modifier(TipAnchor(tip: tip))
    }

    func tipTap(_ tip: IOSTip) -> some View {
        modifier(TipTap(tip: tip))
    }
}

/// A tip: its line and Got it on a solid card, which is the whole tip where it sits in a list.
struct TipBubble: View {
    let tip: IOSTip

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(tip.text)
                .font(.body)
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            Button {
                IOSTips.dismiss(tip)
            } label: {
                Text(IOSTips.gotItLabel)
                    .font(.body)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("tip.gotIt")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
        .shadow(color: Color.black.opacity(0.25), radius: 8, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(tip.text))
        .accessibilityIdentifier(tip.identifier)
        .onAppear {
            AccessibilityNotification.Announcement(tip.text).post()
        }
    }
}

/// The tip's pointer: a thin triangle from the bubble's edge to the control.
private struct TipPointer: Shape {
    let base: CGPoint
    let apex: CGPoint

    func path(in rect: CGRect) -> Path {
        var path: Path = Path()
        path.move(to: CGPoint(x: base.x - 9, y: base.y))
        path.addLine(to: apex)
        path.addLine(to: CGPoint(x: base.x + 9, y: base.y))
        path.closeSubpath()
        return path
    }
}

/// Puts the due tip over the camera screen, pointing at its control's frame (`TipAnchorKey`): the Library's
/// hangs below it, the others sit above theirs. The first one stays right of the Type label that sits on the
/// Controls row, which is above Options when the phone is upright. Options' and Save's are lifted above that
/// row so they do not cover its Type label or the Controls pill.
struct TipLayer: View {
    let tip: IOSTip
    let anchor: Anchor<CGRect>
    let compact: Bool
    @Environment(\.dynamicTypeSize) private var typeSize: DynamicTypeSize

    private static let margin: CGFloat = 16
    private static let reach: CGFloat = 14
    private static let typeLabelClear: CGFloat = 130
    private static let controlsRow: CGFloat = 44

    var body: some View {
        GeometryReader { (proxy: GeometryProxy) in
            let target: CGRect = proxy[anchor]
            let size: CGSize = proxy.size
            let fullWidth: CGFloat = min(280, size.width - 2 * Self.margin)
            let clearsLabel: Bool = tip == .options && !compact
            let labelWidth: CGFloat = min(fullWidth, size.width - Self.typeLabelClear - Self.margin)
            let width: CGFloat = typeSize.isAccessibilitySize ? size.width - 2 * Self.margin : (clearsLabel ? labelWidth : fullWidth)
            let hangs: Bool = tip == .library
            let preferred: CGFloat = leading(of: target, width: width)
            let left: CGFloat = min(max(preferred, Self.margin), max(Self.margin, size.width - width - Self.margin))
            let lift: CGFloat = (tip == .options || tip == .save) && !compact ? Self.controlsRow + 4 : 0
            let edge: CGFloat = hangs ? target.maxY + Self.reach : target.minY - Self.reach - lift
            let apexY: CGFloat = hangs ? target.maxY + 2 : target.minY - 2
            let baseX: CGFloat = min(max(target.midX, left + 24), left + width - 24)
            ZStack(alignment: .topLeading) {
                TipPointer(base: CGPoint(x: baseX, y: edge), apex: CGPoint(x: target.midX, y: apexY))
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .shadow(color: Color.black.opacity(0.25), radius: 4, y: 1)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                bubble(width: width, left: left, edge: edge, hangs: hangs)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        }
        .transition(.opacity)
    }

    private func leading(of target: CGRect, width: CGFloat) -> CGFloat {
        switch tip {
        case .options: return compact ? target.minX : max(target.minX, Self.typeLabelClear)
        case .save: return target.maxX - width
        case .library, .computer: return target.minX
        }
    }

    @ViewBuilder
    private func bubble(width: CGFloat, left: CGFloat, edge: CGFloat, hangs: Bool) -> some View {
        if hangs {
            TipBubble(tip: tip)
                .frame(width: width)
                .padding(.leading, left)
                .padding(.top, edge)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            TipBubble(tip: tip)
                .frame(width: width)
                .padding(.leading, left)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: max(edge, 0), alignment: .bottom)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}
#endif
