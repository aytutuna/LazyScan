#if os(iOS)
import LazyScanKit
import CoreGraphics
import SwiftUI

/// The ID card's review on the iPhone and iPad (I13), a port of the Mac's `IdCardReviewView`: the privacy
/// line (`IdCardSteps.privacyNote`), each side with Rotate, Fix crop (the touch corner editor on the photo
/// it was cut from) and Scan again, its note (what to check, or the glare hint), a missing back with Scan
/// the back, Swap sides, the page both go on with what it holds and whether it is at real size, then Paper,
/// Save as and Also save sides as images in the scroll view, with Discard, Print and Save pinned. The card stays in memory only until it is saved or
/// discarded (AppState+IdCard.swift); Print prints both sides at real size over AirPrint
/// (`IOSPrintService`, I16). It shows the error alert itself,
/// since the root's cannot show over it. Discard asks first.
struct IdCardReviewScreen: View {
    @EnvironmentObject private var state: AppState
    let model: IOSIdCardReviewModel
    /// The phone's mode: in camera mode the camera took the sides, so their buttons say Take, not Scan.
    @AppStorage(IOSShell.scanModeKey) private var mode: IOSScanMode = .camera
    @State private var cropping: IOSCropRequest?
    @State private var preparing: Bool = false
    @State private var asksDiscard: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(IdCardSteps.privacyNote, systemImage: "lock.shield")
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                            .accessibilityHint(Text(IOSReviewText.privacyHelp))
                            .accessibilityIdentifier("idcard.privacy")
                        SideCard(side: .front, photo: state.idCardFront, note: state.idCardFrontNote,
                                 busy: state.isBusy || preparing, camera: mode == .camera,
                                 onRotate: { state.rotateIdCardSide(.front) },
                                 onCrop: { fixCrop(.front) },
                                 onRetake: { state.retakeIdCardSide(.front) })
                        SideCard(side: .back, photo: state.idCardBack, note: state.idCardBackNote,
                                 busy: state.isBusy || preparing, camera: mode == .camera,
                                 onRotate: { state.rotateIdCardSide(.back) },
                                 onCrop: { fixCrop(.back) },
                                 onRetake: { state.retakeIdCardSide(.back) })
                        if state.idCardBack != nil {
                            Button {
                                state.swapIdCardSides()
                            } label: {
                                Label(IOSReviewText.swapLabel, systemImage: "arrow.up.arrow.down")
                            }
                            .buttonStyle(.bordered)
                            .disabled(state.isBusy)
                            .accessibilityIdentifier("idcard.swap")
                        }
                        pagePreview
                        settingsCard
                    }
                    .padding(16)
                }
                Divider()
                footer
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(IOSReviewText.idCardTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(IOSReviewText.discardLabel, role: .destructive) {
                        asksDiscard = true
                    }
                    .disabled(state.isBusy)
                    .accessibilityHint(Text(discardHint))
                    .accessibilityIdentifier("idcard.discard")
                }
            }
            .confirmationDialog(IOSPresetText.discardTitle, isPresented: $asksDiscard, titleVisibility: .visible) {
                Button(IOSReviewText.discardLabel, role: .destructive) {
                    state.discardIdCard()
                }
                .accessibilityIdentifier("idcard.confirmDiscard")
            } message: {
                Text(IOSPresetText.discardLine)
            }
        }
        .fullScreenCover(item: $cropping) { (crop: IOSCropRequest) in
            CornerEditorView(request: crop.request, onAnswer: { (answer: PhotoCornersAnswer) -> Void in
                finishCrop(crop, answer: answer)
            }, fixesCrop: true)
        }
        .modifier(ErrorAlert(state: state))
    }

    /// The page the sides go on, small, with what it holds and whether it is at real size.
    private var pagePreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let page = state.idCardPreview {
                    Image(decorative: page, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Rectangle()
                        .fill(Color.white)
                        .aspectRatio(8.5 / 11, contentMode: .fit)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 320)
            .background(Color.white)
            .overlay(Rectangle().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
            .accessibilityElement()
            .accessibilityLabel(Text(IOSReviewText.pagePreviewName))
            .accessibilityValue(Text(state.idCardLayoutCaption))
            .accessibilityIdentifier("idcard.page")
            Text(state.idCardLayoutCaption)
                .font(.caption)
                .foregroundStyle(Color.secondary)
                .accessibilityIdentifier("idcard.caption")
            if let warning = state.idCardSizeWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Paper, Save as and the toggles, as rows of one card.
    private var settingsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text(IOSReviewText.paperLabel)
                Spacer(minLength: 8)
                Picker(IOSReviewText.paperLabel, selection: paper) {
                    ForEach(IdCardPaper.allCases) { (choice: IdCardPaper) in
                        Text(state.idCardPaperChoiceLabel(choice)).tag(choice)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityIdentifier("idcard.paper")
            }
            .padding(.vertical, 6)
            Divider()
            HStack {
                Text(IOSReviewText.saveAsLabel)
                Spacer(minLength: 8)
                Picker(IOSReviewText.saveAsLabel, selection: format) {
                    ForEach(pageFormats) { (choice: OutputFormat) in
                        Text(choice.label).tag(choice)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .accessibilityIdentifier("idcard.format")
            }
            .padding(.vertical, 6)
            Divider()
            Toggle(IOSReviewText.sidesAsImagesLabel, isOn: sidesAsImages)
                .padding(.vertical, 6)
                .accessibilityIdentifier("idcard.sides")
            if IOSShell.reviewOffersPassword(state.settings) {
                Divider()
                Toggle(PDFProtection.optionLabel, isOn: protect)
                    .disabled(IOSPDFOptions.archivalShown(state.settings.output))
                    .padding(.vertical, 6)
                    .accessibilityHint(Text(PDFProtection.optionHint))
                    .accessibilityIdentifier("idcard.password")
            }
        }
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .secondarySystemGroupedBackground)))
        .disabled(state.isBusy)
    }

    /// The progress of a save, Print and Save.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state.isBusy {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(state.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                }
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: 12) {
                Button {
                    state.printIdCard()
                } label: {
                    Label(IOSReviewText.printLabel, systemImage: "printer")
                }
                .buttonStyle(.bordered)
                .disabled(state.idCardFront == nil || state.isBusy)
                .accessibilityHint(Text(IOSReviewText.printIdCardHint))
                .accessibilityIdentifier("idcard.print")
                Button {
                    state.saveIdCard()
                } label: {
                    Text(IOSReviewText.idCardSaveTitle(state.settings.format))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.idCardFront == nil || state.isBusy)
                .accessibilityIdentifier("idcard.save")
            }
        }
        .padding(16)
    }

    /// The formats a card is saved in: a PDF or a picture.
    private var pageFormats: [OutputFormat] {
        var formats: [OutputFormat] = []
        for format in OutputFormat.allCases where format.pageFormat == format {
            formats.append(format)
        }
        return formats
    }

    /// What Discard deletes: the front alone when the back was skipped.
    private var discardHint: String {
        state.idCardBack == nil ? IOSReviewText.discardFrontHint : IOSReviewText.discardHint
    }

    private var paper: Binding<IdCardPaper> {
        let appState: AppState = state
        return Binding<IdCardPaper>(get: { appState.settings.taskOptions.idCardPaper },
                                    set: { (choice: IdCardPaper) in appState.setIdCardPaper(choice) })
    }

    /// A text format chosen elsewhere shows (and saves) as PDF here.
    private var format: Binding<OutputFormat> {
        let appState: AppState = state
        return Binding<OutputFormat>(get: { appState.settings.format.pageFormat },
                                     set: { (choice: OutputFormat) in appState.settings.format = choice })
    }

    private var protect: Binding<Bool> {
        let appState: AppState = state
        return Binding<Bool>(get: { appState.settings.output.protect },
                             set: { (on: Bool) in
                                 appState.settings.output = IOSPDFOptions.settingProtect(on, in: appState.settings.output)
                             })
    }

    private var sidesAsImages: Binding<Bool> {
        let appState: AppState = state
        return Binding<Bool>(get: { appState.settings.taskOptions.idCardSaveSidesAsImages },
                             set: { (on: Bool) in appState.settings.taskOptions.idCardSaveSidesAsImages = on })
    }

    /// Opens the corner editor on the photo `side` was cut from, once it is read.
    private func fixCrop(_ side: PageSide) {
        guard !preparing, !state.isBusy else { return }
        let held: DetectedPhoto? = side == .front ? state.idCardFront : state.idCardBack
        guard let photo = held else { return }
        preparing = true
        let review: IOSIdCardReviewModel = model
        let name: String = side == .front ? IOSReviewText.frontTitle : IOSReviewText.backTitle
        Task { @MainActor in
            let crop: IOSCropRequest? = await review.cropRequest(for: photo, name: name, number: 1, count: 1)
            preparing = false
            cropping = crop
        }
    }

    private func finishCrop(_ crop: IOSCropRequest, answer: PhotoCornersAnswer) {
        cropping = nil
        model.applyCrop(crop, answer: answer)
    }
}

