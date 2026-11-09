#if os(iOS)
import LazyScanKit
import SwiftUI

/// A group of the options drawer, an icon each in its row.
enum DrawerGroup: String, Identifiable, CaseIterable {
    case colour
    case scanner
    case flash
    case camera

    var id: String { rawValue }

    var title: String {
        switch self {
        case .colour: return String(localized: "Color")
        case .scanner: return String(localized: "Scanner")
        case .flash: return IOSCameraText.flashLabel
        case .camera: return IOSImportText.cameraLabel
        }
    }

    var symbol: String {
        switch self {
        case .colour: return "circle.lefthalf.filled"
        case .scanner: return "scanner"
        case .flash: return "bolt"
        case .camera: return "camera"
        }
    }

    /// The groups of the camera tab: Colour, Flash where the camera has a light (`torch`) and Camera; of the
    /// scanner tab (`printer`): Colour and Scanner.
    static func shown(printer: Bool, torch: Bool) -> [DrawerGroup] {
        if printer {
            return [.colour, .scanner]
        }
        return torch ? [.colour, .flash, .camera] : [.colour, .camera]
    }
}

/// The options drawer both tabs open with the arrow, above the bottom bar so it never covers the picture: a
/// row of icons, one per group (`DrawerGroup.shown`), and the chosen group's controls under it. Colour: the
/// filter new pages get, or the colour mode for the kinds that collect no pages and on the scanner tab (and
/// Restore faded colours for Photos). Flash: the camera's light (its torch), where it has one. Camera: the
/// automatic shutter, Both sides and how the sides or a book's pages are taken, Items in frame for Photo
/// and Document, Straighten pages. Scanner: the scanner's Source, Sides and Resolution. `model` is the
/// camera's, nil on the scanner tab. What is saved is in the Options sheet.
struct ScanDrawer: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var importer: IOSImportSession
    let model: IOSCameraModel?
    let torch: Bool
    @Binding var group: DrawerGroup

    var body: some View {
        let groups: [DrawerGroup] = DrawerGroup.shown(printer: model == nil, torch: torch)
        let shown: DrawerGroup = groups.contains(group) ? group : (groups.first ?? DrawerGroup.colour)
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                ForEach(groups) { (item: DrawerGroup) in
                    groupButton(item, selected: item == shown)
                }
            }
            .frame(height: 56)
            // The icons sit in fixed circles.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            controls(shown)
                .padding(.horizontal, 16)
                .disabled(state.isBusy || importer.isImporting)
        }
        .padding(.bottom, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawer")
    }

    private func groupButton(_ item: DrawerGroup, selected: Bool) -> some View {
        Button {
            group = item
        } label: {
            Image(systemName: item.symbol)
                .font(.body.weight(.medium))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(selected ? Color.accentColor : Color(uiColor: .tertiarySystemFill)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(item.title))
        .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : [])
        .accessibilityIdentifier("drawer.\(item.rawValue)")
    }

    @ViewBuilder
    private func controls(_ shown: DrawerGroup) -> some View {
        switch shown {
        case .colour:
            ColourDrawer(camera: model != nil)
        case .scanner:
            VStack(spacing: 8) {
                ScannerSettingsRows(includesColor: false)
            }
        case .flash:
            if let model {
                FlashPicker(model: model)
            }
        case .camera:
            if let model {
                CameraControls(model: model)
            }
        }
    }
}

/// The drawer's Flash group: the camera's light, on or off.
private struct FlashPicker: View {
    @ObservedObject var model: IOSCameraModel

    var body: some View {
        Picker(IOSCameraText.flashLabel, selection: torch) {
            Text(IOSCameraText.offValue).tag(false)
            Text(IOSCameraText.onValue).tag(true)
        }
        .pickerStyle(.segmented)
        .disabled(!model.lifecycle.isLive)
        .accessibilityIdentifier("camera.torch")
    }

    private var torch: Binding<Bool> {
        let shown: IOSCameraModel = model
        return Binding<Bool>(
            get: { shown.torchOn },
            set: { (on: Bool) in
                guard on != shown.torchOn else { return }
                Task { @MainActor in
                    await shown.toggleTorch()
                }
            })
    }
}

