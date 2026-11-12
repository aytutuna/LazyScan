#if os(iOS)
import AVFoundation
import LazyScanKit
import Foundation
import UniformTypeIdentifiers

/// What the app was launched with. `-demoScanner` (the UI smoke test's) keeps the app on the demo
/// scanner alone: the iPhone has no other connection yet, and once it has (eSCL), a test launched this
/// way still scans the same made-up pages. `-importFixture` (the import UI test's) imports one photo at
/// launch into the Document task, as the Files app would hand it over: its PNG bytes, base64, in the
/// environment variable `importFixtureVariable`, since a UI test cannot drive the system's pickers;
/// `-importTask` followed by a task's name (`ScanTask`'s raw value, "photos") imports it into that task
/// instead (I13: the photos UI test). Since I14 the variable may hold several files, comma-separated, and
/// a file whose bytes start as a PDF comes in as one (the two-sided and batch UI tests).
public struct IOSLaunchOptions: Equatable, Sendable {
    /// The launch argument for the demo scanner alone.
    public static let demoScannerArgument = "-demoScanner"
    /// The launch argument that imports the photo in `importFixtureVariable` at launch.
    public static let importFixtureArgument = "-importFixture"
    /// The environment variable holding that photo's bytes, base64.
    public static let importFixtureVariable = "LAZYSCAN_IMPORT_FIXTURE"
    /// The name the photo imported at launch is shown with.
    public static let importFixtureName = "fixture.png"
    /// The name a PDF imported at launch is shown with.
    public static let importFixturePDFName = "fixture.pdf"
    /// The launch argument naming the task the photo imported at launch goes into (the next argument).
    public static let importTaskArgument = "-importTask"

    /// Only the demo scanner is offered.
    public let demoScannerOnly: Bool
    /// The files to import at launch, in order; none when the app was not launched to import.
    public let launchImports: [IOSImportItem]
    /// The task the photo imported at launch goes into; nil: the task set up when it takes photos, else
    /// Document to PDF.
    public let launchTask: ScanTask?

    public init(demoScannerOnly: Bool) {
        self.demoScannerOnly = demoScannerOnly
        self.launchImports = []
        self.launchTask = nil
    }

    /// The first file to import at launch; nil for none.
    public var launchImport: IOSImportItem? { launchImports.first }

    /// The options in the process's launch arguments.
    public init(arguments: [String]) {
        self.init(arguments: arguments, environment: [:])
    }

    /// The options in the process's launch arguments and environment (`ProcessInfo`).
    public init(arguments: [String], environment: [String: String]) {
        self.demoScannerOnly = arguments.contains(IOSLaunchOptions.demoScannerArgument)
        var items: [IOSImportItem] = []
        if arguments.contains(IOSLaunchOptions.importFixtureArgument),
           let text = environment[IOSLaunchOptions.importFixtureVariable] {
            for part in text.split(separator: ",") {
                guard let data = Data(base64Encoded: String(part), options: [.ignoreUnknownCharacters]),
                      !data.isEmpty else { continue }
                let kind: IOSImportItem.Kind = IOSImportItem.kind(forFileName: IOSLaunchOptions.importFixtureName, data: data)
                let name: String = kind == .pdf ? IOSLaunchOptions.importFixturePDFName : IOSLaunchOptions.importFixtureName
                items.append(IOSImportItem(name: name, data: data, kind: kind))
            }
        }
        self.launchImports = items
        var task: ScanTask?
        if !items.isEmpty, let index = arguments.firstIndex(of: IOSLaunchOptions.importTaskArgument),
           index + 1 < arguments.count {
            task = ScanTask(rawValue: arguments[index + 1])
        }
        self.launchTask = task
    }
}

/// What the scanner tab's picture shows (`IOSShell.scannerPicture`).
public enum ScannerPicture {
    case overview
    case page
    case empty
}

/// What the iPhone's and iPad's app shell passes `AppState`: its scanner connections, its file actions,
/// its troubleshooter service, its lifecycle and AirPrint printing (`IOSPrintService`, I16).
public enum IOSShell {
    /// The app's Documents folder in this install; the save folder kept from an earlier one is moved into
    /// it (`ScanSettings.rebasedDestinationPath`).
    public static var documentsFolder: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    /// The demo scanner alone, whatever `options` say: the connections without the network, for tests and
    /// previews. The app's are `backends(options:networkScanners:)`.
    @MainActor
    public static func backends(options: IOSLaunchOptions) -> [any ScannerBackend] {
        backends(options: options, network: nil)
    }

    /// The app's scanner connections: the network scanners (eSCL: found on the network, added by address),
    /// with the demo scanner beside them, or the demo scanner alone where `options` ask for it
    /// (`-demoScanner`, the UI tests: then nothing is searched for) or no network scanners are passed in.
    @MainActor
    public static func backends(options: IOSLaunchOptions, networkScanners: IOSNetworkScanners?) -> [any ScannerBackend] {
        backends(options: options, network: networkScanners?.backend)
    }

    /// The network scanner connection (eSCL) and the demo scanner, or the demo scanner alone when `options`
    /// ask for it or there is no network connection. On a real phone the demo scanner is listed apart from
    /// the found scanners (`IOSScannerPickerModel.demoRow`) and is only used once picked: the phone's state
    /// selects no scanner on its own (`AppState.start(onlySelecting:)`).
    @MainActor
    static func backends(options: IOSLaunchOptions, network: EsclScannerBackend?) -> [any ScannerBackend] {
        if let network, !options.demoScannerOnly {
            return [network, AppState.makeDemoBackend()]
        }
        return [AppState.makeDemoBackend()]
    }

    /// A network scanner connection to `endpoints`, its certificates pinned in `trust`, each job covered
    /// by UIKit's background time (`UIKitBackgroundActivity`).
    @MainActor
    static func networkBackend(endpoints: [EsclEndpoint], trust: EsclTrustStore,
                               clientOptions: EsclClientOptions = EsclClientOptions()) -> EsclScannerBackend {
        EsclScannerBackend(trust: trust, endpoints: endpoints, clientOptions: clientOptions,
                           background: UIKitBackgroundActivity())
    }

    /// The screen stays on while `isBusy` (a scan, a save, text recognition) and while the camera is live
    /// (`cameraLive`): iOS would suspend the app soon after the screen locked, cutting a feeder batch short,
    /// and Auto capture takes pages without a touch, so Auto-Lock would fire mid-document.
    public static func keepsScreenAwake(isBusy: Bool, cameraLive: Bool) -> Bool {
        isBusy || cameraLive
    }

    /// Whether `device` is a network scanner (eSCL), not the demo scanner; nil, with no scanner selected,
    /// is not.
    public static func usesNetworkScanner(_ device: ScannerInfo?) -> Bool {
        device?.backend == "escl"
    }

    /// The camera's line the scan screen's step card shows in place of the task's step, which speaks of the
    /// glass and the feeder (`CameraTaskCatalog.current`): for every task but the ID card, whose steps say
    /// which side is next, while the pages come from the camera, Photos or Files. With a stack turned over
    /// by hand, only while a back is due in the camera's two-sided steps or the next page starts a new
    /// document; in printer mode (`printer`) only for the new document, since a scanned page never takes the
    /// camera's back. Nil when the step's own words stay.
    public static func cameraLine(_ task: ScanTask?, options: TaskOptions, sides: CameraSides?, newDocument: Bool,
                                  turningOverByHand: Bool, printer: Bool) -> CameraStepText? {
        guard task != .idCard else { return nil }
        let pending: Bool = sides?.next == .back || newDocument
        guard pending || !turningOverByHand, !printer || newDocument else { return nil }
        return CameraTaskCatalog.current(task, options: options, sides: sides, newDocument: newDocument)
    }

