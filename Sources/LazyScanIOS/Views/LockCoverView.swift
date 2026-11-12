#if os(iOS)
import SwiftUI
import UIKit

/// What the window's cover shows while the app is locked (`PrivacyCover`).
struct LockCoverView: View {
    @ObservedObject var lock: IOSAppLock

    var body: some View {
        let failedLine: String = String(localized: "Couldn't unlock. Try again.")
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(String(localized: "Lazy Scan is locked"))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            if lock.state == .failed {
                Text(failedLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("lock.failed")
            }
            Button(String(localized: "Unlock")) {
                Task {
                    await lock.unlock()
                }
            }
            .buttonStyle(.borderedProminent)
            .frame(minHeight: 44)
            .keyboardShortcut(.defaultAction)
            .disabled(lock.state == .unlocking)
            .accessibilityIdentifier("lock.unlock")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .onChange(of: lock.state) { (_: IOSAppLock.State, state: IOSAppLock.State) in
            if state == .failed {
                UIAccessibility.post(notification: .announcement, argument: failedLine)
            }
        }
    }
}
#endif