/// One side of the card: its picture turned as the user turned it, the note about it, and Rotate, Fix crop
/// and Scan again; a missing back says so and offers to scan it. In camera mode the phone takes the sides,
/// so those two say Take again and Take the back.
private struct SideCard: View {
    let side: PageSide
    let photo: DetectedPhoto?
    let note: String?
    let busy: Bool
    let camera: Bool
    let onRotate: () -> Void
    let onCrop: () -> Void
    let onRetake: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var thumbnail: CGImage?

    private var title: String { side == .front ? IOSReviewText.frontTitle : IOSReviewText.backTitle }
    private var sideID: String { side == .front ? "front" : "back" }
    private var key: String {
        guard let held = photo else { return "none" }
        return "\(held.region.id.uuidString)-\(held.rotationQuarterTurns)"
    }
    private var againLabel: String { camera ? IOSReviewText.takeAgainLabel : IOSReviewText.scanAgainLabel }
    private var missingBackLabel: String { camera ? IOSReviewText.takeBackLabel : IOSReviewText.scanBackLabel }

    private var againSymbol: String { camera ? "camera" : "scanner" }

    private var actions: some View {
        let layout: AnyLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            action(IOSReviewText.rotateLabel, symbol: "rotate.right", id: "idcard.rotate.\(sideID)", run: onRotate)
            action(IOSReviewText.fixCropLabel, symbol: "crop", id: "idcard.crop.\(sideID)", run: onCrop)
            action(againLabel, symbol: againSymbol, id: "idcard.retake.\(sideID)", run: onRetake)
        }
        .disabled(busy)
    }

    private func action(_ word: String, symbol: String, id: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            let stacked: AnyLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(HStackLayout(spacing: 8))
                : AnyLayout(VStackLayout(spacing: 2))
            stacked {
                Image(systemName: symbol)
                Text(word)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(IOSReviewText.sideAction(word, side: side)))
        .accessibilityIdentifier(id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            if photo != nil {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.12))
                    if let picture = thumbnail {
                        Image(decorative: picture, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .padding(6)
                    }
                }
                .frame(height: 170)
                .accessibilityHidden(true)
                actions
                if let line = note {
                    Label(line, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("idcard.note.\(sideID)")
                }
            } else {
                Text(IOSReviewText.noBackLine)
                    .font(.callout)
                    .foregroundStyle(Color.secondary)
                Button(missingBackLabel, action: onRetake)
                    .buttonStyle(.bordered)
                    .disabled(busy)
                    .accessibilityIdentifier("idcard.scanBack")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .secondarySystemGroupedBackground)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
        .task(id: key) {
            guard let held = photo else {
                thumbnail = nil
                return
            }
            let image: CGImage = held.image
            let turns: Int = held.rotationQuarterTurns
            let small: CGImage = await Task.detached(priority: .userInitiated) { () -> CGImage in
                let reduced: CGImage = IOSIdCardReviewModel.thumbnail(image, maxSide: 500)
                return turns == 0 ? reduced : ImagePipeline.rotate(reduced, quarterTurns: turns)
            }.value
            thumbnail = small
        }
    }
}
#endif
