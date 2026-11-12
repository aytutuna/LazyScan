#if os(macOS)
import AppKit
import LazyScanKit
import SwiftUI

/// What adding a scanner by address needs of the network connection (`EsclScannerBackend`; tests pass a stand-in).
@MainActor
protocol MacAddressChecking: AnyObject {
    func checkAddress(_ address: ScannerAddress, firstUse: String?) async throws -> EsclAddressCheck
    func addAddress(_ address: ScannerAddress, capabilities: EsclCapabilities) -> String
    func trustCertificate(_ certificate: EsclCertificateError, deviceUuid: String?, name: String)
}

extension EsclScannerBackend: MacAddressChecking {}

/// "Add a network scanner": the address typed is read with the Windows rules and messages
/// (`ScannerAddress.tryParse`), then checked (a scanner must answer there) and added to escl-hosts.json. A
/// certificate the app has not seen before, and one that changed, are asked about (`certificateQuestion`), as the
/// Windows dialog does. Twin of the Windows `AddScannerWindow`.
@MainActor
final class MacAddScannerModel: ObservableObject {
    /// The address as typed.
    @Published var text: String = ""
    /// What the sheet says under the field: progress while checking, else why the address was not added.
    @Published private(set) var message: String?
    @Published private(set) var isChecking: Bool = false
    /// A certificate waiting for the user's answer.
    @Published private(set) var certificateQuestion: EsclCertificateError?
    /// The added scanner's device ID; nil until one was added.
    private(set) var addedDeviceID: String?

    private let checker: any MacAddressChecking
    private var answer: CheckedContinuation<Bool, Never>?
    private var check: Task<Bool, Never>?

    init(checker: any MacAddressChecking) {
        self.checker = checker
    }

    /// Checks and adds in the background (the Add button); `done` runs with true once added.
    func start(_ done: @escaping @MainActor (Bool) -> Void) {
        guard check == nil else { return }
        check = Task { @MainActor [weak self] () -> Bool in
            guard let self else { return false }
            let added: Bool = await self.add()
            self.check = nil
            done(added)
            return added
        }
    }

    /// The sheet closed: a check under way is abandoned and nothing is added or trusted after it.
    func cancel() {
        check?.cancel()
        check = nil
        answerCertificate(false)
    }

    /// The text changed: a message about the previous text no longer applies.
    func textChanged() {
        if !isChecking {
            message = nil
        }
    }

    /// Reads, checks and adds the typed address; true once it was added.
    func add() async -> Bool {
        guard !isChecking else { return false }
        var problem: String = ""
        guard let address = ScannerAddress.tryParse(text, error: &problem) else {
            message = problem
            return false
        }
        isChecking = true
        message = L10n.t("Connecting to {0}…", address)
        let added: Bool = await checkAndAdd(address, https: address.httpsFallback(typed: text))
        isChecking = false
        return added
    }

    private func checkAndAdd(_ address: ScannerAddress, https: ScannerAddress?) async -> Bool {
        var address: ScannerAddress = address
        do {
            var result: EsclAddressCheck = try await checker.checkAddress(address, firstUse: nil)
            if Task.isCancelled {
                return false
            }
            // A bare host that did not answer over HTTP may serve eSCL over HTTPS.
            if result.noAnswer, let https {
                address = https
                message = L10n.t("Connecting to {0}…", address)
                result = try await checker.checkAddress(address, firstUse: nil)
                if Task.isCancelled {
                    return false
                }
            }
            // A new certificate is trusted once the scanner's UUID shows it is not a changed certificate
            // of a scanner trusted before; a changed one is asked about as such.
            var firstUseAsked: Bool = false
            var trusted: Bool = false
            while !trusted, let certificate = result.certificate, certificate.canTrust {
                message = L10n.t("Confirm the scanner's certificate to continue.")
                let answered: Bool = await ask(certificate)
                if Task.isCancelled {
                    return false
                }
                guard answered else {
                    message = L10n.t("The scanner was not added, because its certificate was not trusted.")
                    return false
                }
                message = L10n.t("Connecting to {0}…", address)
                if certificate.verdict == .unknown && !firstUseAsked {
                    firstUseAsked = true
                    result = try await checker.checkAddress(address, firstUse: certificate.fingerprint)
                } else {
                    checker.trustCertificate(certificate, deviceUuid: nil, name: certificate.deviceName)
                    trusted = true
                    result = try await checker.checkAddress(address, firstUse: nil)
                }
                if Task.isCancelled {
                    return false
                }
            }
            if let capabilities = result.capabilities {
                addedDeviceID = checker.addAddress(address, capabilities: capabilities)
                message = nil
                return true
            }
            message = result.certificate?.message ?? result.error ?? L10n.t("No scanner answered at {0}.", address)
            return false
        } catch {
            // Cancelled: the sheet is gone.
            message = nil
            return false
        }
    }

