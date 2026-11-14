#if os(macOS)
import LazyScanKit
import SwiftUI

/// The bar under the canvas: Preview, Scan and Cancel, and Import photos of documents beside them. It does not
/// depend on the settings column, so a scan can be started and stopped with that hidden. On the other tabs
/// (`showsScanButtons` off) it shows only the progress and Cancel while a scan runs, or the countdown and Stop between passes.
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
                    } else if let left = state.scanAgainRemaining {
                        countdownText(left)
                        Spacer(minLength: 10)
                    } else {
                        importButton
                        Spacer(minLength: 10)
                    }
                    scanButtons
                }
                VStack(spacing: 10) {
                    if !state.isBusy && state.scanAgainRemaining == nil {
                        importButton
                    }
                    HStack(spacing: 10) {
                        if state.isBusy {
                            progressBar
                        } else if let left = state.scanAgainRemaining {
                            countdownText(left)
                            Spacer(minLength: 0)
                        } else {
                            Spacer(minLength: 0)
                        }
                        scanButtons
                    }
                }
            }
            .onChange(of: state.scanAgainRemaining) { old, new in
                announceScanAgain(from: old, to: new)
            }
        } else {
            HStack(spacing: 10) {
                if let left = state.scanAgainRemaining, !state.isBusy {
                    countdownText(left)
                    Spacer(minLength: 10)
                    stopButton
                } else {
                    progressBar
                    cancelButton
                }
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
            .disabled(state.isBusy || state.scanAgainRemaining != nil || state.previewUnavailableReason != nil)
            .help(state.previewUnavailableReason ?? String(localized: "Quick look at the whole glass"))

            if state.scanAgainRemaining != nil {
                stopButton
            } else {
                Button {
                    state.performScan()
                } label: {
                    Label(state.primaryActionLabel, systemImage: "scanner")
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isBusy || !state.isConnected)
                .help(scanHelp)
            }

            if state.isBusy {
                cancelButton
            }
        }
    }

    private var stopButton: some View {
        Button {
            state.cancelScan()
        } label: {
            Label("Stop", systemImage: "stop.fill")
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.cancelAction)
        .help("Stop scanning")
        .accessibilityHint(Text("Stops scanning pages by itself"))
    }

    private func countdownText(_ left: Int) -> some View {
        Text("Scanning again in \(left) s")
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityLabel(Text("Scanning again in \(left) seconds"))
    }

    /// The countdown is not read every second: VoiceOver hears it when it starts and when it ends without a scan.
    private func announceScanAgain(from old: Int?, to new: Int?) {
        if old == nil, let left = new {
            let message: String = String(localized: "Scanning again in \(left) seconds")
            AccessibilityNotification.Announcement(message).post()
        } else if new == nil, old != nil, !state.isBusy {
            AccessibilityNotification.Announcement(String(localized: "Stopped")).post()
        }
    }

    private var cancelButton: some View {
        Button("Cancel") { state.cancelScan() }
            .keyboardShortcut(.cancelAction)
            .help("Stop")
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
