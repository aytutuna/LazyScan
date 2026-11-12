#if os(iOS)
import LazyScanKit
import CoreGraphics
import SwiftUI
import UIKit

/// A page drawn large: the picture the queue holds until its preview is read from the spool file, and that
/// picture again after a memory warning. The preview is kept with the page it was read for, so a slow read
/// of an earlier page or turn never shows over a newer one.
struct SharpPageImage: View {
    let page: ScannedPage
    @State private var preview: (key: String, image: CGImage)?

    private var key: String {
        "\(page.id.uuidString) \(page.fileURL?.lastPathComponent ?? "") \(page.rotationQuarterTurns)"
    }

    var body: some View {
        let current: String = key
        let shown: CGImage = preview?.key == current ? (preview?.image ?? page.image) : page.image
        Image(shown, scale: 1, label: Text("Last scan"))
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .task(id: current) {
                let source: ScannedPage = page
                let image: CGImage? = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                    QueuePreview.image(of: source)
                }.value
                if !Task.isCancelled, let image {
                    preview = (current, image)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { (_: Notification) in
                preview = nil
            }
    }
}
#endif
