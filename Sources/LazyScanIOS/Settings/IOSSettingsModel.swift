#if os(iOS)
import LazyScanKit
import Foundation

/// The words of the Options pages that are the iPhone's own; the summaries on the rows are the shared
/// `InspectorSections`.
public enum IOSSettingsText {
    public static var doneLabel: String { String(localized: "Done") }
    public static var saveAsLabel: String { String(localized: "Save as") }
    public static var lookLabel: String { String(localized: "Look") }
    public static var pagesLabel: String { String(localized: "Pages") }
    public static var separateLabel: String { String(localized: "Separate documents") }
    public static var fileNameAndFolderLabel: String { String(localized: "File name and folder") }
    public static var shareNowLabel: String { String(localized: "Share now") }
    public static var helpLabel: String { String(localized: "Help and about") }
    public static var presetsLabel: String { String(localized: "Presets") }
    public static var historyLabel: String { String(localized: "Scans") }
    public static var savedLabel: String { String(localized: "Saved files") }
    /// The iPhone's saved files and scans together (`LibraryScreen`).
    public static var libraryLabel: String { String(localized: "Library") }
    /// The computer the phone is paired with (`CompanionScreen`, I20).
    public static var companionLabel: String { String(localized: "My computer") }
    public static var saveToLabel: String { String(localized: "Save to") }
    /// Picks a save folder in Files (iCloud Drive, a USB drive); Use app folder goes back to the app's own.
    public static var chooseFolderLabel: String { String(localized: "Choose\u{2026}") }
    public static var appFolderLabel: String { String(localized: "Use app folder") }
    public static var troubleshootLabel: String { String(localized: "Troubleshoot") }
    public static var aboutLabel: String { String(localized: "About") }
    /// The ruler test page, to check that AirPrint copies come out at real size (I16).
    public static var rulerLabel: String { String(localized: "Print test ruler") }
    public static var rulerHint: String { String(localized: "Prints a ruler to check copies come out at real size") }
    public static var resetLabel: String { String(localized: "Reset") }
    public static var notCollectingReason: String { String(localized: "Needs Collect pages") }
    /// Why Collect pages is locked while the camera's Both sides is on: its fronts and backs are paired in
    /// the queue.
    public static var bothSidesCollectsReason: String { String(localized: "Both sides pairs the pages in the stack") }
    public static var importingReason: String { String(localized: "Can be changed once the import has finished") }
    public static var busyReason: String { String(localized: "Can be changed once the scan or save has finished") }
    /// Why Source is locked while a side of an ID card is held (from the camera or the scanner alike).
    public static var idCardHeldReason: String {
        String(localized: "Source is locked while a side of the ID card is held. Save or discard the card, or pick another type, to change it.")
    }
    /// In place of the Scanner section's rows while no scanner is selected: printer mode until the scanner
    /// picked is found (camera mode has no Scanner section).
    public static var noScannerReason: String { String(localized: "No scanner is in use. Pick one in the Scanner row to change these.") }
    /// The About screen: what the app is built with (Apple's frameworks, and the page corner model with
    /// what runs it, whose licenses go with the app) and where scans stay.
    public static var aboutBuiltWith: String {
        String(localized: "Built with Apple's frameworks. Pages are found with DocAligner by DocsaidLab (Apache License 2.0) on ONNX Runtime by Microsoft (MIT License).")
    }
    public static var aboutPrivacy: String { String(localized: "Your scans stay on this device unless you share them.") }
    /// About's row to the licence texts that go with the app (`LicencesScreen`).
    public static var licencesLabel: String { String(localized: "Licences") }
    public static var licenceMissing: String { String(localized: "Licence text missing") }
    /// The camera's group, on this device only: the size its photos are taken at.
    public static var cameraTitle: String { String(localized: "Camera") }
    public static var cameraResolutionLabel: String { String(localized: "Resolution") }

    /// Why Collect pages is locked while a PDF picked in the task list takes the pages: turned off, each scan
    /// would be saved as a new file while Save still names this one.
    public static func addingToReason(_ fileName: String) -> String {
        String(localized: "Adding to \(fileName)")
    }

