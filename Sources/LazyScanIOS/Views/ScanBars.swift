#if os(iOS)
import LazyScanKit
import SwiftUI

/// The top bar of both tabs: the library at the left (`onLibrary`; none where the sidebar has it) and at the
/// right `trailing`, which ends in the mode switch (`ModeSwitch`).
struct ScanTopBar<Trailing: View>: View {
    let onLibrary: (() -> Void)?
    let trailing: Trailing

    init(onLibrary: (() -> Void)?, @ViewBuilder trailing: () -> Trailing) {
        self.onLibrary = onLibrary
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            libraryButton
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var libraryButton: some View {
        if let open = onLibrary {
            Button {
                open()
            } label: {
                Image(systemName: "books.vertical")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(IOSSettingsText.libraryLabel))
            .accessibilityIdentifier("open.library")
        } else {
            Color.clear
                .frame(width: 44, height: 44)
        }
    }
}

/// The Camera | Scanner switch at the top right of both tabs: the segment of the tab shown is filled and does
/// nothing, the other one switches the mode (`onSwitch`). `disabled` is while the switch must not happen.
struct ModeSwitch: View {
    let onCamera: Bool
    let disabled: Bool
    let onSwitch: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment(IOSImportText.cameraLabel, selected: onCamera, hint: IOSCameraText.cameraModeHint,
                    identifier: "mode.camera")
            segment(IOSCameraText.printerLabel, selected: !onCamera, hint: IOSCameraText.printerHint,
                    identifier: "mode.printer")
        }
        .background(Capsule().fill(Color(uiColor: .tertiarySystemFill)).frame(height: 32))
        .opacity(disabled ? 0.4 : 1)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func segment(_ title: String, selected: Bool, hint: String, identifier: String) -> some View {
        Button {
            if !selected {
                onSwitch()
            }
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(Capsule().fill(selected ? Color.accentColor : Color.clear).frame(height: 32))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityHint(Text(selected ? "" : hint))
        .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// The pill at the foot of the picture that shows or hides the controls drawer under it.
struct DrawerHandle: View {
    @Binding var open: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    var body: some View {
        let symbol: String = open ? "chevron.down" : "chevron.up"
        let label: String = open ? IOSCameraText.hideControls : IOSCameraText.showControls
        let fill: Color = open ? Color.accentColor : Color(white: 0.15)
        return Button {
            if reduceMotion {
                open.toggle()
            } else {
                withAnimation(Animation.snappy) {
                    open.toggle()
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(IOSCameraText.controlsLabel)
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 28)
            .background(Capsule().fill(fill))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier("drawer.toggle")
    }
}

/// The items of a Type menu, one per tile: the Options sheet's Type row and the camera's Type label list the
/// kinds the same way. A kind that cannot start is dimmed, with the reason in its hint.
struct KindMenuItems: View {
    let tiles: [IOSKindTile]
    let settings: ScanSettings
    let camera: Bool
    let onType: (IOSScanKind) -> Void

    var body: some View {
        ForEach(tiles) { (tile: IOSKindTile) in
            let kind: IOSScanKind = tile.kind
            let available: Bool = tile.availability.isAvailable
            let name: String = camera ? kind.cameraTitle : kind.title
            let subtitle: String = kind.shownSubtitle(for: settings)
            let hint: String = available ? subtitle : String(localized: "\(subtitle). Not available: \(tile.availability.reason ?? "")")
            Button {
                onType(kind)
            } label: {
                if tile.isCurrent {
                    Label(name, systemImage: "checkmark")
                } else {
                    Text(name)
                }
            }
            .disabled(!available)
            .accessibilityHint(Text(hint))
            .accessibilityIdentifier("type.\(kind.rawValue)")
        }
    }
}

/// Options and Save as round buttons over the bottom corners of the picture on both tabs, Options at the
/// leading corner (it opens the sheet of everything about what is saved) and Save at the trailing one. Both
/// are always there; Save keeps Options' dark look with a dimmed glyph while nothing can be saved. Save's
/// accessibility label is its `title` ("Save", or "Add to Contract.pdf" while the pages go into a PDF
/// picked) and the format and the pages are its value (`detail`); while a PDF is picked the caption
/// `adding` between the buttons says so in words.
/// With Separate documents, Split here sits there too (`SplitHereButton`), at the buttons' height.
struct PictureButtons: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var importer: IOSImportSession
    let title: String
    let detail: String
    let canSave: Bool
    let adding: String?
    let onOptions: () -> Void
    let onSave: () -> Void

    static let diameter: CGFloat = 52
    static let margin: CGFloat = 16
    /// How far up from the picture's foot the notices and the other overlays stay, clear of the buttons.
    static let clearance: CGFloat = margin + diameter + 8

    var body: some View {
        HStack(spacing: 8) {
            optionsButton
            VStack(spacing: 6) {
                if let adding {
                    Text(IOSShell.addingCaption(adding))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .accessibilityHidden(true)
                }
                if state.offersNewDocument {
                    SplitHereButton()
                }
            }
            .frame(maxWidth: .infinity)
            saveButton
        }
        .padding(Self.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    private var optionsButton: some View {
        Button(action: onOptions) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: Self.diameter, height: Self.diameter)
                .background(Circle().fill(Color(white: 0.15)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // An import's corner editor needs the screen; the sheet closes as one starts.
        .disabled(importer.isImporting)
        .opacity(importer.isImporting ? 0.4 : 1)
        .accessibilityLabel(Text("Options"))
        .accessibilityIdentifier("options.button")
    }

    private var saveButton: some View {
        let fill: Color = canSave ? Color.accentColor : Color(white: 0.15)
        let stroke: Color = canSave ? Color.clear : Color.white.opacity(0.3)
        let glyph: Color = canSave ? Color.white : Color.white.opacity(0.4)
        return Button(action: onSave) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(glyph)
                // The tray makes the symbol bottom-heavy, so centred by its bounds it looks low in the circle.
                .offset(y: -2)
                .frame(width: Self.diameter, height: Self.diameter)
                .background(Circle().fill(fill))
                .overlay(Circle().strokeBorder(stroke, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .keyboardShortcut(IOSShortcuts.save.keyboardShortcut)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(detail))
        .accessibilityIdentifier("save.button")
    }
}

/// The sides mismatch on a dark capsule over a picture: white words, an orange icon.
struct MismatchPill: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(Color.white)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.orange)
        }
        .font(.footnote)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.75)))
        .accessibilityIdentifier("task.mismatch")
    }
}

/// The bottom bar of both tabs: the pages as a stack (`onPages`), `centre` (the shutter, or Scan), and Photos
/// and Files, which rest the camera while one is open (`onPresenting`). The tabs share it, so the centre
/// button stays where it is when the tab is switched.
struct CaptureRow<Centre: View>: View {
    let onPages: () -> Void
    let onPresenting: (@MainActor (Bool) -> Void)?
    let centre: Centre

