#if os(iOS)
import LazyScanKit
import SwiftUI

/// The sections of the Options sheet, the same on both tabs: the Type (a menu of the kinds the tab offers,
/// `IOSShell.cameraKinds` on the camera; picking one goes to `onType`, which asks what a kind's pick does),
/// the Book's way and Photos' restore under it for those types, then everything about what is saved while
/// the pages are saved here (`IOSShell.offersSave`: `ExportOptions`, After saving included), and last the
/// actions on the pages queued: adding them to a PDF picked in Files (or going back to saving new files),
/// Email, Print, sharing them as a Lazy Scan document and, with a computer paired, sending them to it. Each
/// action closes the sheet first (`onAction`), since what it opens cannot show over it; they are dimmed
/// while nothing is queued or a share or a send reads the queue (`blocked`).
struct OptionsSections: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var importer: IOSImportSession
    @AppStorage(IOSShell.scanModeKey) private var mode: IOSScanMode = .camera
    let blocked: Bool
    let onType: (IOSScanKind) -> Void
    let onAction: (OptionsAction) -> Void

    var body: some View {
        let current: IOSScanKind = IOSShell.shownKind(state.settings)
        let kinds: [IOSScanKind] = mode == .camera ? IOSShell.cameraKinds : IOSScanKind.allCases
        let tiles: [IOSKindTile] = IOSShell.kindTiles(state.taskCards, current: current, order: kinds)
        Section {
            typeMenu(tiles, current: current)
        } footer: {
            if let line = IOSShell.unavailableKindsLine(tiles) {
                Text(line)
                    .accessibilityIdentifier("kinds.unavailable")
            }
        }
        if state.activeTask == .book {
            Section {
                TaskWayPicker()
            } header: {
                Text("Book")
            }
        }
        if current == .photos {
            Section {
                RestoreToggle()
            } header: {
                Text("Photos")
            }
        }
        if IOSShell.offersSave(state.settings, pageCount: state.scannedPages.count) {
            ExportOptions()
        }
        Section {
            actions
        }
    }

    private func title(_ kind: IOSScanKind) -> String {
        mode == .camera ? kind.cameraTitle : kind.title
    }

    private func typeMenu(_ tiles: [IOSKindTile], current: IOSScanKind) -> some View {
        Menu {
            ForEach(tiles) { (tile: IOSKindTile) in
                let kind: IOSScanKind = tile.kind
                let available: Bool = tile.availability.isAvailable
                Button {
                    onType(kind)
                } label: {
                    if tile.isCurrent {
                        Label(title(kind), systemImage: "checkmark")
                    } else {
                        Text(title(kind))
                    }
                }
                .disabled(!available)
                .accessibilityHint(Text(available ? kind.subtitle : String(localized: "\(kind.subtitle). Not available: \(tile.availability.reason ?? "")")))
                .accessibilityIdentifier("type.\(kind.rawValue)")
            }
        } label: {
            HStack(spacing: 8) {
                Text("Type")
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 8)
                Text(title(current))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .disabled(blocked || importer.isImporting)
        .accessibilityLabel(Text("Type"))
        .accessibilityValue(Text(title(current)))
        .accessibilityIdentifier("options.type")
    }

    @ViewBuilder
    private var actions: some View {
        let canSave: Bool = SavePlan.make(state.scannedPages, options: state.settings.document).pageCount > 0
        let idle: Bool = !blocked && !importer.isImporting
        if IOSShell.offersPDFOptions(state.settings) || state.appendTarget != nil {
            appendRows(canSave: canSave && idle)
        }
        Button {
            onAction(.email)
        } label: {
            Label("Email\u{2026}", systemImage: "envelope")
        }
        .disabled(!canSave || !idle)
        .accessibilityIdentifier("save.email")
        Button {
            onAction(.print)
        } label: {
            Label("Print\u{2026}", systemImage: "printer")
        }
        .disabled(!canSave || !idle)
        .accessibilityIdentifier("save.print")
        Button {
            onAction(.share)
        } label: {
            Label(IOSShell.sharePackageLabel, systemImage: "square.and.arrow.up")
        }
        .disabled(state.scannedPages.isEmpty || !idle)
        .accessibilityIdentifier("share.package")
        if IOSShell.offersSendToComputer(state.settings, status: state.companionStatus) {
            Button {
                onAction(.send)
            } label: {
                Label(IOSCompanionText.sendButton, systemImage: "laptopcomputer")
            }
            .disabled(state.scannedPages.isEmpty || !idle)
            .accessibilityIdentifier("send.computer")
            if state.companionOutboxCount > 0 {
                Button(IOSCompanionText.waiting(state.companionOutboxCount)) {}
                    .disabled(true)
                    .accessibilityIdentifier("send.waiting")
            }
        }
    }

    /// Add to an existing PDF, as a new PDF again while one is picked (After saving's steps included, as Save
    /// runs them), and going back to saving new files. Word and text queues save their own format once the
    /// target is cleared.
    @ViewBuilder
    private func appendRows(canSave: Bool) -> some View {
        if state.settings.format.queueFormat == .pdf, state.appendTarget != nil {
            Button {
                onAction(.saveAsNew)
            } label: {
                Label(PDFAppender.saveAsNewLabel, systemImage: "doc.badge.arrow.up")
            }
            .disabled(!canSave)
            .accessibilityIdentifier("save.new")
        }
        Button {
            onAction(.addToPDF)
        } label: {
            Label(PDFAppender.buttonLabel, systemImage: "doc.badge.plus")
        }
        .disabled(!canSave)
        .accessibilityHint(Text(PDFAppender.buttonHint))
        .accessibilityIdentifier("append.button")
        if let target = state.appendTarget {
            Button {
                state.clearAppendTarget()
            } label: {
                Label(ScanScreen.clearTargetLabel(target), systemImage: "xmark.circle")
            }
            .accessibilityIdentifier("append.target.clear")
        }
    }
}

/// What the Options sheet's action rows ask the scan screen to do once the sheet has closed.
enum OptionsAction {
    case saveAsNew
    case addToPDF
    case email
    case print
    case share
    case send
}
#endif