    private func ask(_ certificate: EsclCertificateError) async -> Bool {
        certificateQuestion = certificate
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            answer = continuation
        }
    }

    /// The user's answer about `certificateQuestion`: true trusts the certificate.
    func answerCertificate(_ trust: Bool) {
        certificateQuestion = nil
        guard let open = answer else { return }
        answer = nil
        open.resume(returning: trust)
    }
}

/// The texts of the certificate question: the Windows `CertificateTrustWindow`'s, for an address typed by hand.
enum MacCertificateText {
    static func title(_ certificate: EsclCertificateError) -> String {
        certificate.verdict == .changed ? L10n.t("Scanner certificate changed")
                                        : L10n.t("Trust the scanner at {0}?", certificate.authority)
    }

    static func trustButton(_ certificate: EsclCertificateError) -> String {
        certificate.verdict == .changed ? L10n.t("Trust the new certificate") : L10n.t("Trust and add")
    }

    private static func changedSentence(_ certificate: EsclCertificateError) -> String {
        guard let date: Date = certificate.previous?.trusted else {
            return L10n.t("The scanner identified itself with a different certificate from the one you trusted.")
        }
        return L10n.t("The scanner identified itself with a different certificate from the one you trusted on {0}.",
                      date.formatted(date: .numeric, time: .omitted))
    }

    static func message(_ certificate: EsclCertificateError) -> String {
        var lines: [String] = []
        if certificate.verdict == .changed {
            lines.append(changedSentence(certificate) + " "
                         + L10n.t("A firmware update or a reset of the scanner can change it, but so can another device on the network that pretends to be your scanner."))
            lines.append(L10n.t("Trust the new certificate only if you know why it changed. Otherwise choose Cancel and check the scanner."))
            if let previous = certificate.previous {
                lines.append(L10n.t("Trusted before") + "\n" + EsclCertificates.format(previous.fingerprint, bytesPerLine: 16))
            }
            lines.append(L10n.t("New fingerprint") + "\n" + EsclCertificates.format(certificate.fingerprint, bytesPerLine: 16))
        } else {
            lines.append(L10n.t("This scanner offers an encrypted connection and identifies itself with a certificate it made itself. macOS cannot vouch for such certificates; that is normal for scanners."))
            lines.append(L10n.t("Trust it if this is your scanner. Lazy Scan remembers the certificate and warns you if it ever changes."))
            lines.append(L10n.t("Fingerprint") + "\n" + EsclCertificates.format(certificate.fingerprint, bytesPerLine: 16))
        }
        return lines.joined(separator: "\n\n")
    }
}

/// The sheet of "Add by address": the address field, Add, and what the check found. Twin of the Windows
/// `AddScannerWindow`.
struct AddScannerView: View {
    @StateObject private var model: MacAddScannerModel
    let onAdded: (String) -> Void
    let onClose: () -> Void
    @FocusState private var focused: Bool
    @State private var showsHelp: Bool = false