    /// Whether the scan screen shows the step card: while the step's own words stay (the ID card's sides,
    /// printer mode, a stack turned over by hand: `cameraLine` is nil), a back is due or the next page starts
    /// a new document. Otherwise the camera's line is on our camera's screen only.
    public static func showsStepCard(_ task: ScanTask?, options: TaskOptions, sides: CameraSides?, newDocument: Bool,
                                     turningOverByHand: Bool, printer: Bool) -> Bool {
        if sides?.next == .back || newDocument { return true }
        return cameraLine(task, options: options, sides: sides, newDocument: newDocument,
                          turningOverByHand: turningOverByHand, printer: printer) == nil
    }

    /// The step as printer mode says it. As on the desktops' banners (`TaskCatalog.shownStep`), Document with
    /// the feeder as the source is Stack from feeder's step ("Load the pages in the feeder and scan.", "Scan
    /// stack"): the phone folds that task into Document, and a Source changed in the Scanner options keeps
    /// the kind; with Collect pages before saving off it says each scan is saved right away. Photos, Restore
    /// old photos and Receipts with the feeder as the source are fed, not laid on the glass. Separate
    /// documents' help on the Mac sends you to "Split into documents, on the right" and the page strip, but
    /// here the separator sheet is saved under Options and the splits are checked in the pages. Text's words on
    /// the Mac speak of dragging over its preview and of a scan saved at once, but here the preview is in the
    /// Scanner options, the area is chosen by tapping the preview, and the page waits on the Quick scan
    /// screen. Other steps are as `TaskCatalog.shownStep` words them.
    public static func printerStep(_ step: TaskStep, settings: ScanSettings) -> TaskStep {
        if step == TaskCatalog.definition(.batch).steps.first {
            return reworded(step, prompt: step.prompt, help: printerBatchHelp)
        }
        if settings.source == .documentFeeder {
            let photos: TaskStep? = TaskCatalog.definition(.photos).steps.first
            let restore: TaskStep? = TaskCatalog.definition(.photoRestore).steps.first
            if step == photos || step == restore {
                return reworded(step, prompt: printerFeederPhotosPrompt, help: step.help)
            }
            if step == TaskCatalog.definition(.receipt).steps.first {
                return reworded(step, prompt: printerFeederReceiptPrompt, help: step.help)
            }
        }
        guard step == TaskCatalog.definition(.quickScan).steps.first else {
            return TaskCatalog.shownStep(step, settings: settings)
        }
        return reworded(step, prompt: printerTextPrompt, help: printerTextHelp)
    }

    private static func reworded(_ step: TaskStep, prompt: String, help: String) -> TaskStep {
        TaskStep(id: step.id, title: step.title, prompt: prompt, primaryActionLabel: step.primaryActionLabel,
                 skippable: step.skippable, repeats: step.repeats, requiresCapture: step.requiresCapture, help: help,
                 shortWord: step.shortWord)
    }

    static var printerTextPrompt: String { String(localized: "Preview under Scanner, tap it to choose the area, then scan.") }
    static var printerTextHelp: String { String(localized: "Then copy the text, or save the page as a picture.") }
    static var printerBatchHelp: String { String(localized: "1. Save a separator sheet under Options › Separate documents and print it. 2. Put one in front of each document after the first. 3. Load the stack and scan. 4. Check the splits in the pages, then save.") }
    static var printerFeederPhotosPrompt: String { String(localized: "Feed the photos one by one and scan.") }
    static var printerFeederReceiptPrompt: String { String(localized: "Feed each receipt and scan.") }

    /// The flatbed's preview, with its area and Choose area, while the flatbed is the source. With the feeder
    /// the printer screen shows the last scan instead: a feeder scan takes no area, and the one chosen waits
    /// for the flatbed, as on the Mac.
    public static func showsFlatbedPreview(_ settings: ScanSettings) -> Bool {
        settings.source == .flatbed
    }

    /// What the scanner tab's picture shows: the flatbed's overview (with its scan area) while it is the
    /// source and the overview is newer than the last page queued, or when no page is queued; else the last
    /// page queued, which goes with the queue (a save, a delete or Discard empties it, Undo brings it back);
    /// else nothing, and the picture says what the step asks for.
    public static func scannerPicture(flatbed: Bool, hasOverview: Bool, overviewIsNewer: Bool,
                                      pageCount: Int) -> ScannerPicture {
        if flatbed && hasOverview && (overviewIsNewer || pageCount == 0) {
            return .overview
        }
        return pageCount > 0 ? .page : .empty
    }

    /// The task the iPhone opens on: the one set up last time (kept in the settings), else Document to PDF.
    /// A photocopy or Email kept from before opens as Document: they are Save's Print… and Email… now.
    public static func launchTask(_ settings: ScanSettings) -> ScanTask {
        if let task = savingActionsAsDocument(settings).task, offers(task) {
            return task
        }
        return .document
    }

    /// The settings with a photocopy or Email task (a preset's, or one kept from before) as Document, the
    /// rest kept: on the iPhone they are Save's Print… and Email…, and the Type list does not offer them. Nothing
    /// runs after saving, as Document starts: Email's share sheet would open on every Save with nothing on
    /// the scan screen saying why. Its Compact size stays, which Options shows.
    public static func savingActionsAsDocument(_ settings: ScanSettings) -> ScanSettings {
        guard settings.task == .copy || settings.task == .email else { return settings }
        var s: ScanSettings = settings
        s.taskId = ScanTask.document.rawValue
        s.output.afterSave = AfterSaveAction.none
        return s
    }

    /// The settings with a Quick scan task (a preset's, saved in printer mode or an older build) as Document,
    /// for a preset applied in camera mode, which has no Text: its own choices stay, and its pages are
    /// collected into a PDF, as a Document's are.
    public static func cameraPreset(_ settings: ScanSettings) -> ScanSettings {
        guard settings.task == .quickScan else { return settings }
        var s: ScanSettings = settings
        s.documentMultiPage = true
        s.format = .pdf
        s.taskId = ScanTask.document.rawValue
        return s
    }

    /// The user's defaults key: the card saying why the camera is asked for was shown (`cameraOnOpen`).
    public static let cameraIntroKey = "camera.introShown"

    /// What camera mode does at launch or when it is switched to: the card saying why the camera is asked
    /// for while iOS has not asked yet and the card was never shown (the viewfinder waits for it); otherwise
    /// the camera at once where it can be used. Nothing without a camera (the Simulator), with access off or
    /// not allowed, in printer mode and under `-demoScanner` (the UI tests): the viewfinder says why itself.
    public static func cameraOnOpen(offersCamera: Bool, camera: IOSCameraAvailability, authorization: AVAuthorizationStatus,
                                    introShown: Bool, demo: Bool) -> IOSCameraOnOpen {
        guard !demo, offersCamera, camera.isAvailable else { return .stay }
        if authorization == .notDetermined && !introShown {
            return .introduce
        }
        return .open
    }

    /// Whether the book's Right to left switch is shown: while its spreads are cut at the spine for the
    /// source in use, a network scanner's scans (`PageProcessor.forScan`; `device` is the selected scanner,
    /// none while the camera is the source) or the camera's whole spreads (`PageProcessor.splitsCameraSpreads`).
    public static func showsRightToLeft(_ settings: ScanSettings, device: ScannerInfo?) -> Bool {
        PageProcessor.splitsFacingPages(settings) && (settings.taskOptions.cameraSpreads || usesNetworkScanner(device))
    }

