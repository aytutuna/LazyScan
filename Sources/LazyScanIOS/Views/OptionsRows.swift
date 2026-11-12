#if os(iOS)
import LazyScanKit
import LazyScanModel
import SwiftUI
import UniformTypeIdentifiers

/// A reason beside a dimmed setting, or a consequence not to miss: an icon and a few words.
struct ReasonLine: View {
    let text: String
    var systemImage: String = "info.circle"

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The offer under the book's reading order and rotation to cut the spreads already scanned again with
/// them (`AppState.bookReorderOffer`); Apply is one Undo on the scan screen. Nothing while no offer is up.
struct BookReorderRow: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if let offer = state.bookReorderOffer {
            row(offer)
        }
    }

    private func row(_ offer: BookReorderOffer) -> some View {
        let working: Bool = state.isBusy && state.statusMessage == BookPages.reorderingStatus
        let text: String = working ? BookPages.reorderingStatus : BookPages.reorderOfferText(count: offer.count)
        let spoken: String = BookPages.reorderOfferLabel(count: offer.count, changed: offer.changed)
        let busy: Bool = state.isBusy
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if working {
                    ProgressView()
                }
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(spoken))
            }
            ViewThatFits {
                HStack(spacing: 24) {
                    buttons
                }
                VStack(alignment: .leading, spacing: 0) {
                    buttons
                }
            }
            .disabled(busy)
        }
        .accessibilityElement(children: .contain)
        .onAppear {
            AccessibilityNotification.Announcement(spoken).post()
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button("Apply") {
            state.applyBookReorder()
        }
        .buttonStyle(.borderless)
        .frame(minHeight: 44)
        .accessibilityIdentifier("book.reorder.apply")
        Button("Not now") {
            state.dismissBookReorder()
        }
        .buttonStyle(.borderless)
        .frame(minHeight: 44)
        .accessibilityIdentifier("book.reorder.dismiss")
    }
}

/// The scanner's Source, Sides (with a feeder), Paper size (not on the demo scanner, which ignores it),
/// Resolution and Color: for the scanner in use (a network scanner, the demo scanner), in printer mode
/// only, since the camera measures its own pages; with no
/// scanner selected yet a line says where to pick one instead. Source is locked while a side of an ID card
/// is held, as on the Mac: another source would end the task and drop the card. With a feeder it is locked
/// under ID card, Book and Text too, whose tasks need the flatbed, so the feeder never ends the task under the
/// chip. Also the scan screen's drawer, outside a form, so each picker sits beside its name (`LabeledContent`).
struct ScannerSettingsRows: View {
    @EnvironmentObject private var state: AppState
    /// Color is left out where its own control is beside these (the scan screen's drawer).
    var includesColor: Bool = true

    var body: some View {
        if let reason = IOSSettingsSections.scannerRowsReason(selected: state.selectedDeviceID) {
            ReasonLine(text: reason)
        } else {
            rows
        }
    }

