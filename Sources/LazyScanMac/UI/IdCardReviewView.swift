#if os(macOS)
import AppKit
import LazyScanKit
import CoreGraphics
import SwiftUI

/// Sheet shown once the sides of an ID card are scanned (or the back skipped): each side with its
/// turn, its crop (the crop editor, through `state.recropPhoto`) and scanning it again, swapping
/// them, the page both go on with what it holds and whether it is at real size, and saving: the
/// paper, the format and also saving each side as an image. Twin of the Windows ID card review
/// (MainWindow.xaml).
struct IdCardReviewView: View {
    @EnvironmentObject var state: AppState

    /// Side whose crop is being corrected manually (drives the editor sheet).
    @State private var editingPhoto: DetectedPhoto?
    /// Discard is asking before it drops the sides.
    @State private var asksDiscard = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Check the ID Card")
                    .font(.title2.bold())
                // Privacy: always shown, the full sentence on hover and for VoiceOver.
                Label(IdCardSteps.privacyNote, systemImage: "lock.shield")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .help(IdCardSteps.privacyHelp)
                    .accessibilityHint(Text(IdCardSteps.privacyHelp))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            Divider()

            ScrollView {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        IdCardSideCard(side: .front, title: String(localized: "Front"), photo: state.idCardFront, note: state.idCardFrontNote,
                                       busy: state.isBusy,
                                       onRotate: { state.rotateIdCardSide(.front) },
                                       onAdjustCrop: { editingPhoto = state.idCardFront },
                                       onRetake: { state.retakeIdCardSide(.front) })
                        IdCardSideCard(side: .back, title: String(localized: "Back"), photo: state.idCardBack, note: state.idCardBackNote,
                                       busy: state.isBusy,
                                       onRotate: { state.rotateIdCardSide(.back) },
                                       onAdjustCrop: { editingPhoto = state.idCardBack },
                                       onRetake: { state.retakeIdCardSide(.back) })
                        if state.idCardBack != nil {
                            Button {
                                state.swapIdCardSides()
                            } label: {
                                Label("Swap Sides", systemImage: "arrow.up.arrow.down")
                            }
                            .help("The sides were scanned the other way round")
                            .disabled(state.isBusy)
                        }
                    }
                    .frame(width: 300)