    /// Whether this app offers a task: the tasks whose pages are collected and saved, since I13 Photos,
    /// Restore old photos and Receipts (several objects in one shot, each a page of the queue) and the ID card
    /// (front then back, then its review), since I14 Quick scan (one shot, then a picture or its text) and
    /// Archive document (with the Archive & password choices), and since I16 the photocopy (the page held on
    /// the copy screen, then printed over AirPrint). Every task is offered now.
    public static func offers(_ task: ScanTask) -> Bool {
        takesPhotos(flow: TaskCatalog.definition(task).flow)
    }

    /// Whether the scan screen takes photos for the settings' task (our camera, Photos and Files): pages
    /// collected in the queue (a document's pages, and the objects found in a shot of photos or receipts), a side of the
    /// ID card, or the page of a photocopy.
    public static func takesPhotos(_ settings: ScanSettings) -> Bool {
        takesPhotos(flow: TaskCatalog.flow(of: settings))
    }

    private static func takesPhotos(flow: TaskFlowKind) -> Bool {
        switch flow {
        case .documentQueue, .photoSplit, .receiptSplit, .idCard, .copy:
            return true
        }
    }

    /// Whether the scan screen collects pages to save (Save and the PDF or JPEG choice): the document
    /// tasks that collect pages, and Photos and Receipts, whose objects found in a shot are pages of the queue
    /// (`AppState.listsFoundObjects`). The ID card is saved from its review, a Quick scan from its own screen.
    public static func collectsPages(_ settings: ScanSettings) -> Bool {
        switch TaskCatalog.flow(of: settings) {
        case .documentQueue:
            return settings.documentMultiPage
        case .photoSplit, .receiptSplit:
            return true
        case .idCard, .copy:
            return false
        }
    }

    /// Whether a Lazy Scan document or a PDF can be added to the queue: only Document with Collect pages before
    /// saving on. Photos and Receipts collect pages too, but cut the pages they are given into objects.
    public static func takesWholePages(_ settings: ScanSettings) -> Bool {
        PhotoImport.isOffered(settings) && settings.documentMultiPage
    }

    /// Whether the scan screen offers Save and the save options in Options: while it collects pages, and while a document
    /// task holds pages it no longer collects (Collect pages before saving turned off over them, or the pages
    /// a failed save at once put back), so that queued pages always have a Save.
    public static func offersSave(_ settings: ScanSettings, pageCount: Int) -> Bool {
        collectsPages(settings) || (TaskCatalog.flow(of: settings) == .documentQueue && pageCount > 0)
    }

    /// Whether the scan screen offers the PDF's choices (its size, Archive and Password): its Save writes a
    /// PDF.
    public static func offersPDFOptions(_ settings: ScanSettings) -> Bool {
        collectsPages(settings) && !savesImages(settings) && settings.format.savesPDF(collectsPages: true)
    }

    /// Whether the ID card's review shows Password: its Save writes a PDF, which takes the password set in
    /// Options (Save as) though the card has no Export of its own.
    public static func reviewOffersPassword(_ settings: ScanSettings) -> Bool {
        settings.format.pageFormat == .pdf
    }

    /// Why a task is not offered yet: the tile's one visible line.
    public static var notYetReason: String { String(localized: "Not in this version yet") }

    /// Whether the scan screen can offer our own camera (`CameraScreen`), the default way to take pages:
    /// wherever photos are taken (`takesPhotos`), as photos are imported.
    public static func offersOwnCamera(_ settings: ScanSettings) -> Bool {
        takesPhotos(settings)
    }

    /// The user's defaults key of the phone's mode (`IOSScanMode`): the camera, the default, or printer mode.
    public static let scanModeKey = "scan.mode"

    /// The user's defaults key of the screen the app opens on (`IOSScanMode`): the camera unless the scanner
    /// is picked in Options. The mode left last is not what the next launch shows.
    public static let startModeKey = "scan.startMode"

    /// At launch: the mode becomes the one picked to start with.
    public static func applyStartMode(_ defaults: UserDefaults) {
        // Without a mode yet this is a first run or a build from before the two modes, which
        // `migratedScanner` still has to read; the camera is the default then anyway.
        guard defaults.object(forKey: scanModeKey) != nil else { return }
        let start: IOSScanMode = defaults.string(forKey: startModeKey).flatMap(IOSScanMode.init(rawValue:)) ?? .camera
        defaults.set(start.rawValue, forKey: scanModeKey)
    }

    /// The user's defaults key of the scanner printer mode scans with: the ID of the one picked last. It is
    /// kept while the camera is in use, so switching back to printer mode finds it again.
    public static let scannerKey = "scan.scanner"

    /// The user's defaults key: the camera's filter was set to Original once (`adoptOriginalFilter`).
    static let originalFilterKey = "camera.originalFilter"

    /// Once per install, on a first run and over settings kept from a build before the filters alike: the
    /// camera's pages start at Original on the phone (the Mac keeps the shared default, Enhanced). A filter
    /// chosen after that is kept.
    @MainActor
    static func adoptOriginalFilter(_ state: AppState, defaults: UserDefaults) {
        guard !defaults.bool(forKey: originalFilterKey) else { return }
        defaults.set(true, forKey: originalFilterKey)
        state.settings.taskOptions.cameraFilter = .original
    }

    /// The key builds before the two modes kept the source under: empty for the camera, else a scanner's ID.
    static let oldSourceKey = "scan.source"

    /// Once, from a build that kept the source under `oldSourceKey`: the scanner picked there, for printer
    /// mode, when no mode was kept yet and it is not the demo scanner; the old key goes either way.
    static func migratedScanner(_ defaults: UserDefaults) -> String? {
        guard let old = defaults.string(forKey: oldSourceKey) else { return nil }
        defaults.removeObject(forKey: oldSourceKey)
        guard defaults.object(forKey: scanModeKey) == nil, !old.isEmpty, !old.hasPrefix("mock:") else { return nil }
        return old
    }

    /// The scanner the pages come from: in printer mode the remembered one (`scanner`, its ID) while it is
    /// listed and selected; nil in camera mode, and in printer mode until that scanner is found again. A
    /// scanner found on its own never takes its place.
    public static func printerScanner(_ mode: IOSScanMode, scanner: String, selected: String?,
                                      devices: [ScannerInfo]) -> ScannerInfo? {
        guard mode == .printer, !scanner.isEmpty, scanner == selected else { return nil }
        for device in devices where device.id == scanner {
            return device
        }
        return nil
    }

    /// The listed row of the remembered scanner: its own, or the one of the connection the app moved that
    /// scanner to (`groups`, `DeviceMerge`); nil when the scanner is not listed, or none was picked.
    public static func listedScanner(_ scanner: String, devices: [ScannerInfo], groups: [DeviceGroup]) -> String? {
        guard !scanner.isEmpty else { return nil }
        var connections: [String] = [scanner]
        for group in groups where group.members.contains(where: { (member: ScannerInfo) -> Bool in member.id == scanner }) {
            for member in group.members {
                connections.append(member.id)
            }
        }
        for device in devices where connections.contains(device.id) {
            return device.id
        }
        return nil
    }

    /// The scanner the selection follows in `mode`: the remembered one's listed row in printer mode
    /// (`listedScanner`); none with the camera, or while that scanner is not listed.
    public static func followedScanner(_ mode: IOSScanMode, scanner: String, devices: [ScannerInfo],
                                       groups: [DeviceGroup]) -> String? {
        guard mode == .printer else { return nil }
        return listedScanner(scanner, devices: devices, groups: groups)
    }

    /// What printer mode says while no scanner is in use, on the card in the step card's place and on the
    /// status line: where the search is, as the Scanner options show it (the explanation card's title before
    /// the first search, Local Network access being off, "Looking for scanners…", "No scanner found"), or,
    /// with scanners listed (`found`: none picked yet, or the one picked not among them), that none is in use.
    public static func noScannerLine(explained: Bool, denied: Bool, searching: Bool, found: Bool) -> String {
        if !explained { return IOSNetworkText.explanationTitle }
        if denied { return IOSNetworkText.deniedLine }
        if found { return noScannerInUse }
        if searching { return IOSNetworkText.searching }
        return IOSNetworkText.noScanner
    }