    @ViewBuilder
    private var rows: some View {
        let sources: [ScanSource] = IOSSettingsSections.offeredSources(state.capabilities,
                                                                         chosen: state.settings.source)
        let feeder: Bool = state.settings.source == ScanSource.documentFeeder
        let lock: String? = IOSSettingsSections.sourceLockReason(task: state.activeTask,
                                                                  cardHeld: state.hasIdCardCaptures,
                                                                  sources: sources)
        LabeledContent("Source") {
            Picker("Source", selection: source) {
                ForEach(sources) { (source: ScanSource) in
                    Text(source.label).tag(source)
                }
            }
            .labelsHidden()
        }
        .disabled(lock != nil)
        .accessibilityHint(Text(lock ?? state.settings.source.hint))
        if let lock {
            ReasonLine(text: lock)
        }
        if sources.contains(ScanSource.documentFeeder) {
            LabeledContent("Sides") {
                Picker("Sides", selection: sides) {
                    ForEach(offeredSides) { (mode: DuplexMode) in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
            }
            .disabled(!feeder)
            .accessibilityHint(Text(state.settings.duplex.hint))
            if !feeder {
                ReasonLine(text: DocumentSides.needsFeederReason)
            }
        }
        if !demoSelected {
            let fits: Bool = state.settings.paperSize == PaperSize.longPaper
                ? feeder
                : PaperSizes.fits(state.settings.paperSize, in: paperArea, custom: state.settings.customPaper)
            LabeledContent("Paper size") {
                Picker("Paper size", selection: $state.settings.paperSize) {
                    ForEach(offeredPaperSizes) { (size: PaperSize) in
                        Text(paperSizeTitle(size)).tag(size)
                    }
                }
                .labelsHidden()
            }
            .accessibilityHint(Text(paperSizeHint))
            if !fits {
                ReasonLine(text: PaperSizes.doesNotFitReason(source: state.settings.source))
            }
        }
        LabeledContent("Resolution") {
            Picker("Resolution", selection: $state.settings.resolution) {
                ForEach(resolutions, id: \.self) { (dpi: Int) in
                    Text("\(dpi) dpi").tag(dpi)
                }
            }
            .labelsHidden()
        }
        if includesColor {
            LabeledContent("Color") {
                Picker("Color", selection: $state.settings.colorMode) {
                    ForEach(ColorMode.allCases) { (mode: ColorMode) in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
            }
        }
    }

    // A source or sides that end the task under an Options switch (Both sides, Separate documents) keep its
    // kind, as that switch turned off would.
    private var source: Binding<ScanSource> {
        let appState: AppState = state
        return Binding<ScanSource>(
            get: { appState.settings.source },
            set: { (source: ScanSource) in
                var s: ScanSettings = appState.settings
                s.source = source
                appState.settings = IOSShell.keepingKind(s)
            })
    }

    private var sides: Binding<DuplexMode> {
        let appState: AppState = state
        return Binding<DuplexMode>(
            get: { appState.settings.duplex },
            set: { (mode: DuplexMode) in
                var s: ScanSettings = appState.settings
                s.duplex = mode
                appState.settings = IOSShell.keepingKind(s)
            })
    }

    private var demoSelected: Bool {
        let selected: String? = state.selectedDeviceID
        return state.devices.contains { (info: ScannerInfo) -> Bool in info.id == selected && info.isDemo }
    }

    private var paperSizeHint: String {
        let wholeGlass: Bool = state.settings.source == ScanSource.flatbed && TaskCatalog.scansWholeGlass(state.settings)
        return PaperSizes.hint(wholeGlass ? PaperSize.auto : state.settings.paperSize, source: state.settings.source)
    }

    /// The glass or the feeder, whichever is the source; nil while the scanner's capabilities are unknown.
    private var paperArea: CGSize? {
        guard let caps: ScannerCapabilities = state.capabilities else { return nil }
        return state.settings.source == ScanSource.documentFeeder ? caps.feederSizeInches : caps.flatbedSizeInches
    }

    /// Automatic, the region's usual size, then the others that fit the glass or the feeder, with the one
    /// chosen always listed. Custom size needs width and height fields, so it is left out; Long paper is
    /// offered only for a feeder that reports its size.
    private var offeredPaperSizes: [PaperSize] {
        let area: CGSize? = paperArea
        let chosen: PaperSize = state.settings.paperSize
        let longPaper: Bool = state.settings.source == ScanSource.documentFeeder && area != nil
        return PaperSizes.displayOrder(region: Locale.current.region?.identifier).filter { (size: PaperSize) in
            if size == chosen { return true }
            if size == PaperSize.custom { return false }
            if size == PaperSize.longPaper { return longPaper }
            return PaperSizes.fits(size, in: area)
        }
    }

    private func paperSizeTitle(_ size: PaperSize) -> String {
        if size == PaperSize.auto || size == PaperSize.custom || size == PaperSize.longPaper {
            return size.label
        }
        return String(localized: "\(size.label) (\(size.detail))")
    }

    /// The scanner's resolutions, with the one chosen always listed.
    private var resolutions: [Int] {
        var list: [Int] = state.capabilities?.supportedResolutions ?? AppState.fallbackResolutions
        if !list.contains(state.settings.resolution) {
            list.append(state.settings.resolution)
            list.sort()
        }
        return list
    }

    /// One side, both (a feeder that scans both), turned over by hand (where it can be); the one chosen is
    /// always listed.
    private var offeredSides: [DuplexMode] {
        let s: ScanSettings = state.settings
        let duplex: Bool = state.capabilities?.supportsDuplex ?? false
        var modes: [DuplexMode] = []
        for mode in DuplexMode.allCases {
            switch mode {
            case .off:
                modes.append(mode)
            case .both:
                if duplex || s.duplex == .both { modes.append(mode) }
            case .manual:
                if DocumentSides.manualUnavailableReason(s) == nil || s.duplex == .manual { modes.append(mode) }
            }
        }
        return modes
    }
}

/// Where files are saved: the app's own folder in Files (On My iPhone › Lazy Scan) or one picked with
/// Choose… (iCloud Drive, a USB drive; `IOSSaveFolder`), with Show in Files. Use app folder goes back to
/// the app's own once another is picked.
struct SaveFolderRow: View {
    @EnvironmentObject private var state: AppState
    @State private var choosing: Bool = false

    var body: some View {
        let folder: URL = IOSSavedFiles.shownFolder(state.settings)
        LabeledContent(IOSSettingsText.saveToLabel) {
            HStack(spacing: 8) {
                Text(folder.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button {
                    state.revealInFinder(folder)
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(IOSSavedFiles.revealLabel))
            }
        }
        HStack {
            Button(IOSSettingsText.chooseFolderLabel) {
                choosing = true
            }
            .accessibilityIdentifier("settings.saveFolder.choose")
            if state.settings.destinationBookmark != nil {
                Spacer()
                Button(IOSSettingsText.appFolderLabel) {
                    state.settings = IOSSaveFolder.appFolder(state.settings)
                }
                .accessibilityIdentifier("settings.saveFolder.app")
            }
        }
        .buttonStyle(.borderless)
        .fileImporter(isPresented: $choosing, allowedContentTypes: [UTType.folder]) { (result: Result<URL, Error>) in
            switch result {
            case .success(let url):
                do {
                    state.settings = try IOSSaveFolder.choosing(url, in: state.settings)
                    state.openBookmarkedFolder()
                } catch {
                    state.errorMessage = error.localizedDescription
                }
            case .failure(let error):
                state.errorMessage = error.localizedDescription
            }
        }
    }
}

/// Auto-enhance, the four sliders on one -100…+100 scale with Reset, Remove print dots and Restore faded
/// colors, which for Photos is the drawer's own switch (`RestoreToggle`: Restore old photos under the hood).
struct AdjustmentSettingsRows: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Toggle("Auto-enhance", isOn: $state.settings.adjustments.autoEnhance)
        ForEach(IOSAdjustment.allCases) { (adjustment: IOSAdjustment) in
            slider(adjustment)
        }
        Button {
            state.settings.adjustments = IOSAdjustment.neutral(state.settings.adjustments)
        } label: {
            Label(IOSSettingsText.resetLabel, systemImage: "arrow.counterclockwise")
        }
        .disabled(IOSAdjustment.isNeutral(state.settings.adjustments))
        .accessibilityHint(Text("Puts the four sliders back to neutral"))
        Toggle("Remove print dots", isOn: $state.settings.adjustments.descreen)
            .accessibilityHint(Text("Smooths the dot pattern of magazines and printed photos (descreen)"))
        if IOSShell.shownKind(state.settings) == .photos {
            RestoreToggle()
        } else {
            Toggle("Restore faded colors", isOn: $state.settings.adjustments.restoreFadedColors)
        }
        if AdjustmentSettingsRows.showsThreshold(state.settings) {
            thresholdSlider
        }
    }

    /// The black and white threshold has a slider while the color is Black & White.
    static func showsThreshold(_ s: ScanSettings) -> Bool {
        s.colorMode == .blackWhite
    }

    private var thresholdSlider: some View {
        let level: Double = state.settings.adjustments.blackWhiteThreshold
        let text: String = Int((level * 100).rounded()).formatted()
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("B&W threshold")
                Spacer(minLength: 8)
                Text(text)
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
            }
            Slider(value: $state.settings.adjustments.blackWhiteThreshold, in: 0...1)
                .accessibilityLabel(Text("B&W threshold"))
                .accessibilityValue(Text(text))
                .accessibilityHint(Text("Higher makes more of the page black"))
                .accessibilityIdentifier("options.bwThreshold")
        }
    }

    private func slider(_ adjustment: IOSAdjustment) -> some View {
        let value: Binding<Double> = amount(adjustment)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(adjustment.label)
                Spacer(minLength: 8)
                Text(IOSAdjustment.amountText(value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
            }
            Slider(value: value, in: -100...100)
                .accessibilityLabel(Text(adjustment.label))
                .accessibilityValue(Text(IOSAdjustment.amountText(value.wrappedValue)))
        }
    }

    private func amount(_ adjustment: IOSAdjustment) -> Binding<Double> {
        let appState: AppState = state
        return Binding<Double>(
            get: { adjustment.amount(appState.settings.adjustments) },
            set: { (amount: Double) in
                appState.settings.adjustments = adjustment.setting(amount, in: appState.settings.adjustments)
            })
    }
}

/// The JPEG's quality, 50% to 100%: under the Format row while Save as shows JPEG.
struct JPEGQualityRow: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let text: String = state.settings.jpegQuality.formatted(.percent.precision(.fractionLength(0)))
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("JPEG quality")
                Spacer(minLength: 8)
                Text(text)
                    .monospacedDigit()
                    .foregroundStyle(Color.secondary)
            }
            Slider(value: $state.settings.jpegQuality, in: 0.5...1)
                .accessibilityLabel(Text("JPEG quality"))
                .accessibilityValue(Text(text))
                .accessibilityHint(Text("Lower makes smaller files"))
                .accessibilityIdentifier("options.jpegQuality")
        }
    }
}

