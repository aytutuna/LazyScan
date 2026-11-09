#if os(iOS)
import LazyScanKit
import SwiftUI

/// The top bar of both tabs: the library at the left (`onLibrary`; none where the sidebar has it), a small
/// round arrow that shows or hides the options drawer in the middle, and at the right `trailing`, which is
/// the other tab's icon (the scanner on the camera, the camera on the scanner tab).
struct ScanTopBar<Trailing: View>: View {
    @Binding var showsDrawer: Bool
    let onLibrary: (() -> Void)?
    let trailing: Trailing

    init(showsDrawer: Binding<Bool>, onLibrary: (() -> Void)?, @ViewBuilder trailing: () -> Trailing) {
        _showsDrawer = showsDrawer
        self.onLibrary = onLibrary
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            libraryButton
                .frame(maxWidth: .infinity, alignment: .leading)
            drawerToggle
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

    private var drawerToggle: some View {
        let open: Bool = showsDrawer
        return Button {
            withAnimation(Animation.snappy) {
                showsDrawer.toggle()
            }
        } label: {
            Image(systemName: open ? "chevron.down" : "chevron.up")
                .font(.caption.weight(.bold))
                .foregroundStyle(open ? Color.white : Color.primary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(open ? Color.accentColor : Color(uiColor: .tertiarySystemFill)))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(open ? IOSCameraText.hideOptions : IOSCameraText.showOptions))
        .accessibilityIdentifier("drawer.toggle")
    }
}

/// Options and Save as round buttons over the bottom corners of the picture on both tabs, Options at the
/// leading corner (it opens the sheet of everything about what is saved) and Save at the trailing one. Both
/// are always there; Save is dimmed while nothing can be saved. Save's accessibility label is its `title`
/// ("Save", or "Add to Contract.pdf" while the pages go into a PDF picked) and the format and the pages are
/// its value (`detail`); while a PDF is picked the caption `adding` between the buttons says so in words.
struct PictureButtons: View {
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
            if let adding {
                Text(IOSShell.addingCaption(adding))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            } else {
                Spacer(minLength: 0)
            }
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
        Button(action: onSave) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: Self.diameter, height: Self.diameter)
                .background(Circle().fill(Color.accentColor))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.4)
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
        .accessibilityHint(Text(hint))
        .accessibilityIdentifier(identifier)
    }
}

/// The pages taken, as the last one whole on a white card shaped as the page is, a second card behind it
/// once there are two, and the count on a badge inside the card; it opens the page strip. It springs and a
/// tap is felt as a page comes in.
struct PagesStack: View {
    @EnvironmentObject private var state: AppState
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
        .disabled(count == 0)
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