    /// Why Source is locked under ID card, Book and Text, whose tasks need the flatbed.
    public static func needsFlatbedReason(_ kind: String) -> String {
        String(localized: "\(kind) is scanned on the flatbed. Pick Document to use the feeder.")
    }

    /// A photo size in the Resolution picker, "24 MP (default)" for the one taken until another is picked.
    public static func resolutionChoice(_ size: IOSPhotoSize, isDefault: Bool) -> String {
        isDefault ? String(localized: "\(IOSCameraText.sizeLabel(size)) (default)") : IOSCameraText.sizeLabel(size)
    }

    /// "Version 0.1.0 (1)" from the app's Info.plist; "Version 0.1.0" without a build number.
    public static func version(_ info: [String: Any]?) -> String {
        let short: String = info?["CFBundleShortVersionString"] as? String ?? "?"
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else { return String(localized: "Version \(short)") }
        return String(localized: "Version \(short) (\(build))")
    }
}

/// What the Options pages show, on top of the shared `InspectorSections` rules (which of the desktop's
/// sections apply, their summaries). The iPhone differs where it saves pictures: a queue saved as pictures
/// (`IOSShell.savesImages`) and the Text kind's held page (`AppState.saveQuickScan`) write no PDF, so the PDF's
/// choices are hidden there and the text beside a PDF does not count, and Save as shows that page's picture
/// format (`shownFormat`). Camera mode has no Scanner page, the camera measuring its own pages, and its Pages
/// row counts only what runs on them (`cameraShown`).
public enum IOSSettingsSections {
    /// The scan screen saves the queue as a picture a page, or the Text kind's screen its page as a picture,
    /// so no PDF is written.
    public static func savesPictures(_ s: ScanSettings) -> Bool {
        (IOSShell.collectsPages(s) && IOSShell.savesImages(s)) || (s.task == .quickScan && !s.documentMultiPage)
    }

    /// Photos and Receipts save the pages they found in the format chosen in Options, any of them, where the
    /// desktop saves photos as pictures and receipts as a PDF or a picture.
    private static func savesChosenFormat(_ s: ScanSettings) -> Bool {
        let flow: TaskFlowKind = TaskCatalog.flow(of: s)
        return flow == .photoSplit || flow == .receiptSplit
    }

    /// The format Output shows: the format chosen for Photos and Receipts, the Text kind's held page (Collect
    /// pages off) as a picture (JPEG unless an image format is chosen), the rest as
    /// `InspectorSections.shownFormat` says.
    public static func shownFormat(_ s: ScanSettings) -> OutputFormat {
        if savesChosenFormat(s) { return s.format }
        return s.task == .quickScan && !s.documentMultiPage ? s.format.imageFormatOrJPEG : InspectorSections.shownFormat(s)
    }

    /// Archive & password and Searchable PDF apply: a save of `s` writes a PDF here.
    public static func writesPDF(_ s: ScanSettings) -> Bool {
        if savesChosenFormat(s) { return s.format == .pdf }
        return InspectorSections.writesPDF(s) && !savesPictures(s)
    }

    /// Whether the Output rows offer every format, not the desktop's list for the task.
    public static func offersEveryFormat(_ s: ScanSettings) -> Bool {
        savesChosenFormat(s)
    }

    /// The Scanner section's rows are a selected scanner's; with none (printer mode's scanner not found yet)
    /// a line says where to pick one instead.
    public static func scannerRowsReason(selected: String?) -> String? {
        selected == nil ? IOSSettingsText.noScannerReason : nil
    }

    /// The sources the Source row offers: the scanner's (the flatbed until they are known), with the one
    /// chosen always listed, so the row never shows a blank value.
    public static func offeredSources(_ capabilities: ScannerCapabilities?, chosen: ScanSource) -> [ScanSource] {
        var sources: [ScanSource] = capabilities?.sources ?? [ScanSource.flatbed]
        if !sources.contains(chosen) {
            sources.append(chosen)
        }
        return sources
    }