/// Skip blank pages (with what counts as blank), crop and straighten, rotate upright, and split facing
/// pages with the book's choices: on pages collected before saving only. Camera mode offers what runs on
/// its pages (`PageProcessor.forCapture`): they are cut along their corners already, so there is nothing to
/// crop, their straightening is the drawer's own (`IOSShell.straightenKey`), and spreads are split only with Whole spread picked, so Split facing pages shows
/// only then and the book's choices only while whole spreads are cut.
struct PageSettingsRows: View {
    @EnvironmentObject private var state: AppState
    let camera: Bool

    var body: some View {
        let s: ScanSettings = state.settings
        let collecting: Bool = PageProcessor.checksBlankPages(s)
        let separators: Bool = collecting && DocumentSplitter.blankPagesAreSeparators(s.document, sides: state.effectiveDuplex)
        let upright: Bool = state.canTurnPagesUpright
        let oneSide: Bool = BookPages.scansOneSide(s)
        let spreads: Bool = camera ? PageProcessor.splitsCameraSpreads(s) : s.document.splitFacingPages
        if !collecting {
            ReasonLine(text: IOSSettingsText.notCollectingReason)
        }
        Toggle("Skip blank pages", isOn: $state.settings.document.removeBlankPages)
            .disabled(!collecting || separators)
            .accessibilityHint(Text(separators ? DocumentSplitter.blankPagesAreSeparatorsHint
                                    : String(localized: "Blank pages are left out. Tap Keep on a page to save it.")))
        if separators {
            ReasonLine(text: String(localized: "Blank sheets split documents"))
        }
        if collecting && s.document.removeBlankPages {
            Picker("What counts as blank", selection: $state.settings.document.blankSensitivity) {
                ForEach(BlankSensitivity.displayOrder, id: \.self) { (level: BlankSensitivity) in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityHint(Text(s.document.blankSensitivity.hint))
            if s.document.blankSensitivity == BlankSensitivity.high {
                ReasonLine(text: BlankSensitivity.highWarning, systemImage: "exclamationmark.triangle")
            }
        }
        if !camera {
            Toggle("Crop to page", isOn: $state.settings.document.autoCrop)
                .disabled(!collecting)
                .accessibilityHint(Text("Cut away the scanner background"))
            Toggle("Straighten pages", isOn: $state.settings.document.autoStraighten)
                .disabled(!collecting)
                .accessibilityHint(Text("Straighten slanted pages"))
        }
        Toggle("Rotate pages upright", isOn: $state.settings.document.autoRotate)
            .disabled(!collecting || !upright)
            .accessibilityHint(Text(PageTurns.hint(s, available: upright)))
        if collecting && !upright {
            ReasonLine(text: PageTurns.hint(s, available: upright))
        }
        if !camera || s.taskOptions.cameraSpreads {
            Toggle("Split facing pages", isOn: $state.settings.document.splitFacingPages)
                .disabled(!collecting || !oneSide)
            if collecting && !oneSide {
                ReasonLine(text: BookPages.notWithTwoSidedReason)
            }
        }
        if collecting && oneSide && spreads {
            Toggle("Reads right to left", isOn: $state.settings.taskOptions.bookRightToLeft)
                .accessibilityHint(Text("Arabic, Hebrew, manga: the right page of each spread comes first."))
            Picker("Book rotation", selection: bookTurns) {
                ForEach(BookPages.rotationChoices, id: \.self) { (turns: Int) in
                    Text(BookPages.rotationLabel(turns)).tag(turns)
                }
            }
            BookReorderRow()
            Picker("Cut at", selection: $state.settings.taskOptions.bookCutAt) {
                ForEach(BookCutAt.allCases, id: \.self) { (choice: BookCutAt) in
                    Text(BookPages.cutAtLabel(choice)).tag(choice)
                }
            }
            .accessibilityHint(Text("Where a spread is cut when no gutter is found. Same as last uses the cut you set by hand last."))
            .accessibilityIdentifier("options.cutAt")
            Toggle("Soften spine shadow", isOn: $state.settings.document.softenSpineShadow)
                .accessibilityHint(Text(SpineShadow.hint(s.document.softenSpineShadow)))
        }
    }

    private var bookTurns: Binding<Int> {
        let appState: AppState = state
        return Binding<Int>(
            get: { BookSplitter.normalizedTurns(appState.settings.taskOptions.bookRotationQuarterTurns) },
            set: { (turns: Int) in
                appState.settings.taskOptions.bookRotationQuarterTurns = turns
            })
    }
}

/// Split into documents: the choice (through `AppState.setSplitMode`), its one line, the sheet count, and at
/// QR codes where the codes are; Save sheet makes the separator sheet to print.
struct SplitSettingsRows: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let s: ScanSettings = state.settings
        let collecting: Bool = s.documentMultiPage
        let mode: SplitMode = s.document.splitMode
        if !collecting {
            ReasonLine(text: IOSSettingsText.notCollectingReason)
        }
        Picker("Split|setting", selection: splitMode) {
            ForEach(SplitMode.displayOrder, id: \.self) { (choice: SplitMode) in
                Text(choice.label).tag(choice)
            }
        }
        .disabled(!collecting)
        .accessibilityHint(Text(mode.hint))
        .accessibilityIdentifier("options.split")
        if collecting && !mode.caption.isEmpty {
            Text(mode.caption)
                .font(.caption)
                .foregroundStyle(Color.secondary)
        }
        if collecting && mode == SplitMode.sheetCount {
            Stepper(value: sheetCount, in: 1...DocumentSplitter.maxSheetCount) {
                Text(L10n.plural(DocumentSplitter.clampSheetCount(s.document.splitSheetCount),
                                 one: "New document every {0} sheet", other: "New document every {0} sheets"))
            }
            .accessibilityIdentifier("split.sheets")
        }
        if collecting && mode == SplitMode.barcode {
            Picker("Codes are on", selection: startsDocument) {
                Text("Separator sheets").tag(false)
                Text("First pages").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("split.codes")
            Text(BarcodeSeparators.startsDocumentCaption(s.document.barcodeStartsDocument))
                .font(.caption)
                .foregroundStyle(Color.secondary)
        }
        if collecting && (mode == SplitMode.separatorSheet || (mode == SplitMode.barcode && !s.document.barcodeStartsDocument)) {
            if mode == SplitMode.barcode {
                TextField("Name on sheet", text: $state.qrSheetName, prompt: Text("Optional"))
                    .accessibilityIdentifier("separator.name")
            }
            Button {
                state.saveSeparatorSheet()
            } label: {
                Label("Save sheet", systemImage: "square.and.arrow.down")
            }
            .accessibilityHint(Text("Saves a PDF of the sheet; print it at 100%"))
            .accessibilityIdentifier("separator.save")
            if mode == SplitMode.separatorSheet {
                ReasonLine(text: CameraTaskCatalog.separatorHint)
            }
        }
    }

    private var splitMode: Binding<SplitMode> {
        let appState: AppState = state
        return Binding<SplitMode>(
            get: { appState.settings.document.splitMode },
            set: { (mode: SplitMode) in
                IOSShell.setSplit(mode, in: appState)
            })
    }

    private var sheetCount: Binding<Int> {
        let appState: AppState = state
        return Binding<Int>(
            get: { DocumentSplitter.clampSheetCount(appState.settings.document.splitSheetCount) },
            set: { (count: Int) in
                appState.setSplitSheetCount(count)
            })
    }

    private var startsDocument: Binding<Bool> {
        let appState: AppState = state
        return Binding<Bool>(
            get: { appState.settings.document.barcodeStartsDocument },
            set: { (on: Bool) in
                appState.setBarcodeStartsDocument(on)
            })
    }
}

/// Collect pages before saving: locked on while the camera's Both sides pairs the sides in the queue, and
/// while a PDF picked in the task list takes the pages, since turned off each scan would be saved as a new
/// file. Not for Receipts and the ID card, which save from their own screens.
struct CollectPagesRow: View {
    @EnvironmentObject private var state: AppState
    let camera: Bool