                    VStack(alignment: .leading, spacing: 8) {
                        Group {
                            if let page = state.idCardPreview {
                                Image(decorative: page, scale: 1)
                                    .resizable()
                                    .interpolation(.high)
                                    .scaledToFit()
                            } else {
                                Rectangle().fill(Color.white)
                                    .aspectRatio(8.5 / 11, contentMode: .fit)
                            }
                        }
                        .frame(height: 380)
                        .background(Color.white)
                        .overlay(Rectangle().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                        .accessibilityLabel("Page preview")
                        Text(state.idCardLayoutCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let warning = state.idCardSizeWarning {
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(width: 300, alignment: .leading)
                }
                .padding()
            }

            Divider()

            HStack(spacing: 12) {
                Picker("Paper", selection: Binding(
                    get: { state.settings.taskOptions.idCardPaper },
                    set: { state.setIdCardPaper($0) })) {
                    ForEach(IdCardPaper.allCases) { paper in
                        Text(state.idCardPaperChoiceLabel(paper)).tag(paper)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                // The card is a picture: a PDF or an image. A text format chosen in the inspector
                // shows (and saves) as PDF here.
                Picker("Save as", selection: Binding(
                    get: { state.settings.format.pageFormat },
                    set: { state.settings.format = $0 })) {
                    ForEach(OutputFormat.allCases.filter { $0.pageFormat == $0 }) { format in
                        Text(format.label).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                Toggle("Also save sides as images", isOn: $state.settings.taskOptions.idCardSaveSidesAsImages)
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Print\u{2026}") {
                    state.printIdCard()
                }
                .disabled(state.idCardFront == nil || state.isBusy || !state.hasPrinter)
                .help(state.hasPrinter
                      ? (state.copyPrinterName.map { String(localized: "Print at real size on \($0)") }
                         ?? String(localized: "Print at real size on the default printer"))
                      : PrintText.noPrinterMessage)
                if state.lazyPrintInstalled {
                    Button("Lazy Print") {
                        state.printIdCardWithLazyPrint()
                    }
                    .disabled(state.idCardFront == nil || state.isBusy)
                    .help("Open it in Lazy Print, then choose a printer and print")
                }
                Button("Discard") {
                    asksDiscard = true
                }
                .help(discardHelp)
                Button("Close") {
                    state.showIdCardReview = false
                }
                .keyboardShortcut(.cancelAction)
                .help("Keep the sides and close; Review in the settings column opens this again")
                Button(saveTitle) {
                    state.saveIdCard()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(state.idCardFront == nil || state.isBusy)
                .accessibilityHint(Text(saveHelp))
            }
            .disabled(state.isBusy)
            .padding()
        }
        .frame(minWidth: 700, idealWidth: 760, maxWidth: .infinity,
               minHeight: 520, idealHeight: 620, maxHeight: .infinity)
        .sheet(item: $editingPhoto) { photo in
            PhotoCropEditorView(photo: photo)
                .environmentObject(state)
        }
        .errorNoticeAlert()
        // Asked here: ContentView's alert for leaving the card is under this sheet.
        .alert("Discard the ID card?", isPresented: $asksDiscard) {
            Button("Discard", role: .destructive) { state.discardIdCard() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The ID card has not been saved. Its scanned sides will be discarded.")
        }
    }

    /// "Save PDF", "Save JPEG".
    private var saveTitle: String {
        state.settings.format.pageFormat == .pdf
            ? String(localized: "Save PDF")
            : String(localized: "Save \(state.settings.format.pageFormat.label)")
    }

    private var saveHelp: String {
        let paper = state.idCardPaperSize.label
        return state.idCardBack == nil
            ? String(localized: "Save the front on one \(paper) page")
            : String(localized: "Save both sides on one \(paper) page")
    }

    private var discardHelp: String {
        state.idCardBack == nil ? String(localized: "Delete the front; can't be undone")
                                : String(localized: "Delete both sides; can't be undone")
    }
}

// MARK: - File-private card

/// One side of the card: its picture (turned as the user turned it), the note about its crop, and
/// turning, fixing the crop and scanning it again; a missing back offers scanning it.
fileprivate struct IdCardSideCard: View {
    let side: PageSide
    let title: String
    let photo: DetectedPhoto?
    let note: String?
    let busy: Bool
    let onRotate: () -> Void
    let onAdjustCrop: () -> Void
    let onRetake: () -> Void

    @State private var thumbnail: CGImage?

    /// "Front side", "Back side: none".
    private var accessibilityName: String {
        switch (side, photo == nil) {
        case (.front, true): String(localized: "Front side: none")
        case (.front, false): String(localized: "Front side")
        case (.back, true): String(localized: "Back side: none")
        case (.back, false): String(localized: "Back side")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.headline)
                Spacer(minLength: 4)
                if photo != nil {
                    // Short tooltips; the names keep the side ("Scan the front again").
                    Button(action: onRotate) {
                        Image(systemName: "rotate.right")
                    }
                    .help("Rotate")
                    .accessibilityLabel(side == .front ? Text("Rotate the front 90° clockwise") : Text("Rotate the back 90° clockwise"))
                    Button(action: onAdjustCrop) {
                        Image(systemName: "crop")
                    }
                    .help("Fix crop")
                    .accessibilityLabel(side == .front ? Text("Fix the crop of the front") : Text("Fix the crop of the back"))
                    Button(action: onRetake) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Scan again")
                    .accessibilityLabel(side == .front ? Text("Scan the front again") : Text("Scan the back again"))
                }
            }
            .buttonStyle(.borderless)
            .disabled(busy)

            if photo != nil {
                ZStack {
                    // The thumbnail is drawn turned, so a turned card is laid out (and fitted into the
                    // frame) at its turned shape, as on Windows.
                    if let thumbnail {
                        Image(decorative: thumbnail, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.15))
                    }
                }
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                if let note {
                    Label(note, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No back side. Scan it if something is printed on the back.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Scan the Back", action: onRetake)
                    .disabled(busy)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityName)
        // Keyed on the region and the turn so a new crop, a new scan or a turn re-renders the thumbnail.
        .task(id: ThumbnailKey(region: photo?.region, quarterTurns: photo?.rotationQuarterTurns ?? 0)) {
            thumbnail = photo.map { (photo: DetectedPhoto) -> CGImage in
                let small = sideThumbnail(photo.image, maxDimension: 340)
                return photo.rotationQuarterTurns == 0
                    ? small
                    : ImagePipeline.rotate(small, quarterTurns: photo.rotationQuarterTurns)
            }
        }
    }
}

/// What a side's thumbnail is drawn from: its crop and its turn.
fileprivate struct ThumbnailKey: Equatable {
    let region: DetectedPhotoRegion?
    let quarterTurns: Int
}

/// Downsample a side for its card.
fileprivate func sideThumbnail(_ image: CGImage, maxDimension: CGFloat) -> CGImage {
    let w = CGFloat(image.width), h = CGFloat(image.height)
    guard w > 0, h > 0 else { return image }
    let scale = maxDimension / max(w, h)
    guard scale < 1 else { return image }
    let tw = max(1, Int(w * scale)), th = max(1, Int(h * scale))
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return image }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: tw, height: th))
    return ctx.makeImage() ?? image
}
#endif