    /// Printer mode's line while scanners are listed and none is in use, and its card's way to the Scanner
    /// options.
    public static var noScannerInUse: String { String(localized: "No scanner is in use.") }
    public static var pickScannerLabel: String { String(localized: "Pick a scanner") }
    /// What VoiceOver says after the scanner tab's round Scan button.
    public static var scanHint: String { String(localized: "Starts the scanner") }

    /// Whether our camera takes page after page (continuous capture): the task collects several pages in
    /// the queue, or takes the ID card's front then its back, so the camera stays open after each photo
    /// and the corner editor opens only for a page (or card) its photo's own search is unsure of.
    public static func capturesContinuously(_ settings: ScanSettings) -> Bool {
        TaskCatalog.flow(of: settings) == .idCard || collectsPages(settings)
    }

    /// The format the settings save the collected pages as: a PDF, a picture a page, a Word document or a text
    /// file. A .txt beside the PDF is one of the PDF's choices (`PDFOptionsSection`).
    public static func exportFormat(_ settings: ScanSettings) -> OutputFormat {
        settings.format
    }

    /// The collected pages are saved as pictures (`AppState.saveImages`), not as one file (`savePDF`).
    public static func savesImages(_ settings: ScanSettings) -> Bool {
        settings.format.isImageFormat
    }

    /// Saves the queue as Save does, without After saving's steps: into the PDF picked, as pictures, or as the
    /// format's document.
    @MainActor
    public static func saveQueue(_ state: AppState) {
        if state.appendTarget == nil && savesImages(state.settings) {
            state.saveImages()
        } else {
            state.savePDF()
        }
    }

    /// The main Save button's accessibility label: just "Save", or "Add to Contract.pdf" while the pages go
    /// into a PDF picked, which is a different action. The format and the pages are in `saveDetail`.
    public static func saveTitle(target: URL?) -> String {
        if let target {
            return PDFAppender.saveTitle(target.lastPathComponent)
        }
        return String(localized: "Save")
    }

    /// The caption at the picture's foot while the pages go into the PDF picked: "Adding to Contract.pdf".
    public static func addingCaption(_ fileName: String) -> String {
        String(localized: "Adding to \(fileName)")
    }

    /// What the title leaves out, for the button's accessibility value: "Save JPEG (3 pages)" for pictures
    /// (`AppState.imagesSaveTitle`), else the queue's own ("Save PDF (3 pages)", "Save Word"); the pages
    /// alone ("3 pages") while they go into a PDF picked.
    public static func saveDetail(_ settings: ScanSettings, plan: SavePlan, target: URL?) -> String {
        if target != nil {
            return L10n.plural(plan.pageCount, one: "{0} page", other: "{0} pages")
        }
        if savesImages(settings) {
            return AppState.imagesSaveTitle(settings.format, pageCount: plan.pageCount)
        }
        return plan.saveTitle(settings.format)
    }

    /// The question before something that would leave the queued pages without a Save (the ID card,
    /// `AppState.pagesLeftBehind(by:)`, a preset, a document opened as new): "Keep the 3 pages?".
    public static func keepPagesTitle(_ count: Int) -> String {
        L10n.plural(count, one: "Keep the page?", other: "Keep the {0} pages?")
    }

    /// The question's line: why the pages would be left (`keepPagesReason`), then what can be done with them,
    /// without saving when Save first is not offered.
    public static func keepPagesLine(_ reason: String, count: Int, canSave: Bool) -> String {
        if canSave {
            return L10n.plural(count, one: "{1} Save it first, or discard it.", other: "{1} Save them first, or discard them.", reason)
        }
        return L10n.plural(count, one: "{1} It cannot be saved now: discard it, or cancel to keep it.",
                           other: "{1} They cannot be saved now: discard them, or cancel to keep them.", reason)
    }

    /// "ID card does not collect pages.": the one kind that keeps no pages, with its own steps.
    public static func keepPagesReason(_ kind: IOSScanKind) -> String {
        String(localized: "\(kind.title) does not collect pages.")
    }

    /// "The preset “Receipts” does not collect pages."
    public static func keepPagesReason(preset name: String) -> String {
        String(localized: "The preset \u{201C}\(name)\u{201D} does not collect pages.")
    }

    /// "“Trip.lsdoc” opens in their place."
    public static func keepPagesReason(package fileName: String) -> String {
        String(localized: "\u{201C}\(fileName)\u{201D} opens in their place.")
    }

    public static func discardPagesLabel(_ count: Int) -> String {
        L10n.plural(count, one: "Discard {0} page", other: "Discard {0} pages")
    }

    /// The question's button that saves the pages as Save would before the kind changes: "Save PDF first",
    /// "Save JPEG first", "Add to Contract.pdf first".
    public static func saveFirstLabel(_ settings: ScanSettings, pageCount: Int, target: URL?) -> String {
        if let target {
            return String(localized: "\(PDFAppender.saveTitle(target.lastPathComponent)) first")
        }
        if savesImages(settings) {
            return String(localized: "\(AppState.imagesSaveTitle(settings.format, pageCount: 1)) first")
        }
        return String(localized: "\(settings.format.saveTitle) first")
    }

    /// The question before camera mode ends a stack turned over by hand with pages in: its steps go as the
    /// sides turn back to both (`AppState.userSelectNoDevice`). Keep pages as they are does first what the
    /// stack's own buttons would.
    public static var finishStackTitle: String { String(localized: "Finish the stack first?") }
    public static var finishStackLine: String { String(localized: "The front sides wait for their backs. Camera mode ends the stack; the pages stay as they are.") }
    public static var keepStackLabel: String { String(localized: "Keep pages as they are") }

    /// The types the camera's Options list offers. Text is the page viewer's, so it is not one here; the
    /// scanner tab's list still offers it.
    public static let cameraKinds: [IOSScanKind] = [.photos, .document, .receipts, .idCard, .book]

    /// The user's defaults key of camera mode's Items in frame (`IOSItemsInFrame`).
    public static let itemsInFrameKey = "camera.itemsInFrame"

    /// Whether camera mode offers Items in frame for the settings: Photo, and a Document taken a side at a
    /// time. The ID card, a book and Both sides take their pages their own way.
    public static func offersItemsInFrame(_ settings: ScanSettings) -> Bool {
        switch TaskCatalog.flow(of: settings) {
        case .photoSplit:
            return true
        case .documentQueue:
            return shownKind(settings) == .document && settings.task != .twoSided
        case .receiptSplit, .idCard, .copy:
            return false
        }
    }

    /// What a camera shot goes by: the Items in frame kept in `defaults` (Auto when none is), or nil where
    /// it is not offered, for the kind's own way.
    public static func itemsInFrame(_ settings: ScanSettings, defaults: UserDefaults) -> IOSItemsInFrame? {
        guard offersItemsInFrame(settings) else { return nil }
        return IOSItemsInFrame(rawValue: defaults.string(forKey: itemsInFrameKey) ?? "") ?? .auto
    }

    /// The user's defaults key of camera mode's Straighten pages.
    public static let straightenKey = "camera.straighten"

    /// Whether camera mode offers Straighten pages for the settings: a Document taken a side at a time and a
    /// Book, and Both sides, whose shots are straightened too (`PageProcessor.forCapture` ignores
    /// `autoStraighten`). Photos, receipts and the ID card are not pages.
    public static func offersStraighten(_ settings: ScanSettings) -> Bool {
        guard TaskCatalog.flow(of: settings) == .documentQueue else { return false }
        let kind: IOSScanKind = shownKind(settings)
        return kind == .document || kind == .book
    }