    var body: some View {
        let s: ScanSettings = state.settings
        let flow: TaskFlowKind = TaskCatalog.flow(of: s)
        // Both sides pairs the camera's fronts and backs in the queue; a feeder scanning both sides keeps a
        // scan's sheets together even when each scan is saved at once. Locked only while on: Both sides kept
        // from printer mode or a preset with Collect off can still turn it on.
        let paired: Bool = camera && state.cameraSides != nil && s.documentMultiPage
        // A PDF picked in the task list takes the pages only while they are collected: turned off, each scan
        // would be saved as a new file. Stop Adding under Share now is the way back.
        let reason: String? = paired ? IOSSettingsText.bothSidesCollectsReason
            : state.appendTarget.map { IOSSettingsText.addingToReason($0.lastPathComponent) }
        if s.intent == ScanIntent.document && flow != TaskFlowKind.receiptSplit && flow != TaskFlowKind.idCard {
            Toggle("Collect pages before saving", isOn: $state.settings.documentMultiPage)
                .disabled(reason != nil)
                .accessibilityHint(Text(reason ?? String(localized: "Off: each page is saved right away")))
                .accessibilityIdentifier("options.collect")
            if let reason {
                ReasonLine(text: reason)
            }
        }
    }
}

/// The size the camera's photos are taken at, among those this phone's camera offers (`IOSCameraLens.choices`),
/// the default marked; kept on this device (`IOSCameraLens.megapixelsKey`), not in presets, as the camera's
/// own button keeps it. A size whose pages may not fit in this phone's memory says so under it.
struct CameraSettingsRows: View {
    let offered: [IOSPhotoSize]
    @AppStorage(IOSCameraLens.megapixelsKey) private var chosenMegapixels: Int = 0