    /// Why the Source row is locked, nil while it is free: a side of an ID card held, or a task that needs the
    /// flatbed (ID card, Book, Text) while the row offers the feeder, which would end the task under its Type.
    /// A scanner without a flatbed never has such a task (connecting to it ends the task), so the lock keeps
    /// nothing from it.
    public static func sourceLockReason(task: ScanTask?, cardHeld: Bool, sources: [ScanSource]) -> String? {
        if cardHeld { return IOSSettingsText.idCardHeldReason }
        guard let task, sources.contains(ScanSource.documentFeeder),
              TaskCatalog.definition(task).requiredSource == ScanSource.flatbed else { return nil }
        return IOSSettingsText.needsFlatbedReason(IOSShell.kind(of: task).title)
    }

    /// Also save text applies here.
    public static func textApplies(_ s: ScanSettings) -> Bool {
        if savesChosenFormat(s) { return s.format == .pdf && s.intent == .document }
        return InspectorSections.textApplies(s) && !savesPictures(s)
    }

    /// `s` with only the page options that run on camera mode's pages, which its Pages header counts: they
    /// are cut out of the photo along their corners already, so never cropped, and facing pages are split
    /// only from spreads taken whole (`PageProcessor.forCapture`). Their straightening is the camera's own
    /// (`IOSShell.straightenKey`), not the setting, so it is not counted.
    public static func cameraShown(_ s: ScanSettings) -> ScanSettings {
        var shown: ScanSettings = s
        shown.document.autoCrop = false
        shown.document.autoStraighten = false
        shown.document.splitFacingPages = PageProcessor.splitsCameraSpreads(s)
        return shown
    }
}

/// The pages of the Options sheet, each opened from a row of its list (`OptionsScreen`) with its current
/// value. The first group follows the settings, the second is the same for every task. About and Licences
/// are reached from Help and about.
public enum IOSOptionsPage: String, Hashable, Identifiable {
    case saveAs
    case look
    case pages
    case separate
    case fileName
    case afterSaving
    case scanner
    case camera
    case shareNow
    case presets
    case computer
    case help
    case about
    case licences

    public var id: String { rawValue }

    /// The pages after the settings group.
    public static let more: [IOSOptionsPage] = [.presets, .computer, .help]

    public var identifier: String { "options.page.\(rawValue)" }

    public var title: String {
        switch self {
        case .saveAs: return IOSSettingsText.saveAsLabel
        case .look: return IOSSettingsText.lookLabel
        case .pages: return IOSSettingsText.pagesLabel
        case .separate: return IOSSettingsText.separateLabel
        case .fileName: return IOSSettingsText.fileNameAndFolderLabel
        case .afterSaving: return IOSAfterSave.title
        case .scanner: return String(localized: "Scanner")
        case .camera: return IOSSettingsText.cameraTitle
        case .shareNow: return IOSSettingsText.shareNowLabel
        case .presets: return IOSSettingsText.presetsLabel
        case .computer: return IOSSettingsText.companionLabel
        case .help: return IOSSettingsText.helpLabel
        case .about: return IOSSettingsText.aboutLabel
        case .licences: return IOSSettingsText.licencesLabel
        }
    }

    /// The pages of the first group for `s`, in order, those that can apply only: Pages for document pages
    /// collected in the queue (the desktop's Pages section), Separate documents for the Document kind and
    /// wherever the queue can be split, After saving while the pages are saved here, Scanner on the scanner
    /// tab, and Camera on the camera tab where the phone's camera offers more than one photo size
    /// (`photoSizes`).
    public static func listed(_ s: ScanSettings, camera: Bool, pageCount: Int, photoSizes: Int) -> [IOSOptionsPage] {
        let sections: [String] = InspectorSections.shown(s)
        var pages: [IOSOptionsPage] = [.saveAs, .look]
        if sections.contains(InspectorSections.pages) {
            pages.append(.pages)
        }
        if IOSShell.shownKind(s) == .document || sections.contains(InspectorSections.split) {
            pages.append(.separate)
        }
        pages.append(.fileName)
        if IOSShell.offersSave(s, pageCount: pageCount) {
            pages.append(.afterSaving)
        }
        if !camera {
            pages.append(.scanner)
        } else if photoSizes > 1 {
            pages.append(.camera)
        }
        return pages
    }

