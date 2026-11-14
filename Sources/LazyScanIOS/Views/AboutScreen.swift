#if os(iOS)
import LazyScanKit
import LazyScanModel
import SwiftUI

/// About: the app's name and version, what it is built with, and where scans stay. Licenses is beside it in
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

/// The licence texts of DocAligner and ONNX Runtime and the third-party notices, as they go with the app (`FastViTCornerModel.licence`).
struct LicensesScreen: View {
    var body: some View {
        List {
            licence("DocAligner", file: "DocAligner-LICENSE", id: "licences.docaligner")
            licence("ONNX Runtime", file: "ONNXRuntime-LICENSE", id: "licences.onnxruntime")
            licence("Third-party notices", file: "THIRD-PARTY-NOTICES", id: "licences.thirdparty")
            licence("ONNX Runtime notices", file: "ONNXRuntime-THIRD-PARTY-NOTICES", id: "licences.onnxnotices")
        }
        .navigationTitle(IOSSettingsText.licencesLabel)
    }

    private func licence(_ title: LocalizedStringKey, file: String, id: String) -> some View {
        Section(title) {
            Text(FastViTCornerModel.licence(file) ?? IOSSettingsText.licenceMissing)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .accessibilityIdentifier(id)
        }
    }
}
#endif