    var body: some View {
        let choices: [IOSPhotoSize] = IOSCameraLens.choices(offered)
        let fallback: IOSPhotoSize? = IOSCameraLens.photoSize(offered)
        Picker(IOSSettingsText.cameraResolutionLabel, selection: megapixels) {
            ForEach(choices, id: \.pixels) { (size: IOSPhotoSize) in
                Text(IOSSettingsText.resolutionChoice(size, isDefault: size == fallback)).tag(IOSCameraLens.megapixels(size))
            }
        }
        .accessibilityIdentifier("settings.cameraResolution")
        if let size = IOSCameraLens.photoSize(offered, megapixels: chosenMegapixels),
           let warning = IOSCameraText.memoryWarning(size, among: choices, physicalMemory: ProcessInfo.processInfo.physicalMemory) {
            ReasonLine(text: warning, systemImage: "exclamationmark.triangle")
        }
    }

    /// The size taken now: the one picked, or the default while none is or this phone does not offer it.
    private var megapixels: Binding<Int> {
        let stored: Binding<Int> = $chosenMegapixels
        let sizes: [IOSPhotoSize] = offered
        return Binding<Int>(
            get: {
                guard let size = IOSCameraLens.photoSize(sizes, megapixels: stored.wrappedValue) else { return 0 }
                return IOSCameraLens.megapixels(size)
            },
            set: { (picked: Int) in
                stored.wrappedValue = picked
            })
    }
}
#endif
