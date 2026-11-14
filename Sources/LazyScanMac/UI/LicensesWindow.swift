#if os(macOS)
import LazyScanModel
import SwiftUI

/// Help > Lazy Scan Help and Licenses. No help book is registered, so the default help item only says help isn't available.
struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Link("Lazy Scan Help", destination: URL(string: "https://alazy.app/scan/#support")!)
            Divider()
            Button("Licenses") { openWindow(id: "licenses") }
        }
    }
}

/// The third-party notices and the ONNX Runtime notices, as they go with the app in its Resources.
struct LicensesWindow: View {
    @State private var notices = ""
    @State private var onnxNotices = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(notices)
                Divider()
                Text("ONNX Runtime notices")
                    .accessibilityAddTraits(.isHeader)
                Divider()
                Text(onnxNotices)
            }
            .font(.system(.footnote, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .frame(minWidth: 400, minHeight: 300)
        .onAppear {
            notices = FastViTCornerModel.licence("THIRD-PARTY-NOTICES") ?? String(localized: "License text missing")
            onnxNotices = FastViTCornerModel.licence("ONNXRuntime-THIRD-PARTY-NOTICES") ?? String(localized: "License text missing")
        }
    }
}
#endif