    /// Save as: "PDF · Standard", "Word", "JPEG"; a PDF that is archival or has a password says so after it.
    public static func saveAsValue(_ s: ScanSettings) -> String {
        let format: String = InspectorSections.outputSummary(s, shownFormat: IOSSettingsSections.shownFormat(s))
        guard InspectorSections.writesPDF(s) && (s.output.protect || s.output.archival) else { return format }
        return format + " \u{00B7} " + InspectorSections.archiveSummary(s.output)
    }

    /// Look: the filter new pages get on the camera tab (where it is offered), then what is adjusted.
    public static func lookValue(_ s: ScanSettings, camera: Bool) -> String {
        let adjusted: String = InspectorSections.adjustmentsSummary(s.adjustments)
        guard camera && IOSShell.offersFilters(s) else { return adjusted }
        let filter: String = IOSShell.drawerFilter(s).label
        return adjusted.isEmpty ? filter : filter + " \u{00B7} " + adjusted
    }

    /// Pages: the options that are on; on the camera tab only those that run on its pages.
    public static func pagesValue(_ s: ScanSettings, camera: Bool) -> String {
        InspectorSections.pagesSummary((camera ? IOSSettingsSections.cameraShown(s) : s).document)
    }

    /// Separate documents: On or Off, or how the queue is split when that is not at separator sheets or codes.
    public static func separateValue(_ s: ScanSettings) -> String {
        if IOSShell.separatesDocuments(s) { return IOSCameraText.onValue }
        return s.document.splitMode == SplitMode.none ? IOSCameraText.offValue : InspectorSections.splitSummary(s.document)
    }
}

/// The four sliders of Adjustments on one -100...+100 scale (0 neutral), mapped onto the settings' own
/// ranges as on the Mac: brightness -1...1, contrast 0.25...4 (exponential, so 0 is exactly 1), saturation
/// 0...2, sharpness -2...2.
public enum IOSAdjustment: String, CaseIterable, Identifiable {
    case brightness
    case contrast
    case saturation
    case sharpness

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .brightness: return String(localized: "Brightness")
        case .contrast: return String(localized: "Contrast")
        case .saturation: return String(localized: "Saturation")
        case .sharpness: return String(localized: "Sharpness")
        }
    }

    public func amount(_ a: AdjustmentSettings) -> Double {
        switch self {
        case .brightness: return a.brightness * 100
        case .contrast: return log(max(a.contrast, 0.25)) / log(4.0) * 100
        case .saturation: return (a.saturation - 1) * 100
        case .sharpness: return a.sharpness * 50
        }
    }

    public func setting(_ amount: Double, in a: AdjustmentSettings) -> AdjustmentSettings {
        var changed: AdjustmentSettings = a
        switch self {
        case .brightness: changed.brightness = amount / 100
        case .contrast: changed.contrast = pow(4.0, amount / 100)
        case .saturation: changed.saturation = 1 + amount / 100
        case .sharpness: changed.sharpness = amount / 50
        }
        return changed
    }

    /// "0", "+12", "-5".
    public static func amountText(_ amount: Double) -> String {
        Int(amount.rounded()).formatted(.number.sign(strategy: .always(includingZero: false)))
    }

    /// The four sliders back to neutral; the switches stay as they are.
    public static func neutral(_ a: AdjustmentSettings) -> AdjustmentSettings {
        var changed: AdjustmentSettings = a
        changed.brightness = 0
        changed.contrast = 1
        changed.saturation = 1
        changed.sharpness = 0
        return changed
    }

    public static func isNeutral(_ a: AdjustmentSettings) -> Bool {
        a.brightness == 0 && a.contrast == 1 && a.saturation == 1 && a.sharpness == 0
    }
}

/// Options' After saving on the iPhone: what runs each time Save writes a document, checked in any
/// combination and kept in the user's defaults, not in the settings file. They run in the order of the
/// cases: Send to computer and Print take the queue, which the save empties, so they come before the file is
/// written (the save follows once the copy screen has closed); Email goes out with the saved file. Under the
/// checks, Then is the settings' own action after a save (`OutputOptions.afterSave`, kept in presets), the
/// phone's only control for it. A save that is emailed runs the email in its place (`AppState.runAfterSave`):
/// a preview, Files or the share sheet cannot show over Mail's composer. Photos adds the saved JPEG or PNG
/// pictures to the photo library once they are written; the files stay in the save folder.
public enum IOSAfterSave: String, CaseIterable, Identifiable {
    case send
    case print
    case email
    case photos

