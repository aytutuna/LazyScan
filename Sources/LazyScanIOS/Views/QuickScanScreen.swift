#if os(iOS)
import LazyScanKit
import CoreGraphics
import ImageIO
import SwiftUI
import UIKit
import VisionKit

/// Quick scan's screen, full screen once a shot's page is in (`AppState.quickScanPage`): the page, with
/// Live Text where the device has it (press on the text to select part of it, `LiveTextImageView`), Save
/// JPEG, Copy text (the whole page's text, `OCRService`) and Discard. It closes once the page is saved or
/// discarded.
struct QuickScanScreen: View {
    @ObservedObject var model: IOSQuickScanModel
    @EnvironmentObject private var state: AppState
    @State private var asksDiscard: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    Color(uiColor: .secondarySystemBackground)
                    if let image = model.image {
                        if model.offersLiveText {
                            LiveTextImageView(image: image)
                                .padding(12)
                                .accessibilityLabel(Text("Page"))
                                .accessibilityIdentifier("quick.image")
                        } else {
                            ZoomablePage(image: image, isShown: true)
                                .padding(12)
                                .accessibilityLabel(Text("Page"))
                                .accessibilityIdentifier("quick.image")
                        }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Text(StatusLine.shown(state.statusMessage, state.statusDetail, deviceName: nil, reviewShown: true, savedShown: false))
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                        .accessibilityIdentifier("quick.status")
                    HStack(spacing: 12) {
                        Button {
                            model.copyText()
                        } label: {
                            Label(IOSQuickScanModel.copyTextLabel, systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!model.canAct)
                        .accessibilityIdentifier("quick.copy")
                        Button {
                            model.save()
                        } label: {
                            Text(model.saveLabel)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canAct)
                        .accessibilityIdentifier("quick.save")
                    }
                }
                .padding(16)
            }
            .navigationTitle(IOSQuickScanModel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(IOSQuickScanModel.discardLabel, role: .destructive) {
                        asksDiscard = true
                    }
                    .disabled(!model.canAct)
                    .accessibilityIdentifier("quick.discard")
                }
                ToolbarItem(placement: .primaryAction) {
                    if state.isBusy {
                        ProgressView()
                    }
                }
            }
        }
        .alert(IOSQuickScanModel.discardTitle, isPresented: $asksDiscard) {
            Button(IOSQuickScanModel.discardLabel, role: .destructive) {
                model.discard()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(IOSQuickScanModel.discardLine)
        }
        .modifier(ErrorAlert(state: state))
    }
}

/// The page with Live Text over it: VisionKit reads its text and codes once, and a press on the text selects it as in
/// Photos (copy, look up, translate are the system's own menu).
struct LiveTextImageView: UIViewRepresentable {
    let image: CGImage

    func makeCoordinator() -> LiveTextCoordinator {
        LiveTextCoordinator()
    }

    func makeUIView(context: Context) -> ZoomingImageView {
        let view: ZoomingImageView = ZoomingImageView()
        view.show(image)
        view.imageView.isUserInteractionEnabled = true
        let interaction: ImageAnalysisInteraction = ImageAnalysisInteraction()
        interaction.preferredInteractionTypes = .automatic
        view.imageView.addInteraction(interaction)
        context.coordinator.analyze(image, interaction: interaction)
        return view
    }

    func updateUIView(_ uiView: ZoomingImageView, context: Context) {}

    static func dismantleUIView(_ uiView: ZoomingImageView, coordinator: LiveTextCoordinator) {
        coordinator.cancel()
    }
}

/// Reads the page's text and codes for Live Text once, off the screen's way; dropped when the view goes.
@MainActor
final class LiveTextCoordinator {
    private var analysis: Task<Void, Never>?
    private var analyzed: CGImage?
    var interaction: ImageAnalysisInteraction?

    /// Reads a page not read yet; a page shown again as it is keeps its reading.
    func analyzeIfNew(_ image: CGImage) {
        guard let interaction, image !== analyzed else { return }
        analyzed = image
        interaction.analysis = nil
        analyze(image, interaction: interaction)
    }

    func analyze(_ image: CGImage, interaction: ImageAnalysisInteraction) {
        analysis?.cancel()
        analysis = Task { @MainActor [weak interaction] in
            let analyzer: ImageAnalyzer = ImageAnalyzer()
            let configuration: ImageAnalyzer.Configuration = ImageAnalyzer.Configuration([.text, .machineReadableCode])
            guard let result = try? await analyzer.analyze(image, orientation: .up, configuration: configuration) else {
                return
            }
            if Task.isCancelled { return }
            interaction?.analysis = result
        }
    }

    func cancel() {
        analysis?.cancel()
        analysis = nil
        if interaction?.analysis == nil {
            analyzed = nil
        }
    }
}
#endif