    init(onPages: @escaping () -> Void, onPresenting: (@MainActor (Bool) -> Void)?, @ViewBuilder centre: () -> Centre) {
        self.onPages = onPages
        self.onPresenting = onPresenting
        self.centre = centre()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PagesStack(onPages: onPages)
                .frame(maxWidth: .infinity, alignment: .leading)
            centre
            ImportButtons(round: true, onPresenting: onPresenting)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

/// The round button in the middle of the bottom bar: the camera's shutter, whose ring fills (`progress`)
/// while the page holds still for the automatic shutter, and Scan on the scanner tab.
struct ShutterRing: View {
    let progress: CGFloat
    let enabled: Bool
    let label: String
    let hint: String
    let identifier: String
    var value: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                Circle()
                    .fill(Color.accentColor)
                    .padding(7)
                // The automatic shutter's countdown: full when the page held still long enough.
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(Angle.degrees(-90))
                    .padding(1.5)
                    .animation(Animation.linear(duration: 0.1), value: progress)
            }
            .frame(width: 74, height: 74)
            .contentShape(Circle())
        }
        .buttonStyle(ShutterButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(value))
        .accessibilityHint(Text(hint))
        .accessibilityIdentifier(identifier)
    }
}

/// The pages taken, as the last one whole on a white card shaped as the page is, a second card behind it
/// once there are two, and the count on a badge inside the card; it opens the page strip. It springs and a
/// tap is felt as a page comes in.
struct PagesStack: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var importer: IOSImportSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool
    let onPages: () -> Void
    @State private var bumped: Bool = false

    /// The page's long side on the card, inside its white rim.
    private static let longSide: CGFloat = 62
    private static let rim: CGFloat = 3

    var body: some View {
        let count: Int = state.scannedPages.count
        Button {
            onPages()
        } label: {
            stack(count: count)
                .scaleEffect(bumped ? 1.1 : 1)
                .animation(reduceMotion ? nil : Animation.spring(duration: 0.4, bounce: 0.3), value: count)
                .frame(width: 76, height: 76)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The strip's sheet would sit over an import's corner editor.
        .disabled((count == 0 && !state.canUndoRemove) || importer.isImporting)
        .opacity(importer.isImporting ? 0.4 : 1)
        .onChange(of: count) { (old: Int, new: Int) in
            guard new > old, !reduceMotion else { return }
            withAnimation(.spring(duration: 0.15)) {
                bumped = true
            } completion: {
                withAnimation(.spring(duration: 0.45, bounce: 0.35)) {
                    bumped = false
                }
            }
        }
        .sensoryFeedback(SensoryFeedback.impact(weight: SensoryFeedback.Weight.light), trigger: count) { (old: Int, new: Int) -> Bool in
            new > old
        }
        .accessibilityLabel(Text(IOSCameraText.pageCount(count)))
        .accessibilityHint(Text(IOSCameraText.pagesHint))
        .accessibilityIdentifier("camera.pages")
    }

    @ViewBuilder
    private func stack(count: Int) -> some View {
        if let image = state.scannedPages.last?.image {
            let page: CGSize = Self.pageSize(image)
            let card: CGSize = CGSize(width: page.width + Self.rim * 2, height: page.height + Self.rim * 2)
            ZStack {
                if count > 1 {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(uiColor: .systemGray5))
                        .frame(width: card.width, height: card.height)
                        .rotationEffect(Angle.degrees(6))
                        .offset(x: 3, y: -2)
                        .environment(\.layoutDirection, .leftToRight)
                }
                front(image, page: page, count: count)
            }
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color(uiColor: .tertiaryLabel), style: StrokeStyle(lineWidth: 1, dash: [3]))
                .frame(width: 48, height: 64)
        }
    }

    private func front(_ image: CGImage, page: CGSize, count: Int) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: page.width, height: page.height)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .padding(Self.rim)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color(uiColor: .separator), lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.3), radius: 2, y: 1)
            .overlay(alignment: .topTrailing) {
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Capsule().fill(Color.accentColor))
                    .padding(Self.rim + 1)
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            }
    }

    /// The page in the card's box, its own shape kept: a landscape page lies on its side. Only a page
    /// narrower than a long receipt has its ends cut a little, so the card never gets thinner than its badge.
    static func pageSize(_ image: CGImage) -> CGSize {
        let width: CGFloat = CGFloat(max(image.width, 1))
        let height: CGFloat = CGFloat(max(image.height, 1))
        if height >= width {
            return CGSize(width: max(20, longSide * width / height), height: longSide)
        }
        return CGSize(width: longSide, height: max(20, longSide * height / width))
    }
}
#endif