    /// Whether a camera shot is straightened: Straighten pages kept in `defaults` (on when none is), where it
    /// is offered.
    public static func straightensShots(_ settings: ScanSettings, defaults: UserDefaults) -> Bool {
        offersStraighten(settings) && (defaults.object(forKey: straightenKey) as? Bool ?? true)
    }

    /// The user's defaults key of the Options' choices `kind` was left with (`rememberChoices`).
    static func choicesKey(_ kind: IOSScanKind) -> String {
        "scan.choices.\(kind.rawValue)"
    }

    /// Keeps the Options' choices of the kind the settings are shown as in `defaults`, for when that kind is
    /// picked again (`restoringChoices`).
    static func rememberChoices(_ settings: ScanSettings, defaults: UserDefaults) {
        let choices: IOSKindChoices = IOSKindChoices(
            format: settings.format, pdfSize: settings.output.pdfSize,
            archival: IOSPDFOptions.archivalShown(settings.output), alsoSaveText: settings.output.alsoSaveText,
            eachPage: savesEachPage(settings), colorMode: settings.colorMode, adjustments: settings.adjustments,
            namingTemplate: settings.namingTemplate)
        guard let data = try? JSONEncoder().encode(choices) else { return }
        defaults.set(data, forKey: choicesKey(shownKind(settings)))
    }

    /// The settings of `kind`'s task, just started, with the Options' choices the kind was left with laid back
    /// over them (none kept: unchanged): the format, the PDF's size, PDF/A unless a password was turned on
    /// since (a PDF/A file can't have one), Also .txt, One PDF per page, the colour, the adjustments (restored
    /// colours make Photos Restore old photos again) and the file name, unless it was Separate documents',
    /// which starts afresh as Both sides does. The folder, the paper and the password are never the kind's.
    static func restoringChoices(for kind: IOSScanKind, in settings: ScanSettings,
                                 defaults: UserDefaults) -> ScanSettings {
        guard let data = defaults.data(forKey: choicesKey(kind)),
              let kept = try? JSONDecoder().decode(IOSKindChoices.self, from: data) else { return settings }
        var s: ScanSettings = settings
        if s.task == .photos && kept.adjustments.restoreFadedColors {
            s.taskId = ScanTask.photoRestore.rawValue
        }
        s.format = kept.format
        s.output.pdfSize = kept.pdfSize
        s.output = IOSPDFOptions.settingArchival(kept.archival, in: s.output)
        s.output.alsoSaveText = kept.alsoSaveText
        if kept.eachPage {
            s = settingEachPage(true, in: s)
        }
        s.colorMode = kept.colorMode
        s.adjustments = kept.adjustments
        if kept.namingTemplate != separateNames {
            s.namingTemplate = kept.namingTemplate
        }
        return s
    }

    /// A kind picked on the Options sheet's Type: the Options' choices of the kind shown
    /// are kept (`rememberChoices`), the picked kind's task starts as its tile did, with the availability check,
    /// fresh steps and the fit to the scanner (`AppState.startTask`; `discardPages(andStart:)` when the queued
    /// pages go), and the choices that kind was left with go back over the task's (`restoringChoices`). False
    /// when the task was refused.
    @MainActor
    @discardableResult
    static func startKind(_ kind: IOSScanKind, in state: AppState, discardingPages: Bool = false,
                          defaults: UserDefaults) -> Bool {
        rememberChoices(state.settings, defaults: defaults)
        let started: Bool = discardingPages ? state.discardPages(andStart: kind.task) : state.startTask(kind.task)
        if started {
            state.settings = restoringChoices(for: kind, in: state.settings, defaults: defaults)
        }
        return started
    }

    /// Camera mode has no Text: its task, kept from printer mode or an older build, starts the Document over
    /// in camera mode, with the choices it was left with (`startKind`), as do settings left without a task in
    /// printer mode, since camera mode always shows a kind.
    @MainActor
    static func adoptCameraKind(_ state: AppState, defaults: UserDefaults) {
        if let task = state.settings.task, cameraKinds.contains(kind(of: task)) { return }
        startKind(.document, in: state, defaults: defaults)
    }

    /// The `.lsdoc` type the app declares (Info.plist's UTExportedTypeDeclarations), which Files offers
    /// beside photos and PDFs.
    public static let packageType: UTType = UTType(exportedAs: "com.lazyscan.package", conformingTo: .data)

    /// The Save row's button that shares the queue as one `.lsdoc` (`sharePackage`).
    public static var sharePackageLabel: String { String(localized: "Share as Lazy Scan file") }
    /// The package banner's Open as new in a kind that keeps no pages: it switches to Document first.
    public static var openPackageInDocumentLabel: String { String(localized: "Open in Document") }

    /// Whether a file opened in this app (AirDrop, Files, Mail) or picked in Files is a Lazy Scan
    /// document: it goes to the scan screen's banner (`openPackage`), never into a task's import.
    public static func isPackage(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == CompanionPackage.fileExtension
    }

    /// Offers the `.lsdoc` at `url` on the scan screen's banner (`AppState.openPackage(at:)`). It is copied
    /// into a folder of its own first, through its security scope and a coordinated read: the package is
    /// read a picture at a time while its pages are decoded, and a file opened in place may be another
    /// app's (iCloud Drive, a file provider). The copy goes once it is read.
    @MainActor
    public static func openPackage(_ url: URL, in state: AppState) async {
        // One open after another, so the file opened last is the one offered however long its copy
        // takes (a file in iCloud Drive is downloaded first).
        let previous: Task<Void, Never>? = lastPackageOpen
        let open: Task<Void, Never> = Task { @MainActor in
            await previous?.value
            await openPackageNow(url, in: state)
        }
        lastPackageOpen = open
        await open.value
    }

    @MainActor private static var lastPackageOpen: Task<Void, Never>?

    @MainActor private static func openPackageNow(_ url: URL, in state: AppState) async {
        let copied: Result<URL, Error> = await Task.detached(priority: .userInitiated) { () -> Result<URL, Error> in
            Result { try IOSShell.copyPackage(url) }
        }.value
        switch copied {
        case .success(let copy):
            await state.openPackage(at: copy)
            try? FileManager.default.removeItem(at: copy.deletingLastPathComponent())
        case .failure(let error):
            state.errorMessage = PhotoImport.unreadableMessage(url.lastPathComponent, detail: error.localizedDescription)
        }
    }

