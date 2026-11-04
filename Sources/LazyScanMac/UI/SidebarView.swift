#if os(macOS)
import LazyScanKit
import SwiftUI

/// Left column: the list of discovered scanner devices.
struct SidebarView: View {
    @EnvironmentObject var state: AppState
    /// "Send from your phone" is open (`PhoneView`).
    @State private var showPhone = false

    var body: some View {
        List(selection: deviceSelection) {
            Section {
                ForEach(state.devices) { device in
                    DeviceRow(device: device, frozen: state.isBusy)
                        .tag(device.id)
                        // Simultaneous, so the List still selects the row.
                        .simultaneousGesture(retryTap(device.id))
                        // Frozen while an operation runs: picking another scanner would cancel the scan.
                        .selectionDisabled(state.isBusy)
                        .help(rowHelp)
                }
                if !state.hasRealDevices {
                    // Twin of the Windows side pane: what is missing, and the way to find out why.
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No scanner found")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Button("Troubleshoot") {
                            state.showTroubleshooter = true
                        }
                        .buttonStyle(.link)
                        .font(.callout)
                        .help("Why isn't my scanner listed?")
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                HStack {
                    Text("Scanners")
                    Spacer()
                    // Until a scanner is listed, the Troubleshoot link in the list is the one way in.
                    if state.hasRealDevices {
                        Button {
                            state.showTroubleshooter = true
                        } label: {
                            Image(systemName: "questionmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("Why isn't my scanner listed?")
                        .accessibilityLabel("Why isn't my scanner listed?")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footerHint
        }
        .toolbar {
            Button {
                state.refreshScanners()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Look for scanners again")
            Button {
                showPhone = true
            } label: {
                Label("Phone", systemImage: "iphone")
            }
            .help("Send from your phone: pair a phone and see whether this Mac receives")
        }
        .sheet(isPresented: $state.showTroubleshooter) {
            TroubleshooterView()
                .environmentObject(state)
        }
        .sheet(isPresented: $showPhone) {
            PhoneView()
                .environmentObject(state)
        }
    }

    // MARK: Helpers

    /// Selection is owned by AppState: the setter routes through `userSelectDevice`
    /// so the model can distinguish user picks from automatic ones, and through `leaveIdCard`, which
    /// asks first while a side of the ID card is held (a scanner without a flatbed ends the task, and a
    /// scanner's sources are known only once it is open; Cancel leaves the List as it was) and refuses
    /// while an operation runs, also a deselection, which the frozen rows do not stop.
    private var deviceSelection: Binding<String?> {
        Binding(
            get: { state.selectedDeviceID },
            set: { id in
                let appState = state
                appState.leaveIdCard { appState.userSelectDevice(id) }
            }
        )
    }

    private var rowHelp: String {
        state.isBusy ? String(localized: "Wait for the scan to finish") : ""
    }

    /// A click on the selected scanner while it is not connected (it was off, or did not answer) opens it
    /// again: the List sets its selection only when it changes. Twin of the Windows `DeviceList_PreviewMouseDown`.
    private func retryTap(_ id: String) -> some Gesture {
        TapGesture().onEnded {
            guard id == state.selectedDeviceID, !state.isBusy, !state.isConnected, !state.isConnecting else { return }
            state.userSelectDevice(id)
        }
    }

    private var footerHint: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            Text("If a USB scanner isn't listed, install the manufacturer's macOS driver.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.bar)
    }
}

// MARK: - Row

private struct DeviceRow: View {
    let device: ScannerInfo
    let frozen: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: device.isDemo ? "sparkles.rectangle.stack" : "scanner")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(nameStyle)
                transport
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var nameStyle: HierarchicalShapeStyle { frozen ? .secondary : .primary }

    private var transport: Text {
        if device.isDemo { return Text("Demo (no hardware)") }
        switch device.transport {
        case "Network": return Text("Network")
        case "Shared": return Text("Shared")
        default: return Text(device.transport)
        }
    }
}
#endif
