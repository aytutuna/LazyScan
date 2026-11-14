import Foundation
import XCTest
@testable import LazyScanKit

// What applyPreset says about the save folder, and updating a preset in place.

final class AppStatePresetTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppStatePresetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try await Task.sleep(nanoseconds: 600_000_000)
        try? FileManager.default.removeItem(at: folder)
    }

    @MainActor
    func test_applyPreset_namesTheFolder_onlyWhenItChanges() {
        let state = AppState(presetStore: PresetStore(directory: folder), files: AppStateFiles.all(in: folder))
        var other = state.settings
        other.destinationPath = folder.appendingPathComponent("Invoices").path

        state.applyPreset(Preset(name: "Work", settings: other))
        XCTAssertEqual(state.statusMessage, "Applied preset \u{201C}Work\u{201D}. Saving to Invoices.")

        state.applyPreset(Preset(name: "Again", settings: other))
        XCTAssertEqual(state.statusMessage, "Applied preset \u{201C}Again\u{201D}.")
    }

    @MainActor
    func test_updatePreset_overwritesTheSettings_andKeepsNameAndId() {
        let state = AppState(presetStore: PresetStore(directory: folder), files: AppStateFiles.all(in: folder))
        state.saveCurrentAsPreset(named: "Work")
        let id = state.presets[0].id

        var changed = state.settings
        changed.resolution = 600
        state.settings = changed
        XCTAssertTrue(state.updatePreset(id: id))
        XCTAssertFalse(state.updatePreset(id: UUID()))

        let stored = PresetStore(directory: folder).load()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].id, id)
        XCTAssertEqual(stored[0].name, "Work")
        XCTAssertEqual(stored[0].settings.resolution, 600)
    }
}
