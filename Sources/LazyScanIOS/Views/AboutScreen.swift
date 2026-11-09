#if os(iOS)
import LazyScanKit
import LazyScanModel
import SwiftUI

/// About: the app's name and version, what it is built with, and where scans stay. Licences is beside it in
/// Help and about.
struct AboutScreen: View {
    var body: some View {
        let info: [String: Any]? = Bundle.main.infoDictionary
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lazy Scan")
                        .font(.headline)
                    Text(IOSSettingsText.version(info))
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .accessibilityIdentifier("about.version")
                }
                .accessibilityElement(children: .combine)
            }
            Section {
                Text(IOSSettingsText.aboutBuiltWith)
                Text(IOSSettingsText.aboutPrivacy)
            }
        }
        .navigationTitle(IOSSettingsText.aboutLabel)
    }
}

/// The licence texts of DocAligner and ONNX Runtime, as they go with the app (`FastViTCornerModel.licence`).
struct LicencesScreen: View {
    var body: some View {
        List {
            licence("DocAligner", file: "DocAligner-LICENSE", id: "licences.docaligner")
            licence("ONNX Runtime", file: "ONNXRuntime-LICENSE", id: "licences.onnxruntime")
        }
        .navigationTitle(IOSSettingsText.licencesLabel)
    }

    private func licence(_ title: String, file: String, id: String) -> some View {
        Section(title) {
            Text(FastViTCornerModel.licence(file) ?? IOSSettingsText.licenceMissing)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .accessibilityIdentifier(id)
        }
    }
}
#endif
