#if os(macOS)
import LazyScanKit
import SwiftUI

/// Left column: the list of discovered scanner devices.
struct SidebarView: View {
    @EnvironmentObject var state: AppState
    /// "Send from your phone" is open (`PhoneView`).
    @State private var showPhone = false
    /// Add by address was chosen in the troubleshooter; its sheet opens once the troubleshooter has closed.
    @State private var addAfterTroubleshooter = false
    /// The scanner just added, picked once its sheet has gone: the question about the ID card cannot show sooner.
    @State private var addedID: String?

    var body: some View {
        List(selection: deviceSelection) {
            Section {
                ForEach(state.devices) { device in
                    DeviceRow(device: device, frozen: state.isBusy, status: status(of: device.id)) {
                        state.userSelectDevice(device.id)
                    }
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
                        // In a sidebar row the link style can take the row's text colour, white on the light grey.
                        .foregroundStyle(Color(nsColor: .linkColor))
                        .font(.callout)
                        .help("Why isn't my scanner listed?")
                        Button(L10n.t("Add by address")) {
                            state.showAddScanner = true
                        }
                        .buttonStyle(.link)
                        .foregroundStyle(Color(nsColor: .linkColor))
                        .font(.callout)
                        .help(L10n.t("Add a scanner by address"))
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                HStack {
                    Text("Scanners")
                    Spacer()
                    Button {
                        state.showAddScanner = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.t("Add a scanner by address"))
                    .accessibilityLabel(L10n.t("Add a scanner by address"))
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
        .sheet(isPresented: $state.showTroubleshooter, onDismiss: troubleshooterClosed) {
            TroubleshooterView(addByAddress: { addAfterTroubleshooter = true })
                .environmentObject(state)
        }
        .sheet(isPresented: $state.showAddScanner, onDismiss: addClosed) {
            addScannerSheet
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

    @ViewBuilder
    private var addScannerSheet: some View {
        if let backend = state.addressBackend {
            AddScannerView(checker: backend, onAdded: added, onClose: closeAdd)
        }
    }

    private func troubleshooterClosed() {
        if addAfterTroubleshooter {
            addAfterTroubleshooter = false
            state.showAddScanner = true
        }
    }

    private func added(_ deviceID: String) {
        addedID = deviceID
        state.showAddScanner = false
    }

    private func closeAdd() {
        state.showAddScanner = false
    }

    private func addClosed() {
        guard let id = addedID else { return }
        addedID = nil
        let appState = state
        appState.leaveIdCard { appState.userSelectDevice(id) }
    }

    private var rowHelp: String {
        state.isBusy ? String(localized: "Wait for the scan to finish") : ""
    }

    /// Only the selected scanner has a connection to report. A busy row keeps the plain look: the scan
    /// runs on a connected scanner.
    private func status(of id: String) -> DeviceRow.Status? {
        guard id == state.selectedDeviceID, !state.isBusy else { return nil }
        if state.isConnecting { return .connecting }
        return state.isConnected ? nil : .failed
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
    let status: Status?
    let retry: () -> Void

    enum Status { case connecting, failed }

    var body: some View {
        HStack(spacing: 8) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(nameStyle)
                caption
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if status == .failed {
                    Button("Retry", action: retry)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help("Try to connect to this scanner again")
                        .accessibilityLabel(Text("Retry connecting to \(device.name)"))
                }
            }
            if status == .connecting {
                Spacer(minLength: 0)
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var icon: some View {
        if status == .failed {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .frame(width: 22)
                .accessibilityHidden(true)
        } else {
            Image(systemName: device.isDemo ? "sparkles.rectangle.stack" : "scanner")
                .foregroundStyle(.secondary)
                .frame(width: 22)
        }
    }

    @ViewBuilder private var caption: some View {
        switch status {
        case .connecting: Text("Connecting…")
        case .failed: Text("Not connected - Click to retry")
        case nil: transport
        }
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
