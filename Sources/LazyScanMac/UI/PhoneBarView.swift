#if os(macOS)
import AppKit
import LazyScanKit
import SwiftUI

/// The bar under the tab bar when a paired phone's document was added to the queue or waits for it
/// (`AppState.phoneBarMessage`), with a close button, and the phone documents that were cancelled or
/// could not be added (`AppState.keptPhoneDocuments`) with Add Now and Discard. The message is announced,
/// and the Dock icon bounces once when the app is in the background. Twin of the Windows phone bar
/// (MainWindow.Phone.cs).
struct PhoneBarView: View {
    @EnvironmentObject var state: AppState

    let message: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "iphone")
                .font(.system(size: 15))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                if let message {
                    Text(message)
                        .font(.callout)
                        .lineLimit(2)
                        .frame(minHeight: 30, alignment: .leading)
                }
                if !state.keptPhoneDocuments.isEmpty {
                    waitingList
                }
            }
            Spacer(minLength: 8)
            if message != nil {
                Button {
                    state.dismissPhoneBar()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close")
                .accessibilityLabel("Close")
                .frame(height: 30)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .onAppear { arrived(message) }
        .onChange(of: message) { _, changed in arrived(changed) }
    }

    private var waitingList: some View {
        let kept: [KeptPhoneDocument] = state.keptPhoneDocuments
        let rowsHeight: CGFloat = CGFloat(min(kept.count, 4)) * 30
        return DisclosureGroup(isExpanded: $state.keptPhoneDocumentsOpen) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(kept) { document in
                        waitingRow(document)
                    }
                }
            }
            .frame(height: rowsHeight)
        } label: {
            Text("Waiting (\(kept.count))")
                .font(.callout)
                .accessibilityLabel(CompanionHostText.keptListLabel(count: kept.count))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Waiting documents from phones")
        .accessibilityIdentifier("phoneWaitingList")
    }

    private func waitingRow(_ document: KeptPhoneDocument) -> some View {
        let pages: Int = document.package.pageCount
        let name: String = document.phoneName
        return HStack(spacing: 8) {
            Text(CompanionHostText.keptRowText(pageCount: pages, phoneName: name))
                .font(.callout)
                .accessibilityLabel(CompanionHostText.keptRowText(pageCount: pages, phoneName: name))
            Spacer(minLength: 8)
            Button("Add Now") {
                state.addKeptPhoneDocument(document)
            }
            .help("Add these pages to the queue now")
            .accessibilityLabel(CompanionHostText.keptAddLabel(pageCount: pages, phoneName: name))
            .accessibilityIdentifier("phoneWaitingAddNow")
            Button("Discard") {
                state.discardKeptPhoneDocument(document)
            }
            .help("Delete this document from this Mac without adding it")
            .accessibilityLabel(CompanionHostText.keptDiscardLabel(pageCount: pages, phoneName: name))
            .accessibilityIdentifier("phoneWaitingDiscard")
        }
        .frame(height: 30)
        .accessibilityElement(children: .contain)
    }

    private func arrived(_ text: String?) {
        guard let text else { return }
        AccessibilityNotification.Announcement(text).post()
        if !NSApp.isActive { _ = NSApp.requestUserAttention(.informationalRequest) }
    }
}
#endif