/// The drawer's Camera group: the automatic shutter, Both sides and how the sides or a book's pages are
/// taken, Items in frame for Photo and Document, Straighten pages.
private struct CameraControls: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var model: IOSCameraModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(IOSCameraText.autoShutterLabel, isOn: autoShutter)
                .accessibilityHint(Text(IOSCameraText.autoHint))
                .accessibilityIdentifier("camera.auto")
            if IOSShell.shownKind(state.settings) == .document {
                BothSidesToggle()
            }
            TaskWayPicker()
            if IOSShell.offersItemsInFrame(state.settings) {
                ItemsInFramePicker(kind: IOSShell.shownKind(state.settings))
            }
            if IOSShell.offersStraighten(state.settings) {
                StraightenToggle()
            }
        }
    }

    private var autoShutter: Binding<Bool> {
        let shown: IOSCameraModel = model
        return Binding<Bool>(
            get: { shown.autoShutter },
            set: { (on: Bool) in
                shown.setAutoShutter(on)
            })
    }
}

/// The drawer's Items in frame, kept in the user's defaults (`IOSShell.itemsInFrameKey`) where the import of
/// the next shot reads it, with the line that says what Auto does for the kind. Photo offers Auto and One:
/// Several would cut out every print, as its Auto does.
private struct ItemsInFramePicker: View {
    @AppStorage(IOSShell.itemsInFrameKey) private var items: IOSItemsInFrame = .auto
    let kind: IOSScanKind

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(IOSCameraText.itemsInFrameLabel)
                Spacer()
                Picker(IOSCameraText.itemsInFrameLabel, selection: shown) {
                    ForEach(choices) { (choice: IOSItemsInFrame) in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("camera.itemsInFrame")
            }
            Text(IOSCameraText.itemsInFrameHint(kind))
                .font(.caption)
                .foregroundStyle(Color.secondary)
        }
    }

    private var choices: [IOSItemsInFrame] {
        kind == .photos ? [IOSItemsInFrame.auto, .one] : IOSItemsInFrame.allCases
    }

    /// The pick as the kind shows it. The Document keeps its choice under the same key, so its Several is
    /// Photo's Auto rather than no segment at all.
    private var shown: Binding<IOSItemsInFrame> {
        let kept: Binding<IOSItemsInFrame> = $items
        let photo: Bool = kind == .photos
        return Binding<IOSItemsInFrame>(
            get: { photo && kept.wrappedValue == .several ? IOSItemsInFrame.auto : kept.wrappedValue },
            set: { (choice: IOSItemsInFrame) in
                kept.wrappedValue = choice
            })
    }
}

/// The drawer's Straighten pages, kept in the user's defaults (`IOSShell.straightenKey`) where the import of
/// the next shot reads it; on until it is turned off.
private struct StraightenToggle: View {
    @AppStorage(IOSShell.straightenKey) private var straighten: Bool = true

    var body: some View {
        Toggle("Straighten pages", isOn: $straighten)
            .accessibilityIdentifier("camera.straighten")
    }
}

/// The filter new pages get on the camera tab (Original, Enhanced, Grayscale, B&W; `IOSShell.drawerFilter`,
/// `settingDrawerFilter`): the drawer's Colour group and the Look page are two places for the one setting.
struct CaptureFilterPicker: View {
    @EnvironmentObject private var state: AppState
    let identifier: String

    var body: some View {
        Picker("Color", selection: filter) {
            ForEach(CaptureFilter.displayOrder, id: \.self) { (choice: CaptureFilter) in
                Text(choice.label).tag(choice)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier(identifier)
    }

    private var filter: Binding<CaptureFilter> {
        let appState: AppState = state
        return Binding<CaptureFilter>(
            get: { IOSShell.drawerFilter(appState.settings) },
            set: { (choice: CaptureFilter) in
                appState.settings = IOSShell.settingDrawerFilter(choice, in: appState.settings)
            })
    }
}

/// The drawer's Colour group: on the camera tab the filter new pages get (Original, Enhanced, Grayscale, B&W)
/// for the kinds that collect pages, else the colour mode, and for Photos whether faded colours are restored.
private struct ColourDrawer: View {
    @EnvironmentObject private var state: AppState
    /// The camera tab: its filters, where the scanner tab keeps the colour modes.
    let camera: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if IOSShell.shownKind(state.settings) == .photos {
                Picker("Photos", selection: restore) {
                    Text("As taken").tag(false)
                    Text("Restored").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("drawer.restore")
            }
            if camera && IOSShell.offersFilters(state.settings) {
                CaptureFilterPicker(identifier: "drawer.colourMode")
            } else {
                Picker("Color", selection: $state.settings.colorMode) {
                    ForEach(ColorMode.allCases) { (mode: ColorMode) in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("drawer.colourMode")
            }
        }
    }

    private var restore: Binding<Bool> {
        let appState: AppState = state
        return Binding<Bool>(
            get: { appState.settings.adjustments.restoreFadedColors },
            set: { (on: Bool) in
                appState.settings = IOSShell.settingRestore(on, in: appState.settings)
            })
    }
}
#endif