    /// A copy of the file at `url`, under its own name, in a new folder in the temporary folder.
    static func copyPackage(_ url: URL) throws -> URL {
        let folder: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectoryCompleteUnlessOpen(at: folder)
        let copy: URL = folder.appendingPathComponent(url.lastPathComponent)
        do {
            try IOSPDFAppend.access(url, writing: false) { (file: URL) throws -> Void in
                try FileManager.default.copyItem(at: file, to: copy)
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return copy
    }

    /// The folder the queue is written in to be shared, emptied before each `.lsdoc` is written.
    static var packageShareFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Shared documents", isDirectory: true)
    }

    /// Share as Lazy Scan file: the queue written as one `.lsdoc` in `packageShareFolder`
    /// (`AppState.exportPackage(to:)`, named as the next saved file would be), then the share sheet with
    /// it. Returns the file; nil when it could not be written, which the error alert says.
    @MainActor
    @discardableResult
    public static func sharePackage(_ state: AppState) async -> URL? {
        let folder: URL = packageShareFolder
        do {
            try? FileManager.default.removeItem(at: folder)
            try FileManager.default.createDirectoryCompleteUnlessOpen(at: folder)
            let url: URL = try await state.exportPackage(to: folder)
            state.runFileAction(.share, urls: [url])
            return url
        } catch {
            state.errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Whether the scan screen offers Send to computer: it collects pages (`collectsPages`) and a computer
    /// is paired that still knows this phone.
    public static func offersSendToComputer(_ settings: ScanSettings, status: CompanionStatus) -> Bool {
        guard collectsPages(settings) else { return false }
        switch status {
        case .notPaired, .unpaired:
            return false
        case .checking, .reachable, .unreachable:
            return true
        }
    }

    /// The companion (I20): its files in `folder` (the network folder, out of backups), the device secret
    /// in `secrets` (the Keychain), whether a desktop that does not answer is on the network and where it
    /// is now from `browser`'s DNS-SD browse. While the app is in front with a desktop paired, what the
    /// desktop holds for the phone is taken (`pullFromDesktop`, from becoming active until the app goes to
    /// the background); each time it comes to the front the desktop is checked, browsing while the check
    /// runs and, when it did not answer, a few seconds more before it is checked again, and what waits in
    /// the outbox is sent. A desktop that did not answer and is found at new addresses is checked there.
    @MainActor
    static func setUpCompanion(_ state: AppState, folder: URL, secrets: any CompanionSecretStore,
                               browser: IOSCompanionBrowser?, lifecycle: any PlatformLifecycle) {
        state.setUpCompanion(in: folder, secrets: secrets)
        if let browser {
            state.companionDesktopSeenOnNetwork = { [weak browser] (desktopId: String) -> Bool in
                browser?.isSeen(desktopId) ?? false
            }
            state.companionAccessDenied = { [weak browser] () -> Bool in
                browser?.accessDenied ?? false
            }
            browser.onFound = { [weak state] (desktopId: String, addresses: [String], port: Int) -> Void in
                guard let state else { return }
                Task { @MainActor in
                    if await state.desktopFound(id: desktopId, addresses: addresses, port: port),
                       case .unreachable = state.companionStatus {
                        await state.checkDesktop()
                        await state.drainOutbox()
                    }
                }
            }
        }
        lifecycle.observeDidBecomeActive { [weak state] in
            guard let state, state.companionDesktop != nil else { return }
            state.pullFromDesktop()
            Task { @MainActor in
                browser?.begin()
                await state.checkDesktop()
                if browser != nil, case .unreachable = state.companionStatus {
                    // A refusal comes sooner than the browse: let it see the desktop, or find it elsewhere.
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if case .unreachable = state.companionStatus {
                        await state.checkDesktop()
                    }
                }
                browser?.end()
                await state.drainOutbox()
            }
        }
        lifecycle.observeWillTerminate { [weak state] in
            state?.stopPulling()
        }
    }

    /// The kind a task is shown as on the iPhone (the Options sheet's types): the
    /// document tasks are a Document with its options set (the feeder, both sides, separate documents, the
    /// format, PDF/A, Email…, Print…), Restore old photos is Photos with faded colours restored, Quick scan
    /// is Text.
    public static func kind(of task: ScanTask) -> IOSScanKind {
        switch task {
        case .document, .feeder, .twoSided, .batch, .email, .word, .archive, .copy:
            return .document
        case .photos, .photoRestore:
            return .photos
        case .receipt:
            return .receipts
        case .idCard:
            return .idCard
        case .book:
            return .book
        case .quickScan:
            return .text
        }
    }

    /// The kind the settings are shown as, settings left without a task included (`TaskCatalog.infer`).
    public static func shownKind(_ settings: ScanSettings) -> IOSScanKind {
        kind(of: TaskCatalog.infer(settings))
    }

    /// The Options sheet's types, the iPad sidebar's rows and camera mode's kinds (`cameraKinds`): one per
    /// kind, in `order`, each as its task's card can be picked.
    public static func kindTiles(_ cards: [TaskCard], current: IOSScanKind,
                                 order: [IOSScanKind] = IOSScanKind.allCases) -> [IOSKindTile] {
        var tiles: [IOSKindTile] = []
        for kind in order {
            guard let card = cards.first(where: { (candidate: TaskCard) -> Bool in
                candidate.definition.task == kind.task
            }) else { continue }
            tiles.append(IOSKindTile(kind: kind, summary: card.summary, availability: availability(card),
                                     isCurrent: kind == current))
        }
        return tiles
    }

    /// The line under the Options sheet's Type for the kinds that are dimmed, a sentence for each reason in
    /// the list's order ("ID card, Book and Text need a flatbed."); nil while none is.
    public static func unavailableKindsLine(_ tiles: [IOSKindTile]) -> String? {
        let dimmed: [IOSKindTile] = tiles.filter { (tile: IOSKindTile) -> Bool in !tile.availability.isAvailable }
        var reasons: [String] = []
        for tile in dimmed {
            if let reason = tile.availability.reason, !reasons.contains(reason) {
                reasons.append(reason)
            }
        }
        var sentences: [String] = []
        for reason in reasons {
            var titles: [String] = []
            for tile in dimmed where tile.availability.reason == reason {
                titles.append(tile.kind.title)
            }
            sentences.append(unavailableSentence(titles, reason: reason))
        }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    /// The titles, then the reason as the rest of the sentence: "Needs a flatbed" is "needs a flatbed" for one
    /// kind and "need a flatbed" for several.
    private static func unavailableSentence(_ titles: [String], reason: String) -> String {
        var names: String = titles.joined(separator: ", ")
        if titles.count > 1, let last = titles.last {
            names = L10n.t("{0} and {1}", titles.dropLast().joined(separator: ", "), last)
        }
        if reason == TaskCatalog.needsFlatbedReason {
            return L10n.plural(titles.count, one: "{1} needs a flatbed.", other: "{1} need a flatbed.", names)
        }
        if reason == TaskCatalog.needsFeederReason {
            return L10n.plural(titles.count, one: "{1} needs a document feeder.", other: "{1} need a document feeder.", names)
        }
        let trimmed: String = reason.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return "\(names): \(trimmed)."
    }

    // The Options switches below set only what they are about, never through `TaskCatalog.apply`, which
    // would reset the other choices; the task changes under the hood where its flow needs it.

    /// Both sides on the camera: the two-sided task, whose camera steps (flip & capture, or fronts first)
    /// need it, with the feeder and both sides it fits and the pages collected, since the steps pair the
    /// sides in the queue; off, Document again on the flatbed, as its tile was.
    public static func settingBothSides(_ on: Bool, in settings: ScanSettings) -> ScanSettings {
        var s: ScanSettings = settings
        if on {
            // One task at a time: separator sheets belong to Separate documents.
            if separatesDocuments(s) { s = settingSeparate(false, in: s) }
            s.source = .documentFeeder
            s.duplex = .both
            s.documentMultiPage = true
        } else {
            s.source = .flatbed
            s.duplex = .off
        }
        s.document.removeBlankPages = on
        s.document.autoStraighten = on
        s.document.autoRotate = on
        s.taskId = (on ? ScanTask.twoSided : ScanTask.document).rawValue
        return s
    }

    /// Separate documents is on: the pages are split at patch code or QR sheets.
    public static func separatesDocuments(_ settings: ScanSettings) -> Bool {
        settings.document.splitMode == .separatorSheet || settings.document.splitMode == .barcode
    }

    /// Separate documents: the Separate documents task (its New document button and separator sheets),
    /// split at patch code sheets unless QR codes were chosen, on the feeder it needs, each file named with
    /// its document's name as the task names them; off, one document on the flatbed.
    public static func settingSeparate(_ on: Bool, in settings: ScanSettings) -> ScanSettings {
        var s: ScanSettings = settings
        if on {
            // One task at a time: Both sides ends, its sides and straightening with it.
            if s.task == .twoSided { s = settingBothSides(false, in: s) }
            if s.document.splitMode != .barcode { s.document.splitMode = .separatorSheet }
            s.source = .documentFeeder
            s.namingTemplate = separateNames
        } else {
            s.document.splitMode = SplitMode.none
            s.source = .flatbed
            if s.namingTemplate == separateNames { s.namingTemplate = "Scan {date} {counter}" }
        }
        s.document.removeBlankPages = on
        s.taskId = (on ? ScanTask.batch : ScanTask.document).rawValue
        return s
    }

    /// `settingSeparate`, adapted to the scanner in use: the switch's and the split choice's way of turning
    /// Separate documents on or off.
    @MainActor
    static func setSeparate(_ on: Bool, in state: AppState) {
        let s: ScanSettings = settingSeparate(on, in: state.settings)
        state.settings = SettingsAdapter.adapt(s, to: state.capabilities).settings
    }

    /// A split choice made on the Separate documents page. For the Document kind, going to or from separator
    /// sheets and codes is Separate documents turned on or off, as its switch does, so the task, the feeder and
    /// the file names follow the choice; the other choices only set the split. Where the switch is dimmed
    /// (no feeder) or Both sides is on, the choice only sets the split too, so the task and the fronts
    /// already taken stay, and leaving Separate for another split keeps the source.
    @MainActor
    static func setSplit(_ mode: SplitMode, in state: AppState) {
        let separates: Bool = mode == SplitMode.separatorSheet || mode == SplitMode.barcode
        if shownKind(state.settings) == .document && state.activeTask != .twoSided
            && separates != separatesDocuments(state.settings) {
            if separates {
                let availability: TaskAvailability = TaskCatalog.availability(of: .batch, capabilities: state.capabilities)
                if availability.isAvailable {
                    setSeparate(true, in: state)
                }
            } else {
                var s: ScanSettings = settingSeparate(false, in: state.settings)
                if mode != SplitMode.none { s.source = state.settings.source }
                state.settings = SettingsAdapter.adapt(s, to: state.capabilities).settings
            }
        }
        state.setSplitMode(mode)
    }

    /// The Separate documents task's file names (`TaskCatalog.apply`), with each document's name.
    static let separateNames = "Document {label} {date} {counter}"

    /// One PDF per page: a new document every sheet (`SplitMode.sheetCount`, one sheet each).
    public static func savesEachPage(_ settings: ScanSettings) -> Bool {
        settings.document.splitMode == .sheetCount
            && DocumentSplitter.clampSheetCount(settings.document.splitSheetCount) == 1
    }

    /// That switch's name: a sheet's front and back stay together, so with both sides it is per sheet. The
    /// camera pairs the sides only for Both sides, whatever source and sides printer mode left in the settings.
    public static func eachPageTitle(_ settings: ScanSettings, camera: Bool = false) -> String {
        let sheets: Bool = camera
            ? settings.task == .twoSided
            : settings.source == .documentFeeder && settings.duplex != .off
        return sheets ? String(localized: "One PDF per sheet") : String(localized: "One PDF per page")
    }

    public static func settingEachPage(_ on: Bool, in settings: ScanSettings) -> ScanSettings {
        var s: ScanSettings = settings
        s.document.splitMode = on ? .sheetCount : SplitMode.none
        if on { s.document.splitSheetCount = 1 }
        return s
    }

    /// Restore faded colours for Photos: the Restore old photos task's adjustments and PNG files; off,
    /// Photos as JPEGs again. A format that is not a picture's (a PDF, Word) chosen in Options stays.
    public static func settingRestore(_ on: Bool, in settings: ScanSettings) -> ScanSettings {
        var s: ScanSettings = settings
        s.adjustments.restoreFadedColors = on
        s.adjustments.autoEnhance = on
        if s.format.isImageFormat {
            s.format = on ? .png : .jpeg
        }
        s.taskId = (on ? ScanTask.photoRestore : ScanTask.photos).rawValue
        return s
    }

    /// Whether the drawer's Colour group offers the camera's filters (Original, Enhanced, Grayscale, B&W): for
    /// the kinds that collect pages, whose colour pages take the filter (`DocumentEnhancer.mode(for:)`); the
    /// others keep the colour modes.
    public static func offersFilters(_ settings: ScanSettings) -> Bool {
        TaskCatalog.flow(of: settings) == .documentQueue
    }

    /// The filter the Colour group shows: the colour mode for gray and black and white, which the scanner and
    /// the saved files follow too, else the camera's filter.
    public static func drawerFilter(_ settings: ScanSettings) -> CaptureFilter {
        switch settings.colorMode {
        case .grayscale: return .grayscale
        case .blackWhite: return .blackAndWhite
        case .color: return settings.taskOptions.cameraFilter ?? .enhanced
        }
    }

    /// `filter` picked in the Colour group: Grayscale and B&W set the colour mode (the camera's filter kept for
    /// when colour comes back), Original and Enhanced set colour and the camera's filter.
    public static func settingDrawerFilter(_ filter: CaptureFilter, in settings: ScanSettings) -> ScanSettings {
        var s: ScanSettings = settings
        switch filter {
        case .grayscale:
            s.colorMode = .grayscale
        case .blackAndWhite:
            s.colorMode = .blackWhite
        case .original, .enhanced:
            s.colorMode = .color
            s.taskOptions.cameraFilter = filter
        }
        return s
    }

    /// An option that leaves the task unfit (Word saved as a PDF, PDF/A turned off) keeps its kind: the
    /// kind's own task when the settings fit it, else none, as a change by hand does.
    public static func keepingKind(_ settings: ScanSettings) -> ScanSettings {
        guard let task = settings.task, !TaskCatalog.fits(task, settings) else { return settings }
        var s: ScanSettings = settings
        let base: ScanTask = kind(of: task).task
        s.taskId = TaskCatalog.fits(base, s) ? base.rawValue : nil
        return s
    }

    /// Whether a start-screen tile can be picked, and if not, why: a task this app does not offer
    /// yet says so; otherwise the card's own availability (a scanner without a feeder, say).
    public static func availability(_ card: TaskCard) -> TaskAvailability {
        if !offers(card.definition.task) {
            return TaskAvailability(isAvailable: false, reason: notYetReason)
        }
        return card.availability
    }

    /// The SF Symbol for a task's icon key (`TaskDefinition.iconKey`), as on the Mac.
    public static func systemImage(_ iconKey: String) -> String {
        switch iconKey {
        case "document": return "doc.text"
        case "feeder": return "doc.on.doc"
        case "photos": return "photo.on.rectangle.angled"
        case "restore": return "wand.and.stars"
        case "quick": return "bolt"
        case "email": return "envelope"
        case "twoSided": return "arrow.left.arrow.right.square"
        case "idCard": return "person.text.rectangle"
        case "copy": return "printer"
        case "word": return "doc.richtext"
        case "receipt": return "receipt"
        case "batch": return "square.stack.3d.down.right"
        case "book": return "book"
        case "archive": return "archivebox"
        default: return "scanner"
        }
    }
}

/// The phone's two modes, which are also where the pages come from: the camera, the default, or a scanner
/// (printer mode). Kept in the user's defaults under `IOSShell.scanModeKey`.
public enum IOSScanMode: String, CaseIterable, Identifiable, Sendable {
    case camera
    case printer

    public var id: String { rawValue }

    /// The tab's name where a person picks one (Options > Start screen).
    public var title: String {
        switch self {
        case .camera: return String(localized: "Camera")
        case .printer: return String(localized: "Scanner")
        }
    }
}

/// How many things a camera shot of Photo or Document holds (`IOSShell.itemsInFrame`): Auto splits the shot
/// when more than one is found, One never does (a page with slips on it), Several always does.
public enum IOSItemsInFrame: String, CaseIterable, Identifiable, Sendable {
    case auto
    case one
    case several

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return String(localized: "Auto")
        case .one: return String(localized: "One")
        case .several: return String(localized: "Several")
        }
    }
}

/// The Options' choices a kind was left with, kept in the user's defaults (`IOSShell.rememberChoices`).
private struct IOSKindChoices: Codable {
    let format: OutputFormat
    let pdfSize: PDFSizePreset
    let archival: Bool
    let alsoSaveText: Bool
    let eachPage: Bool
    let colorMode: ColorMode
    let adjustments: AdjustmentSettings
    let namingTemplate: String
}

/// What the iPhone's scan screen asks first, as the Type in Options: what is being scanned. The rest (the
/// feeder, both sides, separate documents, the format, PDF/A, email and printing) is an option or an action
/// in Options.
public enum IOSScanKind: String, CaseIterable, Identifiable, Sendable {
    case document
    case photos
    case receipts
    case idCard
    case book
    case text

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .document: return String(localized: "Document")
        case .photos: return String(localized: "Photos")
        case .receipts: return String(localized: "Receipts")
        case .idCard: return String(localized: "ID card")
        case .book: return String(localized: "Book")
        case .text: return String(localized: "Text")
        }
    }