    init(checker: any MacAddressChecking, onAdded: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        _model = StateObject(wrappedValue: MacAddScannerModel(checker: checker))
        self.onAdded = onAdded
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("Add a network scanner"))
                .font(.title2.weight(.semibold))
            lineWithHelp
            Text(L10n.t("Address"))
                .font(.headline)
                .padding(.top, 16)
            addressField
            resultRow
            buttons
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            focused = true
        }
        .onDisappear {
            model.cancel()
        }
        .onChange(of: model.text) { (_: String, _: String) in
            model.textChanged()
        }
        .onChange(of: model.isChecking) { (_: Bool, checking: Bool) in
            if !checking {
                focused = true
            }
        }
        .onChange(of: model.message) { (_: String?, message: String?) in
            announce(message)
        }
        .alert(alertTitle, isPresented: certificateShown, presenting: model.certificateQuestion) { (certificate: EsclCertificateError) in
            Button(MacCertificateText.trustButton(certificate), role: trustRole(certificate)) {
                model.answerCertificate(true)
            }
            Button(L10n.t("Cancel"), role: .cancel) {
                model.answerCertificate(false)
            }
        } message: { (certificate: EsclCertificateError) in
            Text(MacCertificateText.message(certificate))
        }
    }

    private var lineWithHelp: some View {
        HStack(spacing: 4) {
            Text(L10n.t("Enter the scanner's IP address or name."))
                .foregroundStyle(.secondary)
            Button {
                showsHelp = true
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(L10n.t("the scanner's address"))
            .popover(isPresented: $showsHelp) {
                Text(L10n.t("Most network scanners appear on their own. The address is on the scanner's screen or its network settings page. Forms: 192.168.1.50, scanner.local, 192.168.1.50:8080, https://192.168.1.50."))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 300, alignment: .leading)
                    .padding(12)
            }
        }
        .padding(.top, 4)
    }

    private var addressField: some View {
        TextField(L10n.t("e.g. 192.168.1.50 or scanner.local"), text: $model.text)
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .focused($focused)
            .disabled(model.isChecking)
            .onSubmit(add)
            .accessibilityLabel(L10n.t("Address"))
            .accessibilityHint(L10n.t("For example 192.168.1.50, scanner.local, 192.168.1.50:8080 or https://192.168.1.50"))
    }

    @ViewBuilder
    private var resultRow: some View {
        if let message = model.message {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if model.isChecking {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(L10n.t("Connecting"))
                } else {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(Color.red)
                        .accessibilityLabel(L10n.t("Problem"))
                }
                Text(message)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 14)
        }
    }

    private var buttons: some View {
        HStack {
            Spacer()
            Button(L10n.t("Cancel")) {
                model.cancel()
                onClose()
            }
            .keyboardShortcut(.cancelAction)
            Button(L10n.t("Add"), action: add)
                .keyboardShortcut(.defaultAction)
                .disabled(addDisabled)
        }
        .padding(.top, 16)
    }

    private var addDisabled: Bool {
        model.isChecking || model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var alertTitle: String {
        guard let certificate = model.certificateQuestion else { return "" }
        return MacCertificateText.title(certificate)
    }

    private var certificateShown: Binding<Bool> {
        let adding: MacAddScannerModel = model
        return Binding<Bool>(
            get: { adding.certificateQuestion != nil },
            set: { (shown: Bool) in
                if !shown {
                    Task { @MainActor in adding.answerCertificate(false) }
                }
            })
    }

    private func trustRole(_ certificate: EsclCertificateError) -> ButtonRole? {
        certificate.verdict == .changed ? .destructive : nil
    }

    private func announce(_ message: String?) {
        guard let message else { return }
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                             userInfo: [NSAccessibility.NotificationUserInfoKey.announcement: message])
    }

    private func add() {
        let done: (String) -> Void = onAdded
        let adding: MacAddScannerModel = model
        model.start { (added: Bool) in
            if added, let deviceID = adding.addedDeviceID {
                done(deviceID)
            }
        }
    }
}
#endif
