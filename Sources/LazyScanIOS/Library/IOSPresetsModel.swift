#if os(iOS)
import LazyScanKit
import Foundation

/// The presets screen's words.
public enum IOSPresetText {
    public static var title: String { String(localized: "Presets") }
    public static var groupTitle: String { String(localized: "My presets") }
    public static var saveLabel: String { String(localized: "Save preset") }
    public static var saveTitle: String { String(localized: "Save preset") }
    public static var saveLine: String { String(localized: "Saves the current settings to use again.") }
    public static var namePlaceholder: String { String(localized: "Preset name") }
    public static var renameLabel: String { String(localized: "Rename") }
    public static var renameTitle: String { String(localized: "Rename preset") }
    public static var deleteLabel: String { String(localized: "Delete") }
    public static var emptyTitle: String { String(localized: "No presets") }
    public static var emptyLine: String { String(localized: "Save your settings to use them again.") }
    public static var discardTitle: String { String(localized: "Discard the ID card?") }
    public static var discardLine: String { String(localized: "The ID card has not been saved. Its sides will be discarded.") }
    public static var discardLabel: String { String(localized: "Discard") }
}

/// A preset as the list shows it: its name, the kind it brings back with the kind's icon, as the kind tiles
/// show them, and the settings' one-line summary (`TaskCatalog.summary`).
public struct IOSPresetRow: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let taskTitle: String
    public let summary: String
    public let symbol: String

    public init(preset: Preset) {
        let kind: IOSScanKind = IOSShell.shownKind(preset.settings)
        self.id = preset.id
        self.name = preset.name
        self.taskTitle = kind.title
        self.summary = TaskCatalog.summary(preset.settings)
        self.symbol = kind.symbol
    }

    /// "Invoices preset", as VoiceOver reads the row.
    public var accessibilityLabel: String { String(localized: "\(name) preset") }
    /// "Preset for Document. 300 dpi · Color · PDF."
    public var accessibilityHint: String { String(localized: "Preset for \(taskTitle). \(summary).") }
}

/// What applying a preset came to.
public enum IOSPresetApply: Equatable, Sendable {
    /// The preset's settings are in use.
    case applied
    /// An ID card side is held and not saved: the preset waits until the user discards it
    /// (`AppState.pendingIdCardLeave`).
    case waitsForDiscard
    /// Pages are queued and the preset's settings would leave them without a Save: nothing is applied until
    /// the user saves or discards them. The preset's name, for the question.
    case waitsForPages(String)
    /// Nothing happened: an operation, an import, or a share or a send of the queue runs, or the preset is
    /// gone.
    case refused
}

/// The presets screen without a screen: the presets as rows, saving the current settings as one,
/// renaming, deleting and applying one, all through `AppState` and its `PresetStore` (presets.json).
/// There are no built-in presets: a first run starts with none.
@MainActor
public final class IOSPresetsModel {
    private let state: AppState
    private let importer: IOSImportSession
    /// Where the phone's mode (`IOSShell.scanModeKey`) and camera mode's Items in frame are kept.
    private let defaults: UserDefaults

    /// `importer`: while it imports, no preset is applied (its pages belong to the task it started in).
    public init(state: AppState, importer: IOSImportSession, defaults: UserDefaults = .standard) {
        self.state = state
        self.importer = importer
        self.defaults = defaults
    }

    public var rows: [IOSPresetRow] { IOSPresetsModel.rows(state.presets) }

    public static func rows(_ presets: [Preset]) -> [IOSPresetRow] {
        var rows: [IOSPresetRow] = []
        for preset in presets {
            rows.append(IOSPresetRow(preset: preset))
        }
        return rows
    }

    /// A name a preset can be saved or renamed with: anything but blank.
    public static func isValidName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The current settings saved as a preset named `name` (trimmed); false for a blank name.
    @discardableResult
    public func save(named name: String) -> Bool {
        guard IOSPresetsModel.isValidName(name) else { return false }
        state.saveCurrentAsPreset(named: name)
        return true
    }

    @discardableResult
    public func rename(_ id: UUID, to name: String) -> Bool {
        state.renamePreset(id: id, to: name)
    }

    public func delete(_ id: UUID) {
        state.deletePreset(id: id)
    }

    /// The preset's settings put in use, fitted to the scanner (`AppState.applyPreset`), and a PDF picked
    /// to add the pages to forgotten, then `done` runs; with an ID card side held, both wait until the user
    /// discards the card. Settings that do not collect pages (`IOSShell.collectsPages`: the ID card, Text, or
    /// Collect pages before saving off) are not applied over queued pages unless `discardingPages`, which
    /// drops them with their spooled files first. In camera mode, which has no Text, a Quick scan preset is
    /// applied as Document with its own choices (`IOSShell.cameraPreset`). With no scanner selected (camera
    /// mode) a stack turned over by hand is applied as both sides, as the camera takes them. Refused while
    /// an operation, an import, or a share or a send of the queue runs.
    @discardableResult
    public func apply(_ id: UUID, discardingPages: Bool = false,
                      then done: @escaping @MainActor () -> Void) -> IOSPresetApply {
        guard !state.isBusy, !importer.isImporting, !state.readsQueue else { return .refused }
        guard let preset = state.presets.first(where: { (item: Preset) -> Bool in item.id == id }) else {
            return .refused
        }
        // No mode kept yet is camera mode, the default.
        let camera: Bool = defaults.string(forKey: IOSShell.scanModeKey) != IOSScanMode.printer.rawValue
        let folded: ScanSettings = IOSShell.savingActionsAsDocument(preset.settings)
        let applied: ScanSettings = camera ? IOSShell.cameraPreset(folded) : folded
        let collects: Bool = IOSShell.collectsPages(applied)
        if !discardingPages && !collects && !state.scannedPages.isEmpty {
            return .waitsForPages(preset.name)
        }
        let held: Bool = state.hasIdCardCaptures
        let appState: AppState = state
        let userDefaults: UserDefaults = defaults
        state.leaveIdCard {
            if discardingPages {
                appState.clearPages()
            }
            IOSShell.rememberChoices(appState.settings, defaults: userDefaults)
            appState.applyPreset(preset)
            var settings: ScanSettings = IOSShell.savingActionsAsDocument(appState.settings)
            if camera {
                settings = IOSShell.cameraPreset(settings)
            }
            appState.settings = settings
            // With no scanner a stack turned over by hand would leave the camera nothing to take; a
            // one-sided feeder turns both sides back into by hand once it is selected.
            if appState.selectedDeviceID == nil && appState.settings.duplex == .manual {
                appState.settings.duplex = .both
            }
            appState.clearAppendTarget()
            done()
        }
        return held ? .waitsForDiscard : .applied
    }
}
#endif
