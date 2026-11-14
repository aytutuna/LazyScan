#if os(macOS)
import LazyScanKit
import SwiftUI

/// The question before Mail or the share sheet gets files over about 20 MB (`AppState.largeSendNotice`):
/// Save smaller, when the pages are still held, Send anyway, or Cancel. A window's alert cannot show over
/// an open sheet, so it waits (`enabled`) while a review sheet is up.
private struct LargeFilesAlert: ViewModifier {
    @ObservedObject var state: AppState
    let enabled: Bool

    func body(content: Content) -> some View {
        let title: String = state.largeSendNotice?.title ?? ""
        content
            .alert(title, isPresented: shown, presenting: state.largeSendNotice) { (notice: LargeSendNotice) in
                if notice.canSaveSmaller {
                    Button("Save smaller") {
                        state.saveSmaller(notice)
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("largefiles.saveSmaller")
                }
                Button("Send anyway") {
                    state.sendLargeAnyway(notice)
                }
                .accessibilityIdentifier("largefiles.sendAnyway")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("largefiles.cancel")
            } message: { (notice: LargeSendNotice) in
                Text(notice.message)
            }
    }

    private var shown: Binding<Bool> {
        let appState: AppState = state
        let allowed: Bool = enabled
        return Binding<Bool>(
            get: { allowed && appState.largeSendNotice != nil },
            set: { (isShown: Bool) in
                if !isShown {
                    appState.largeSendNotice = nil
                }
            })
    }
}

extension View {
    func largeFilesAlert(_ state: AppState, enabled: Bool = true) -> some View {
        modifier(LargeFilesAlert(state: state, enabled: enabled))
    }
}
#endif