    public var subtitle: String {
        switch self {
        case .document: return String(localized: "Pages into a PDF")
        case .photos: return String(localized: "Prints and pictures")
        case .receipts: return String(localized: "Named by the day saved")
        case .idCard: return String(localized: "Front and back on one page")
        case .book: return String(localized: "Pages or whole spreads")
        case .text: return String(localized: "One scan, copy its text")
        }
    }

    /// The kind in camera mode's Type list: one print or several there, so Photo.
    public var cameraTitle: String {
        self == .photos ? String(localized: "Photo") : title
    }

    public var symbol: String {
        switch self {
        case .document: return "doc.text"
        case .photos: return "photo.on.rectangle.angled"
        case .receipts: return "receipt"
        case .idCard: return "person.text.rectangle"
        case .book: return "book"
        case .text: return "text.viewfinder"
        }
    }

    /// The task picking the kind starts, as its tile did.
    public var task: ScanTask {
        switch self {
        case .document: return .document
        case .photos: return .photos
        case .receipts: return .receipt
        case .idCard: return .idCard
        case .book: return .book
        case .text: return .quickScan
        }
    }
}

/// A kind as the Options sheet's Type menu, the iPad's task list and its sidebar offer it: the kind,
/// what its task sets, whether it can be picked, and whether it is the kind set up now.
public struct IOSKindTile: Identifiable, Equatable {
    public let kind: IOSScanKind
    public let summary: String
    public let availability: TaskAvailability
    public let isCurrent: Bool

