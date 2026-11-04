#if os(macOS)
import LazyScanKit
import SwiftUI

/// The banner under the tab bar while a `.lsdoc` opened by hand is offered (`AppState.pendingPackage`):
/// "Opened Receipt.lsdoc: 3 pages", Add to pages, Open as new and a close button that drops the offer.
/// The two buttons wait while something runs or a review is open. Twin of the Windows package banner.
struct PackageBannerView: View {
    @EnvironmentObject var state: AppState

    let package: PendingPackage
    /// Open as new asks first while it would drop queued pages (the replace alert), as the iPhone does.
    @State private var asksReplace = false

    var body: some View {
        let pageCount: Int = state.scannedPages.count
        let replaceTitle: String = L10n.plural(pageCount, one: "Replace the page in the queue?",
                                               other: "Replace the {0} pages in the queue?")
        let replaceLine: String = L10n.plural(pageCount,
                                              one: "It has not been saved. “{1}” opens in its place.",
                                              other: "They have not been saved. “{1}” opens in their place.",
                                              package.fileName)
        let discardLabel: String = L10n.plural(pageCount, one: "Discard {0} page", other: "Discard {0} pages")
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 15))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                .accessibilityHidden(true)
            Text(PackageText.openedMessage(package.fileName, pageCount: package.pageCount))
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Group {
                Button(PackageText.addToPages) { state.addPendingPackageToPages() }
                    .help(state.isStackUnderWay ? DocumentSides.notWhileTurningOverReason
                        : String(localized: "Add the pages after the pages in the queue"))
                Button(PackageText.openAsNew) { openAsNew() }
                    .help(state.isStackUnderWay ? DocumentSides.notWhileTurningOverReason
                        : String(localized: "Clear the queue and open the document's pages in it"))
            }
            .disabled(!state.canIngest)
            Button {
                state.dismissPendingPackage()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close without adding the pages")
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .alert(replaceTitle, isPresented: $asksReplace) {
            Button(discardLabel, role: .destructive) { state.openPendingPackageAsNew() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(replaceLine)
        }
    }

    private func openAsNew() {
        // Where the settings collect no pages the click only says why, and the queue stays.
        if state.canTakePhonePages && !state.scannedPages.isEmpty {
            asksReplace = true
        } else {
            state.openPendingPackageAsNew()
        }
    }
}
#endif