    public var id: String { rawValue }

    /// The rows' order under After saving.
    public static let rows: [IOSAfterSave] = [.email, .print, .send, .photos]

    public static var title: String { String(localized: "After saving") }
    public static var footer: String { String(localized: "Runs each time a document is saved. Change it any time.") }
    public static var thenTitle: String { String(localized: "Then") }
    /// Under Then while Email is checked.
    public static var emailInsteadReason: String { String(localized: "Email is sent instead") }
    /// Under Photos while the save is not JPEG or PNG pictures.
    public static var photosNeedsPicturesReason: String { String(localized: "Only for JPEG and PNG saves") }
    public static var photosRowHint: String { String(localized: "Adds saved pictures to your photo library") }
    public static var photosButtonHint: String {
        String(localized: "Adds the saved pictures to your photo library. The files stay in the save folder.")
    }
    public static var photosSavedLabel: String { String(localized: "Saved to Photos") }

    /// After saving's value on the Options list: the checked actions, else what Then does.
    public static func summary(checked: Set<IOSAfterSave>, then: AfterSaveAction, lazyPrintInstalled: Bool) -> String {
        var names: [String] = []
        for action in rows where checked.contains(action) {
            names.append(action.label(lazyPrintInstalled: lazyPrintInstalled))
        }
        return names.isEmpty ? thenLabel(then) : names.joined(separator: ", ")
    }

    /// The Kit's action after a save in the phone's words: Show in folder opens the Files app here.
    public static func thenLabel(_ action: AfterSaveAction) -> String {
        action == .reveal ? IOSSavedFiles.revealLabel : action.label
    }

    public static func thenHint(_ action: AfterSaveAction) -> String {
        switch action {
        case .open: return String(localized: "Open the file (several: show them in Files)")
        case .reveal: return String(localized: "Show the files in the Files app")
        default: return action.hint
        }
    }

    public var label: String {
        switch self {
        case .send: return IOSCompanionText.sendButton
        case .print: return String(localized: "Print")
        case .email: return String(localized: "Email")
        case .photos: return String(localized: "Photos")
        }
    }

    /// Print is Lazy Print's name where that app takes the pages, else it stays Print.
    public func label(lazyPrintInstalled: Bool) -> String {
        self == .print && lazyPrintInstalled ? String(localized: "Lazy Print") : label
    }

    /// The user's defaults key the row's check is kept under.
    public var key: String { "afterSave.\(rawValue)" }

    /// The checked actions in the order they run; Send to computer only while a computer is paired, Photos
    /// only while the save is JPEG or PNG pictures (`pictures`).
    public static func steps(_ defaults: UserDefaults, paired: Bool, pictures: Bool) -> [IOSAfterSave] {
        var steps: [IOSAfterSave] = []
        for action in allCases where defaults.bool(forKey: action.key) {
            if action == .send && !paired { continue }
            if action == .photos && !pictures { continue }
            steps.append(action)
        }
        return steps
    }

    /// Why Send to computer's pages have not gone when the send raised no alert of its own: the computer did not
    /// answer, or no longer knows this phone, and the document waits in the outbox (`waiting`), or in the cloud
    /// folder when every one waiting is there (`inFolder`). Nil when nothing waits or the computer answered.
    public static func notSentMessage(_ status: CompanionStatus, waiting: Int, inFolder: Int = 0) -> String? {
        guard waiting > 0 else { return nil }
        switch status {
        case .unreachable(let reason):
            if inFolder == waiting {
                return String(localized: "\(reason) The document is in the cloud folder; the computer takes it from there.")
            }
            return String(localized: "\(reason) The pages wait on this device and are sent once it answers.")
        case .unpaired(let name):
            let message = CompanionText.unpairedMessage(name)
            return String(localized: "\(message) The pages were not sent.")
        case .notPaired, .checking, .reachable:
            return nil
        }
    }
}
#endif