    public var id: IOSScanKind { kind }

    /// What VoiceOver reads after the title: "Current" for the kind set up now.
    public var accessibilityValue: String { isCurrent ? String(localized: "Current") : "" }
}

/// What camera mode does with our camera when it opens (`IOSShell.cameraOnOpen`).
public enum IOSCameraOnOpen: Equatable, Sendable {
    case open
    /// The card saying why the camera is asked for, then the camera.
    case introduce
    case stay
}

extension AppState {
    /// The iPhone's and iPad's state without network scanners (the demo scanner alone).
    @MainActor
    public static func makeForIOS(options: IOSLaunchOptions, fileActions: IOSFileActions) -> AppState {
        makeForIOS(options: options, fileActions: fileActions, networkScanners: nil, passwordPrompt: nil)
    }

    /// The iPhone's and iPad's state: the scanner connections of `IOSShell.backends(options:networkScanners:)`,
    /// the iOS file actions (share sheet, Quick Look, the Files app), the iOS troubleshooter service (the
    /// app's page in Settings, the pasteboard, the network path) and UIKit's lifecycle; the iPhone's
    /// troubleshooter checks and connection ranking (`platform` `.ios`); the password of a protected PDF
    /// asked for by `passwordPrompt` (none: such a save saves nothing); AirPrint printing through
    /// `IOSPrintService` (I16), used for the photocopy, the ID card page and the ruler test page; a PDF
    /// pages are added to read and replaced through its security scope and a coordinated access
    /// (`IOSPDFAppend.access`), with the question before adding pages to a signed or PDF/A file asked by
    /// `confirmAppend` (none: such a file gets no pages); the companion (`IOSShell.setUpCompanion`) in the
    /// network folder with its secrets in the Keychain, the computers on the network browsed by
    /// `companion` (none: not browsed), and its cloud folder opened through `IOSSyncFolder`. The queue
    /// survives iOS ending the app (`AppStateFiles.keepingQueue`), except under `-demoScanner`, whose UI
    /// tests each start with an empty queue.
    @MainActor
    public static func makeForIOS(options: IOSLaunchOptions, fileActions: IOSFileActions,
                                  networkScanners: IOSNetworkScanners?,
                                  passwordPrompt: IOSPasswordPrompt? = nil,
                                  printService: IOSPrintService? = nil,
                                  confirmAppend: (@MainActor (String) async -> Bool)? = nil,
                                  companion: IOSCompanionBrowser? = nil) -> AppState {
        let backends: [any ScannerBackend] = IOSShell.backends(options: options, networkScanners: networkScanners)
        let lifecycle: UIKitLifecycle = UIKitLifecycle()
        let state: AppState = AppState(backends: backends, fileActions: fileActions,
                                       troubleshooterService: IOSTroubleshooterService(),
                                       printService: printService ?? IOSPrintService(), lifecycle: lifecycle,
                                       background: UIKitBackgroundActivity(),
                                       keepsQueue: !options.demoScannerOnly)
        state.platform = .ios
        state.listsFoundObjects = true
        state.keepsSavedForUndo = true
        fileActions.reportFailure = { [weak state] (message: String) -> Void in
            state?.errorMessage = message
        }
        IOSShell.adoptOriginalFilter(state, defaults: UserDefaults.standard)
        if UserDefaults.standard.string(forKey: IOSShell.scanModeKey) != IOSScanMode.printer.rawValue {
            IOSShell.adoptCameraKind(state, defaults: UserDefaults.standard)
        }
        if let prompt = passwordPrompt {
            state.askPDFPassword = { () async -> PDFProtection? in
                await prompt.ask()
            }
        }
        state.confirmAppend = confirmAppend
        state.accessPDFForAppend = { (url: URL, writing: Bool, body: (URL) throws -> Void) throws -> Void in
            try IOSPDFAppend.access(url, writing: writing, body)
        }
        state.bookmarkAppendTarget = { (url: URL) -> Data? in
            IOSPDFAppend.bookmark(of: url)
        }
        state.resolveAppendTarget = { (bookmark: Data) -> URL? in
            IOSPDFAppend.resolve(bookmark)
        }
        state.documentsFolder = IOSShell.documentsFolder
        state.resolveDestinationBookmark = { (bookmark: Data) -> (folder: URL, bookmark: Data)? in
            IOSSaveFolder.resolve(bookmark)
        }
        state.openBookmarkedFolder()
        state.removeStaleSaveTemps()
        state.resolveSyncFolderBookmark = { (bookmark: Data) -> (folder: URL, bookmark: Data)? in
            IOSSyncFolder.resolve(bookmark)
        }
        let companionFolder: URL = IOSNetworkScanners.filesFolder()
        let secrets = IOSCompanionSecrets()
        let pairingFile: URL = companionFolder.appendingPathComponent(PairedDesktopStore.fileName)
        if !FileManager.default.fileExists(atPath: pairingFile.path) {
            try? secrets.deleteAll()
        }
        IOSShell.setUpCompanion(state, folder: companionFolder, secrets: secrets,
                                browser: companion, lifecycle: lifecycle)
        return state
    }
}
#endif
