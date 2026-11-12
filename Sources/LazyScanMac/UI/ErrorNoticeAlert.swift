#if os(macOS)
import LazyScanKit
import SwiftUI

/// The alert for `AppState.errorMessage`. A window's alert cannot show over an open sheet, so the
/// review sheets carry their own and the window's waits (`enabled`) while one is open.
private struct ErrorNoticeAlert: ViewModifier {
    @EnvironmentObject var state: AppState
    let enabled: Bool

    /// The error as its title and message; a refusal under its own title.
    private var notice: ProblemNotice {
        let message: String = state.errorMessage ?? ""
        guard let title: String = state.errorTitle else { return ScannerProblems.notice(message) }
        return ProblemNotice(title: title, message: message.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var isShown: Binding<Bool> {
        Binding(
            get: { enabled && state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil; state.errorSuggestsTroubleshooter = false } }
        )
    }

    func body(content: Content) -> some View {
        content.alert(notice.title, isPresented: isShown) {
            // A scanner that would not connect or scan: the alert offers the troubleshooter.
            if state.errorSuggestsTroubleshooter {
                Button("Troubleshoot\u{2026}") { state.showTroubleshooter = true }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice.message)
        }
    }
}

extension View {
    func errorNoticeAlert(enabled: Bool = true) -> some View {
        modifier(ErrorNoticeAlert(enabled: enabled))
    }
}
#endif
