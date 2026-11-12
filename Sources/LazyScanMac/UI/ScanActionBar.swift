#if os(macOS)
import LazyScanKit
import SwiftUI

/// The bar under the canvas: Preview, Scan and Cancel, and Import photos of documents beside them. It does not
/// depend on the settings column, so a scan can be started and stopped with that hidden. On the other tabs
/// (`showsScanButtons` off) it shows only the progress and Cancel, and only while a scan runs.
struct ScanActionBar: View {
    @EnvironmentObject var state: AppState
    let showsScanButtons: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            content
                .controlSize(.large)
                .padding(12)
                .background(.bar)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Scan actions"))
    }

    @ViewBuilder
    private var content: some View {
        if showsScanButtons {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    if state.isBusy {
                        progressBar
                    } else {
                        importButton
                        Spacer(minLength: 10)
                    }
                    scanButtons
                }
                VStack(spacing: 10) {
                    if !state.isBusy {
                        importButton
                    }
                    HStack(spacing: 10) {
                        if state.isBusy {
                            progressBar
                        } else {
                            Spacer(minLength: 0)
                        }
                        scanButtons
                    }
                }
            }
        } else {
            HStack(spacing: 10) {
                progressBar
                cancelButton
            }
        }
    }

    private var progressBar: some View {
        ProgressView(value: state.progress?.fraction)
            .progressViewStyle(.linear)
            .accessibilityLabel(Text("Scan progress"))
    }

    private var scanButtons: some View {
        HStack(spacing: 10) {
            Button {
                state.performOverview()
            } label: {
                Label("Preview", systemImage: "viewfinder")
            }
            .buttonStyle(.bordered)
            .disabled(state.isBusy || state.previewUnavailableReason != nil)
            .help(state.previewUnavailableReason ?? String(localized: "Quick look at the whole glass"))

            Button {
                state.performScan()
            } label: {
                Label(state.primaryActionLabel, systemImage: "scanner")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(state.isBusy || !state.isConnected)
            .help(scanHelp)

            if state.isBusy {
                cancelButton
            }
        }
    }

    private var cancelButton: some View {
        Button("Cancel") { state.cancelScan() }
            .keyboardShortcut(.cancelAction)
            .help("Stop the scan")
    }

    // Photos of documents become pages of the queue too, with no scanner (AppState+Import.swift).
    @ViewBuilder
    private var importButton: some View {
        if PhotoImport.isOffered(state.settings) {
            Button {
                state.chooseAndImportPhotos()
            } label: {
                Label(PhotoImport.buttonLabel, systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.bordered)
            .disabled(!state.canImportPhotos)
            .help(state.isStackUnderWay ? DocumentSides.notWhileTurningOverReason : PhotoImport.buttonHint)
            .accessibilityHint(Text(PhotoImport.buttonHelp))
        }
    }

    /// Scan has help only while it waits for the scanner.
    private var scanHelp: String { notConnectedHelp ?? "" }

    /// Why Scan is off while no scanner is connected (Preview gives `AppState.previewUnavailableReason`): the selected one is still connecting, it would
    /// not connect, or none is selected; nil once it is connected. Twin of the Windows window's `NotConnectedHint`.
    private var notConnectedHelp: String? {
        guard !state.isConnected else { return nil }
        guard let id = state.selectedDeviceID else { return String(localized: "No scanner selected.") }
        let name: String? = state.devices.first(where: { $0.id == id })?.name
        if state.isConnecting {
            return name.map { String(localized: "Connecting to \($0)…") } ?? String(localized: "Connecting to the scanner…")
        }
        return name.map { String(localized: "Not connected to \($0). Choose it in the list again to retry.") }
            ?? String(localized: "Not connected to the scanner. Choose it in the list again to retry.")
    }
}
#endif
