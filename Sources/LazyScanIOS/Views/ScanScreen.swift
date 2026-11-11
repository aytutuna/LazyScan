#if os(iOS)
import LazyScanKit
import CoreGraphics
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The full-screen covers the scan screen opens: the flatbed preview to choose the scan area on, (I13) the ID card's review, (I14) Quick scan's page
/// and (I16) the photocopy's screen. Camera mode's camera rests while one is up.
enum ScanCover: String, Identifiable {
    case crop
    case idCardReview
    case quickScan
    case copy

    var id: String { rawValue }
}

/// The scan screen, in the phone's mode (`IOSScanMode`), which is also where the pages come from; the two tabs
/// share one layout. The top bar (`ScanTopBar`): the library (`onOpenLibrary`; nil where the sidebar has it),
/// the arrow that opens the options drawer (`ScanDrawer`: Colour, and Flash and Camera on the camera, the
/// scanner's Source, Sides and Resolution on the scanner tab) and the other tab's icon (`mode.printer`, and
/// `mode.camera`, back to camera mode, which selects no scanner so none of its limits apply to the camera).
/// Over the bottom corners of the picture, on both tabs, Options (`OptionsScreen` in a sheet that opens at half
/// height: the Type and a short list of pages, each with its value, that holds every setting; the camera keeps
/// running above it) and Save (`PictureButtons`). The bottom bar: the pages, the shutter (Scan on
/// the scanner tab, named for the step, `primaryActionLabel`), Photos and Files. Save runs what After saving
/// has checked (`IOSAfterSave`), as a PDF, a picture a page, Word or text (`IOSShell.exportFormat`), or adds the
/// pages to the end of a PDF picked in Files (`AppState.appendToPDF(at:)`; with a PDF picked,
/// `AppState.appendTarget`, Save adds them to that one and the picture's foot says "Adding to" it); it stays
/// dimmed for the ID card, which is saved from its review. Camera mode is the viewfinder as the screen
/// (`CameraScreen`): this screen hands it the notices (the package banner, an import's progress, the files
/// saved last) and the buttons. The scanner tab is the same picture on black: under the top bar the Scanner
/// row (the scanners, "No scanner found", Add by address and Troubleshoot, then the flatbed's Preview; the row
/// reads the scanner and its source, or "No scanner"), then the flatbed's overview with its scan area or the
/// last page queued, whole (`IOSShell.scannerPicture`), and with neither the step in white on black
/// (`IOSShell.showsStepCard`, in the step's own words, which speak of the scanner; while no scanner is in use,
/// a card in its place saying what is missing, `noScannerCard`). At the picture's foot go the notices, as on
/// the camera (a scan's progress with Cancel, the status a scan left, an import's progress, the package
/// banner, the files saved last), the task's buttons, and Try again when the scanner in use could not be
/// connected to. While a sheet is up, anything else the screen presents (a review, the library, the ID
/// card's question) waits for it to close. Picking a type starts its task as the task list's tile does
/// (`pickKind`). Photos and receipts add the objects found in a shot to the pages, the ID card opens its
/// review once its sides are in, Quick scan its page and the photocopy its copy screen, each full screen; a
/// book page's spread can be split again (`SpreadSplitSheet`). PDFs and pictures dropped on the screen are
/// imported as Files' are, and Command-S saves and Command-comma opens Options. Its covers and the spread's
/// sheet are the root view's (`ScanCovers`), so resizing the window across the width classes, which builds
/// this screen anew, leaves them open. On the iPad's sidebar layout (`pickerInSidebar`) the sidebar has the
/// kinds and the scanners, and the library; the bars, the drawer and the Options sheet are the same.
struct ScanScreen: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var importer: IOSImportSession
    @Environment(\.horizontalSizeClass) private var sizeClass: UserInterfaceSizeClass?
    /// The scanners to pick from.
    let picker: IOSScannerPickerModel
    @Binding var cover: ScanCover?
    @Binding var spreadEditor: SpreadEditorSource?
    /// The iPad's sidebar lists the scanners and the tasks, so the Scanner options only name the source and
    /// the top row is left out.
    var pickerInSidebar: Bool = false
    /// Browses the computers on the network for Options' My computer; nil when the app does not (`-demoScanner`).
    var companion: IOSCompanionBrowser?
    /// Opens the library (iPhone); nil when the sidebar has it.
    var onOpenLibrary: (() -> Void)?
    /// The card saying why the camera is asked for is up, or the app has not started: camera mode's camera
    /// waits for it.
    var waitsForIntro: Bool = false
    /// The root presents something over the screen (the share sheet, Mail, Quick Look): camera
    /// mode's camera rests.
    var rests: Bool = false
    /// The camera or printer mode, switched with the top row's printer and camera buttons; picking a
    /// scanner also switches to printer mode.
    @AppStorage(IOSShell.scanModeKey) private var mode: IOSScanMode = .camera
    /// The scanner printer mode scans with, remembered while the camera is in use.
    @AppStorage(IOSShell.scannerKey) private var printerID: String = ""
    /// The page strip's sheet, opened from the capture bar's last page.
    @State private var pagesShown: Bool = false
    /// A book page whose spread is split again once the page strip's sheet has closed.
    @State private var spreadAfterPages: UUID?
    /// The option group open in a sheet.
    @State private var openGroup: ScanOptionGroup?
    /// What waits for the option group's sheet to close: nothing else can be presented while it is up.
    @State private var afterOptionsClosed: (() -> Void)?
    /// My computer is open in the Options sheet; its pairing scanner uses the camera.
    @State private var pairing: Bool = false
    @State private var showsAdd: Bool = false
    @State private var showsTroubleshooter: Bool = false
    @State private var askedToDiscard: Bool = false
    /// A scanner picked or added in the Scanner options asks there about a side of an ID card held.
    @State private var cardAskedInOptions: Bool = false
    /// Files is open to pick the PDF the pages are added to.
    @State private var picksPDF: Bool = false
    /// The queue is being written to be shared as a Lazy Scan document.
    @State private var sharesPackage: Bool = false
    /// Send to computer asks where the pages go.
    @State private var asksSendTarget: Bool = false
    /// The queue is being written and sent to the paired computer.
    @State private var sendsToComputer: Bool = false
    /// Save waits for the copy screen After saving's Print opened, then emails when `emailsAfterPrint`.
    @State private var savesAfterPrint: Bool = false
    @State private var emailsAfterPrint: Bool = false
    /// Save waits for the hand-off to Lazy Print After saving's Print started, then emails when `emailsAfterPrint`.
    @State private var savesAfterHandoff: Bool = false
    /// After saving's steps left once Send to computer's alert closes: the copy screen and Mail cannot show over it.
    @State private var stepsAfterAlert: [IOSAfterSave]?
    /// What was asked for that would leave the pages without a Save, while the question about them is up.
    @State private var leavingPages: PagesLeave?
    /// Camera mode was asked for in the middle of a stack turned over by hand: the question about it is up.
    @State private var leavingStack: Bool = false
    /// The status a busy spell left in camera mode ("3 pages sent to Office PC."), or one the companion said
    /// while idle (`companionNoticed`), on a card for a few seconds.
    @State private var statusAfterBusy: String?
    /// The status, the files saved last and whether the queue had pages as the busy spell began, to tell what
    /// it changed, and whether it is a send, whose "3 pages sent to Office PC." is the same each time.
    @State private var statusBeforeBusy: String = ""
    @State private var savedBeforeBusy: [URL] = []
    @State private var pagesBeforeBusy: Bool = false
    @State private var busySends: Bool = false
    /// Pages came in since the files saved last: camera mode's card of them waits for the next save, so a
    /// queue emptied without one (discarded, deleted) does not bring it back as if those pages were saved.
    @State private var savedRowStale: Bool = false
    /// The options drawer is open, and the group it shows.
    @State private var showsDrawer: Bool = false
    @State private var drawerGroup: DrawerGroup = .colour
    /// The flatbed's overview came after the last page queued, so the picture shows it (`IOSShell.scannerPicture`).
    @State private var overviewIsNewer: Bool = true

    var body: some View {
        following
            .sheet(item: $openGroup, onDismiss: optionsClosed) { (group: ScanOptionGroup) in
                optionsSheet(group)
                    .environmentObject(state)
                    .environmentObject(importer)
            }
            .sheet(isPresented: $pagesShown, onDismiss: pagesClosed) {
                PageStripSheet(onEditSpread: editSpreadFromPages, onClose: closePages, detents: sheetDetents)
                    .environmentObject(state)
            }
            .onChange(of: state.scannedPages.isEmpty) { (_: Bool, empty: Bool) in
                if empty {
                    pagesShown = false
                } else {
                    savedRowStale = true
                }
            }
            .onChange(of: state.scannedPages.count) { (old: Int, new: Int) in
                if new > old {
                    overviewIsNewer = false
                }
            }
            .onChange(of: overviewTag) { (_: ObjectIdentifier?, tag: ObjectIdentifier?) in
                if tag != nil {
                    overviewIsNewer = true
                }
            }
            .onChange(of: state.lastSavedURLs) { (_: [URL], _: [URL]) in
                savedRowStale = false
            }
            .modifier(IdCardDiscardQuestion(state: state, asked: $askedToDiscard))
            .modifier(KeepPagesQuestion(state: state, leave: $leavingPages, blocked: saveBlocked))
            .alert(IOSShell.finishStackTitle, isPresented: $leavingStack) {
                Button(IOSShell.keepStackLabel) {
                    settleStack()
                    leaveForCamera()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(IOSShell.finishStackLine)
            }
            .modifier(SaveDialogs(state: state, asksSendTarget: $asksSendTarget, picksPDF: $picksPDF,
                                  onSend: sendToComputer))
    }

    /// The screen of the mode in use: camera mode, or the printer screen (beside the scanners on a wide
    /// window without the sidebar).
    @ViewBuilder
    private var content: some View {
        if cameraMode {
            cameraLayout
        } else if IOSLayout.usesSidebar(sizeClass, pad: UIDevice.current.userInterfaceIdiom == .pad) && !pickerInSidebar {
            HStack(spacing: 0) {
                ScannerPickerList(picker: picker)
                    .frame(width: 320)
                    .accessibilityIdentifier("scanners.sidebar")
                Divider()
                printerColumn
            }
        } else {
            printerColumn
        }
    }

    private var screen: some View {
        content
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(barTitle)
            .navigationBarTitleDisplayMode(.inline)
            // The iPad keeps its bar in camera mode too, for the sidebar's button.
            .toolbar(pickerInSidebar ? Visibility.automatic : Visibility.hidden, for: .navigationBar)
            .toolbarBackground(cameraMode ? Visibility.hidden : Visibility.automatic, for: .navigationBar)
            .dropDestination(for: IOSDroppedFile.self) { (items: [IOSDroppedFile], _: CGPoint) -> Bool in
                importDropped(items)
            }
            .background {
                optionsShortcut
            }
    }

    /// The reviews follow the state: each opens as a cover once it is due, and closes with it.
    private var following: some View {
        screen
            .onAppear {
                if state.showIdCardReview {
                    cover = .idCardReview
                } else if state.quickScanPage != nil {
                    cover = .quickScan
                } else if !state.copyPages.isEmpty {
                    cover = .copy
                }
            }
            .onChange(of: state.showIdCardReview) { (_: Bool, shown: Bool) in
                showReview(shown, as: .idCardReview)
            }
            .onChange(of: state.quickScanPage != nil) { (_: Bool, shown: Bool) in
                showReview(shown, as: .quickScan)
            }
            .onChange(of: state.copyPages.isEmpty) { (_: Bool, empty: Bool) in
                showReview(!empty, as: .copy)
                if empty && savesAfterPrint {
                    savesAfterPrint = false
                    saveNow(emails: emailsAfterPrint)
                }
            }
            .onChange(of: state.isBusy) { (_: Bool, busy: Bool) in
                if !busy && savesAfterHandoff {
                    savesAfterHandoff = false
                    saveNow(emails: emailsAfterPrint)
                    return
                }
                // Print… held nothing (nothing to print, or cancelled), so no copy screen will close.
                if !busy && savesAfterPrint && state.copyPages.isEmpty {
                    savesAfterPrint = false
                }
            }
            .onChange(of: state.errorMessage == nil) { (_: Bool, closed: Bool) in
                if closed {
                    alertClosed()
                }
            }
            .onChange(of: working) { (_: Bool, busy: Bool) in
                busyChanged(busy)
            }
            .onChange(of: state.companionNotice) { (_: CompanionNotice?, notice: CompanionNotice?) in
                companionNoticed(notice)
            }
            .onChange(of: state.pendingPackage != nil) { (_: Bool, offered: Bool) in
                // The package banner is at the picture's foot, behind the half sheet.
                if offered {
                    openGroup = nil
                }
            }
            .onChange(of: importer.isImporting) { (_: Bool, importing: Bool) in
                // The root's corner editor cannot show over a sheet (files opened in the app, the companion);
                // a spread's split can be started again from the page strip.
                if importing {
                    openGroup = nil
                    pagesShown = false
                    picksPDF = false
                    spreadEditor = nil
                }
            }
    }

    /// The shortcut lives on a button that always exists.
    private var optionsShortcut: some View {
        Button("") {
            openOptions()
        }
        .keyboardShortcut(IOSShortcuts.options.keyboardShortcut)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var cameraMode: Bool {
        mode == .camera
    }

    /// The kind, in the bar the iPad shows. The iPhone's bar is hidden, and a title there would only name the
    /// library's back button.
    private var barTitle: String {
        guard pickerInSidebar else { return "" }
        let kind: IOSScanKind = IOSShell.shownKind(state.settings)
        return cameraMode ? kind.cameraTitle : kind.title
    }

    /// The printer screen's column, drawn again as the network scanners' search goes on, since the picker's
    /// flags are not published: with no scanner in use its card and status line say where the search is.
    @ViewBuilder
    private var printerColumn: some View {
        if let network = picker.network {
            NetworkObserving(network: network) {
                mainColumn
            }
        } else {
            mainColumn
        }
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            ScanTopBar(showsDrawer: $showsDrawer, onLibrary: libraryAction) {
                cameraModeButton
            }
            scannerRow
            picture
            if showsDrawer {
                ScanDrawer(model: nil, torch: false, group: $drawerGroup)
                    .transition(.opacity)
            }
            CaptureRow(onPages: openPages, onPresenting: nil) {
                scanRing
            }
        }
    }

    // MARK: Camera mode

    /// The viewfinder as the screen (`CameraScreen`), with what this screen hands it: the notices at the
    /// viewfinder's foot and the Options and Save buttons.
    private var cameraLayout: some View {
        CameraScreen(resting: cameraCovered, holdsAuto: openGroup == .options, waitsForIntro: waitsForIntro,
                     onLibrary: libraryAction, onPrinter: switchToPrinter, onPages: openPages) {
            cameraNotices
        } pictureButtons: {
            pictureButtons
        }
    }

    /// Something covers the camera: what the root presents, a cover, a sheet, Files to pick a PDF in, a
    /// question or the error alert. The Options sheet does not: the camera keeps running above it, with
    /// Auto held back meanwhile (`holdsAuto`).
    private var cameraCovered: Bool {
        let presented: Bool = cover != nil || openGroup == .scanner || pairing || pagesShown || picksPDF || spreadEditor != nil
        let asked: Bool = askedToDiscard || leavingPages != nil || asksSendTarget || state.errorMessage != nil
            || state.showTroubleshooter
        return rests || presented || asked
    }

    /// The library, once the option group's sheet has closed; nil where the sidebar has it.
    private var libraryAction: (() -> Void)? {
        guard let open = onOpenLibrary else { return nil }
        return { () -> Void in
            afterOptions(open)
        }
    }

    /// Printer mode: the root view selects its scanner once listed. A side of an ID card held keeps the scanner
    /// from being selected, so it asks to discard the card first, as picking a scanner does; Cancel stays in
    /// camera mode, where the card's other side can be taken.
    private func switchToPrinter() {
        let appState: AppState = state
        afterOptions {
            appState.leaveIdCard {
                mode = .printer
            }
            if appState.pendingIdCardLeave != nil {
                askedToDiscard = true
            }
        }
    }

    /// The package banner, the app's progress with Cancel while it is busy (a save, an export, After saving's
    /// steps), an import's progress with Stop, the status a busy spell left (`busyChanged`) or the companion
    /// said while idle (`companionNoticed`), and the files saved last until the next page comes in, back with
    /// the next save only (`savedRowStale`), each on a card over the picture.
    @ViewBuilder
    private var cameraNotices: some View {
        if let offered = state.pendingPackage {
            PackageBanner(offered: offered, onOpenAsNew: openPackageAsNew)
                .modifier(NoticeCard())
        }
        // An import has its own card, and the pages it brings in keep the app busy for a moment each.
        if state.isBusy && !importer.isImporting {
            busyCard
        }
        if importer.progressText != nil {
            ImportProgressRow()
                .modifier(NoticeCard())
        }
        if let message = statusAfterBusy, !state.isBusy {
            statusCard(message)
        }
        if !state.lastSavedURLs.isEmpty && state.scannedPages.isEmpty && !state.isBusy && !savedRowStale {
            SavedFilesRow()
                .modifier(NoticeCard())
        }
    }

    /// The status a busy spell or the companion left, gone after about four seconds.
    private func statusCard(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .lineLimit(3)
            .modifier(NoticeCard())
            .accessibilityIdentifier("camera.notice")
            .task(id: message) {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if statusAfterBusy == message {
                    statusAfterBusy = nil
                }
            }
    }

    /// The app, or a share or a send of the pages, is busy.
    private var working: Bool {
        state.isBusy || sendsToComputer || sharesPackage
    }

    /// A busy spell began or ended. The picture has no status line, so once it ends the status it left is
    /// shown on a card when it changed and nothing else says it: an alert, the import's card, or the card of
    /// the files saved.
    private func busyChanged(_ busy: Bool) {
        if busy {
            statusAfterBusy = nil
            statusBeforeBusy = state.statusMessage
            savedBeforeBusy = state.lastSavedURLs
            pagesBeforeBusy = !state.scannedPages.isEmpty
            busySends = sendsToComputer
            return
        }
        // A save that emptied the queue has the files saved last even when they are the same ones as before
        // (more pages added to the same PDF), which `lastSavedURLs` does not report as a change.
        if pagesBeforeBusy && state.scannedPages.isEmpty {
            savedRowStale = false
        }
        let message: String = state.statusMessage
        // Undo empties the saved files, which leaves no card to say it: the message is shown instead.
        guard !message.isEmpty, message != statusBeforeBusy || busySends, state.errorMessage == nil,
              !importer.isImporting, state.lastSavedURLs == savedBeforeBusy || state.lastSavedURLs.isEmpty else { return }
        statusAfterBusy = message
    }

    /// The companion said a document was sent, put in the cloud folder or received, which happens while nothing
    /// is busy too (the pull, the drain on becoming active): the picture shows it on the busy spell's card.
    private func companionNoticed(_ notice: CompanionNotice?) {
        guard let notice, !working, state.errorMessage == nil else { return }
        statusAfterBusy = notice.text
    }

    /// Printer mode's progress row with Cancel, and the status line under the bar when the progress has no
    /// words of its own (a save's text reading, its PDF being written). Bringing the kept queue back has no
    /// Cancel: nothing stops it.
    private var busyCard: some View {
        let worded: Bool = !(state.progress?.message ?? "").isEmpty
        let status: String = state.statusMessage
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                ScanProgressRow(progress: state.progress)
                if !worded && !status.isEmpty {
                    Text(status)
                        .font(.footnote)
                        .lineLimit(2)
                        .accessibilityIdentifier("camera.status")
                }
            }
            if !state.restoringQueue {
                Button(role: .cancel) {
                    state.cancelScan()
                } label: {
                    Text("Cancel")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("cancel.button")
            }
        }
        .modifier(NoticeCard())
    }

    /// Back to camera mode.
    private var cameraModeButton: some View {
        Button {
            switchToCamera()
        } label: {
            Image(systemName: "camera")
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(state.isBusy)
        .accessibilityLabel(Text(IOSImportText.cameraLabel))
        .accessibilityHint(Text(IOSCameraText.cameraModeHint))
        .accessibilityIdentifier("mode.camera")
    }

    /// Camera mode, with no scanner selected, so none of its limits apply to the camera (the sides turned
    /// over by hand back to both, `AppState.userSelectNoDevice`). That ends a stack turned over by hand, so
    /// while one has pages in (`TurnedOverButtons.showsAny`) it asks first (`leavingStack`).
    private func switchToCamera() {
        let appState: AppState = state
        afterOptions {
            if TurnedOverButtons.showsAny(appState) {
                leavingStack = true
            } else {
                leaveForCamera()
            }
        }
    }

    private func leaveForCamera() {
        mode = .camera
        state.userSelectNoDevice()
    }

    /// Keep pages as they are: what the stack's own buttons would do before its steps end. Keep fronts only
    /// while no back is in, Combine anyway once some are; fronts still being scanned stay as they are.
    private func settleStack() {
        if state.canScanMoreFronts {
            state.keepFrontsOnly()
        } else if state.awaitingBacks {
            state.combineSidesAnyway()
        }
    }

    /// Picking a type in the Options sheet starts its task as the task list's tile does (fresh steps, and no PDF
    /// picked to add to), the Options' choices the kind was left with laid back over its defaults
    /// (`IOSShell.startKind`). A type only sets choices, so the pages taken stay and the sheet stays open;
    /// the ID card, which starts its own steps, asks first (`KeepPagesQuestion`), which cannot show over the
    /// sheet. With a side of an ID card held it asks about the card too. The type already picked changes
    /// nothing, so a stray tap keeps Both sides, the steps and the PDF picked. Nothing changes while a share
    /// or a send reads the spooled pages, which Discard would delete.
    private func pickKind(_ kind: IOSScanKind) {
        guard !saveBlocked else { return }
        guard kind != IOSShell.shownKind(state.settings) || state.activeTask == nil else { return }
        if state.pagesLeftBehind(by: kind.task) > 0 {
            afterOptions {
                leavingPages = PagesLeave(reason: IOSShell.keepPagesReason(kind)) { (discarding: Bool) in
                    switchKind(kind, discardingPages: discarding)
                }
            }
        } else {
            switchKind(kind)
        }
    }

    /// Starts the kind's task, dropping the pages first when asked to, once the ID card's question (when a
    /// side is held) is answered; then `next`, once it has started.
    private func switchKind(_ kind: IOSScanKind, discardingPages: Bool = false, then next: (@MainActor () -> Void)? = nil) {
        let appState: AppState = state
        appState.leaveIdCard {
            let started: Bool = IOSShell.startKind(kind, in: appState, discardingPages: discardingPages,
                                                   defaults: UserDefaults.standard)
            if started {
                appState.clearAppendTarget()
                next?()
            }
        }
        if appState.pendingIdCardLeave != nil {
            if openGroup != nil {
                cardAskedInOptions = true
            } else {
                askedToDiscard = true
            }
        }
    }

    /// Open as new replaces the queued pages, so with pages queued it asks about them first. A kind that keeps
    /// no pages switches to Document first, as a document opened with no task set up opens there; Document
    /// itself with Collect pages before saving off only turns it back on, its other choices kept. Not while a
    /// share or a send reads them.
    private func openPackageAsNew() {
        guard !saveBlocked else { return }
        guard IOSShell.takesWholePages(state.settings) else {
            if IOSShell.shownKind(state.settings) == .document {
                state.settings.documentMultiPage = true
                openPackageReplacingPages()
            } else {
                switchKind(.document) {
                    openPackageReplacingPages()
                }
            }
            return
        }
        openPackageReplacingPages()
    }

    private func openPackageReplacingPages() {
        let appState: AppState = state
        guard !state.scannedPages.isEmpty, let offered = state.pendingPackage else {
            appState.openPendingPackageAsNew()
            return
        }
        leavingPages = PagesLeave(reason: IOSShell.keepPagesReason(package: offered.fileName)) { (_: Bool) in
            appState.openPendingPackageAsNew()
        }
    }

    // MARK: The picture

    /// The overview's identity, to tell a new overview from the same one drawn again.
    private var overviewTag: ObjectIdentifier? {
        state.overviewImage.map { (image: CGImage) -> ObjectIdentifier in ObjectIdentifier(image) }
    }

    private var pictureShown: ScannerPicture {
        IOSShell.scannerPicture(flatbed: IOSShell.showsFlatbedPreview(state.settings),
                                hasOverview: state.overviewImage != nil, overviewIsNewer: overviewIsNewer,
                                pageCount: state.scannedPages.count)
    }

    /// The scanner tab's picture, on black as the camera's viewfinder is: the flatbed's overview, the last
    /// page queued or what the step asks for, with the notices at its foot and the buttons over its corners.
    private var picture: some View {
        ZStack {
            Color.black
            pictureContent
            pictureOverlays
            pictureButtons
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("preview.area")
    }

    @ViewBuilder
    private var pictureContent: some View {
        switch pictureShown {
        case .overview:
            if let overview = state.overviewImage {
                Button(action: openCrop) {
                    FlatbedThumbnail(image: overview)
                        .padding(8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(state.isBusy)
                .accessibilityLabel(Text("Flatbed preview"))
                .accessibilityValue(Text("Scan area: \(IOSCropGeometry.describe(state.selectionRect))"))
                .accessibilityHint(Text("Opens it full screen to choose the scan area."))
                .accessibilityIdentifier("flatbed.preview")
            }
        case .page:
            if let page = state.scannedPages.last?.image {
                Image(page, scale: 1, label: Text("Last scan"))
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(8)
                    .accessibilityIdentifier("last.scan")
            }
        case .empty:
            ViewThatFits(in: .vertical) {
                emptyPicture
                ScrollView {
                    emptyPicture
                }
            }
            .padding(.bottom, PictureButtons.clearance)
        }
    }

    /// With nothing to show, the step's words (or what is missing, with no scanner in use) in white.
    private var emptyPicture: some View {
        VStack(alignment: .leading, spacing: 8) {
            if printerNeedsScanner {
                noScannerCard
            } else {
                stepCard
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .environment(\.colorScheme, ColorScheme.dark)
    }

    /// The step's one line while the picture shows a page or the overview, which leave no room for its card.
    private var stepLine: String? {
        if printerNeedsScanner {
            return noScannerLine
        }
        guard let current = state.taskFlow?.current, showsStepCard else { return nil }
        return cameraLine?.prompt ?? IOSShell.printerStep(current, settings: state.settings).prompt
    }

    /// Over the picture: the step's line at its top while it shows something, and at its foot the notices,
    /// the sides mismatch, the task's buttons and Try again, above the corners the buttons are in.
    private var pictureOverlays: some View {
        let populated: Bool = pictureShown != .empty
        return VStack(spacing: 8) {
            if populated, let line = stepLine {
                StatusPill(text: line, hint: nil)
                    .accessibilityIdentifier("step.prompt")
            }
            Spacer(minLength: 0)
            cameraNotices
            if let mismatch = state.sidesMismatch, state.isTurningOverByHand {
                MismatchPill(text: mismatch)
            }
            if TurnedOverButtons.showsAny(state) {
                TurnedOverButtons()
                    .environment(\.colorScheme, ColorScheme.dark)
            }
            if let device = retryDevice {
                Button(IOSNetworkText.retry) {
                    state.userSelectDevice(device.id)
                }
                .buttonStyle(.borderedProminent)
                .disabled(importer.isImporting)
                .accessibilityIdentifier("scanner.retry")
            }
            if populated && state.canSkipStep {
                Button(IdCardSteps.skipBackLabel) {
                    state.skipStep()
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isBusy)
                .accessibilityIdentifier("step.skip")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, PictureButtons.clearance)
    }

    // MARK: The options

    /// The slim row under the top bar: the scanner in use and its source, which opens the Scanner sheet.
    private var scannerRow: some View {
        Button {
            openGroup = .scanner
        } label: {
            HStack(spacing: 8) {
                Text(ScanOptionGroup.scanner.title)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 8)
                Text(scannerValue)
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
                    .accessibilityHidden(true)
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .padding(.horizontal, 24)
            .frame(minHeight: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // An import's corner editor needs the screen; the sheet closes as one starts.
        .disabled(importer.isImporting)
        .accessibilityIdentifier("options.row.scanner")
    }

    /// What the Scanner row says: the scanner and its source ("No scanner" until one is picked or found).
    private var scannerValue: String {
        guard let device = sourceDevice else { return IOSNetworkText.noScannerPicked }
        return "\(device.name) \u{00B7} \(state.settings.source.label)"
    }

    /// The heights of the page strip's sheet. Camera mode's camera rests under it, so a half sheet would show
    /// the stopped viewfinder above it: full height only.
    private var sheetDetents: Set<PresentationDetent> {
        cameraMode ? [.large] : [.medium, .large]
    }

    /// A group's sheet, in half height first with the screen still usable above it: the Options' pages
    /// (`OptionsScreen`), whose Look changes the camera shows live, or the Scanner's.
    private func optionsSheet(_ group: ScanOptionGroup) -> some View {
        sheetContent(group)
            .modifier(ScannerPickerSheets(picker: picker, showsAdd: $showsAdd, showsTroubleshooter: $showsTroubleshooter,
                                          asksAboutCard: $cardAskedInOptions))
            .modifier(IdCardDiscardQuestion(state: state, asked: $cardAskedInOptions))
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            // iOS 26 draws a half sheet as glass, and the shutter and buttons under it showed through the rows.
            .presentationBackground(Color(uiColor: .systemGroupedBackground))
            // The root's alert cannot show over a sheet, nor its troubleshooter until the sheet has closed.
            .modifier(ErrorAlert(state: state, onTroubleshoot: openTroubleshooter))
            // Nor its question about a changed certificate, which a scanner picked here asks.
            .background {
                if let network = picker.network {
                    CertificateQuestion(network: network)
                }
            }
    }

    @ViewBuilder
    private func sheetContent(_ group: ScanOptionGroup) -> some View {
        switch group {
        case .options:
            OptionsScreen(blocked: saveBlocked, companion: companion, onType: pickKind, onAction: runAction,
                          onPresetApplied: closeOptions, onTroubleshoot: openPickerTroubleshooter, onDone: closeOptions,
                          onPairing: { (open: Bool) -> Void in pairing = open })
        case .scanner:
            NavigationStack {
                Form {
                    scannerContent
                }
                .navigationTitle(group.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(IOSSettingsText.doneLabel) {
                            closeOptions()
                        }
                        .accessibilityIdentifier("options.done")
                    }
                }
            }
        }
    }

    private func openTroubleshooter() {
        let appState: AppState = state
        afterOptions {
            appState.showTroubleshooter = true
        }
    }

    @ViewBuilder
    private var scannerContent: some View {
        if pickerBeside {
            Section {
                sourceRow
            }
        } else {
            ScannerPickerSections(picker: picker, onAdd: openAdd, onTroubleshoot: openPickerTroubleshooter,
                                  asksAboutCard: $cardAskedInOptions)
        }
        if sourceDevice != nil && usesFlatbed {
            Section {
                previewControls
            }
        }
    }

    private func closeOptions() {
        openGroup = nil
    }

    /// An Options row's action, once the sheet has closed.
    private func runAction(_ action: OptionsAction) {
        afterOptions {
            switch action {
            case .saveAsNew:
                state.clearAppendTarget()
                saveWithActions()
            case .addToPDF:
                picksPDF = true
            case .email:
                saveAndEmail()
            case .print:
                if state.canPrintQueueWithLazyPrint {
                    state.printQueueWithLazyPrint()
                } else {
                    state.printQueueAsCopy()
                }
            case .share:
                sharePackage()
            case .send:
                asksSendTarget = true
            }
        }
    }

    /// Runs `action` at once, or once the option group's sheet has closed.
    private func afterOptions(_ action: @escaping () -> Void) {
        guard openGroup != nil else {
            action()
            return
        }
        afterOptionsClosed = action
        openGroup = nil
    }

    private func optionsClosed() {
        pairing = false
        let action: (() -> Void)? = afterOptionsClosed
        afterOptionsClosed = nil
        action?()
    }

    // MARK: The page strip

    private func openPages() {
        afterOptions {
            pagesShown = true
        }
    }

    private func closePages() {
        pagesShown = false
    }

    /// The root view presents the split sheet, which it cannot while the strip's sheet is up.
    private func editSpreadFromPages(_ pageID: UUID) {
        spreadAfterPages = pageID
        pagesShown = false
    }

    private func pagesClosed() {
        guard let pageID = spreadAfterPages else { return }
        spreadAfterPages = nil
        openSpreadEditor(pageID)
    }

    // MARK: The scanner picker

    private func openAdd() {
        showsAdd = true
    }

    private func openPickerTroubleshooter() {
        showsTroubleshooter = true
    }

    // MARK: Dropped files

    /// PDFs and pictures dropped on the screen come in as files picked in Files do, while this task takes
    /// photos and nothing else is being brought in.
    private func importDropped(_ items: [IOSDroppedFile]) -> Bool {
        guard !items.isEmpty, importer.canImport, IOSShell.takesPhotos(state.settings) else { return false }
        var imports: [IOSImportItem] = []
        for dropped in items {
            imports.append(dropped.item)
        }
        let session: IOSImportSession = importer
        Task { @MainActor in
            await session.importItems(imports)
        }
        return true
    }

    // MARK: The reviews

    /// A review opened (in place of the camera or another cover) or closed (saved, discarded, or a side of
    /// the ID card to take again). One that opens while an option group's sheet is up waits for it to close.
    private func showReview(_ shown: Bool, as review: ScanCover) {
        if shown {
            afterOptions {
                if wantsReview(review) {
                    cover = review
                }
            }
        } else if cover == review {
            cover = nil
        }
    }

    /// Whether the review is still due once the sheet it waited for has closed.
    private func wantsReview(_ review: ScanCover) -> Bool {
        switch review {
        case .idCardReview: return state.showIdCardReview
        case .quickScan: return state.quickScanPage != nil
        case .copy: return !state.copyPages.isEmpty
        case .crop: return true
        }
    }

    // MARK: A book's spread

    /// The split sheet for the spread the page was cut from, once its picture is read.
    private func openSpreadEditor(_ pageID: UUID) {
        guard !state.isBusy else { return }
        let appState: AppState = state
        Task { @MainActor in
            spreadEditor = await appState.spreadEditor(for: pageID)
        }
    }

    // MARK: The scan area

    /// The flatbed preview full screen, to choose the scan area on (`CropScreen`).
    private func openCrop() {
        guard state.overviewImage != nil, IOSShell.showsFlatbedPreview(state.settings), !state.isBusy else { return }
        afterOptions {
            cover = .crop
        }
    }

    /// The flatbed's overview, once the Scanner options have closed: its progress and Cancel at the bottom
    /// are in view while it runs, and it lands in the preview above.
    private func previewFlatbed() {
        let appState: AppState = state
        afterOptions {
            appState.performOverview()
        }
    }

    /// The current step's one-line prompt, with its fuller help below (as printer mode says it,
    /// `IOSShell.printerStep`, or the camera's line in its place, `IOSShell.cameraLine`); the back of an ID
    /// card offers "No back side".
    @ViewBuilder
    private var stepCard: some View {
        if let current = state.taskFlow?.current, showsStepCard {
            let step: TaskStep = IOSShell.printerStep(current, settings: state.settings)
            let camera: CameraStepText? = cameraLine
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(camera?.prompt ?? step.prompt)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(camera?.help ?? step.help)
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("step.prompt")
                if state.canSkipStep {
                    Button(IdCardSteps.skipBackLabel) {
                        state.skipStep()
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.isBusy)
                    .accessibilityIdentifier("step.skip")
                }
            }
            // The row has no inset, so without this the cell's rounded corners cut off the first letters.
            .padding(.horizontal, 8)
        }
    }

    private var showsStepCard: Bool {
        IOSShell.showsStepCard(state.activeTask, options: state.settings.taskOptions, sides: state.cameraSides,
                               newDocument: state.newDocumentPending, turningOverByHand: state.isTurningOverByHand,
                               printer: mode == .printer)
    }

    private var cameraLine: CameraStepText? {
        IOSShell.cameraLine(state.activeTask, options: state.settings.taskOptions, sides: state.cameraSides,
                            newDocument: state.newDocumentPending, turningOverByHand: state.isTurningOverByHand,
                            printer: mode == .printer)
    }

    /// Printer mode with no scanner in use (none picked, or the one picked not found yet): Scan is dimmed. A
    /// scanner whose entry dropped from the list keeps its session while a scan runs, a review is open or a
    /// side of an ID card is held (`AppState.autoSwitchMustWait`), and the step card stays with it.
    private var printerNeedsScanner: Bool {
        mode == .printer && sourceDevice == nil && state.capabilities == nil
    }

    private var noScannerLine: String {
        IOSShell.noScannerLine(explained: !picker.showsExplanation, denied: picker.showsDenied,
                               searching: picker.showsSearching, found: state.hasRealDevices)
    }

    /// In the step card's place while no scanner is in use: where the search is, with Pick a scanner (the
    /// Scanner options; not where the scanners are listed beside the screen) and Troubleshoot (the root's,
    /// since the picker's is a sheet of the options), which as in the picker waits until the card about the
    /// local network is read. An ID card whose front the camera took still offers "No back side" here, as the
    /// step card does.
    private var noScannerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(noScannerLine)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("scanner.none")
            HStack(spacing: 12) {
                if !pickerBeside {
                    Button(IOSShell.pickScannerLabel) {
                        openGroup = .scanner
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(importer.isImporting)
                    .accessibilityIdentifier("scanner.pick")
                }
                if !picker.showsExplanation {
                    Button(IOSNetworkText.troubleshoot) {
                        openTroubleshooter()
                    }
                    .buttonStyle(.bordered)
                    .disabled(importer.isImporting)
                    .accessibilityIdentifier("scanner.troubleshoot")
                }
            }
            if state.canSkipStep {
                Button(IdCardSteps.skipBackLabel) {
                    state.skipStep()
                }
                .buttonStyle(.bordered)
                .disabled(state.isBusy)
                .accessibilityIdentifier("step.skip")
            }
        }
        .padding(.horizontal, 8)
    }

    /// The scanner named, with how it is reached, where the list beside the screen picks it.
    private var sourceRow: some View {
        let name: String = sourceDevice?.name ?? IOSNetworkText.noScannerPicked
        return HStack(spacing: 8) {
            Image(systemName: "scanner")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(name)
                .lineLimit(1)
            Spacer(minLength: 8)
            if sourceDevice != nil, let note = deviceNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                    .accessibilityIdentifier("scanner.note")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Scanner: \(name)"))
        .accessibilityIdentifier("scanner.menu")
    }

    /// The scanners are listed beside the screen (the iPad's sidebar, or the column of a wide window).
    private var pickerBeside: Bool {
        pickerInSidebar || IOSLayout.usesSidebar(sizeClass, pad: UIDevice.current.userInterfaceIdiom == .pad)
    }

    /// "Not encrypted" for a network scanner reached over plain HTTP after HTTPS could not be used.
    private var deviceNote: String? {
        let selected: String? = state.selectedDeviceID
        for row in picker.rows where row.id == selected {
            return row.note
        }
        return nil
    }

    /// Preview (the flatbed's overview, run once the sheet has closed, `previewFlatbed`) while the flatbed
    /// is used, Choose area once there is one (the preview full screen, `CropScreen`), and Clear selection
    /// once an area is chosen.
    @ViewBuilder
    private var previewControls: some View {
        if usesFlatbed {
            HStack(spacing: 12) {
                Button {
                    previewFlatbed()
                } label: {
                    Label("Preview", systemImage: "eye")
                }
                .buttonStyle(.bordered)
                .disabled(state.isBusy)
                .accessibilityIdentifier("preview.button")
                if state.overviewImage != nil {
                    Button {
                        openCrop()
                    } label: {
                        Label("Choose area", systemImage: "crop")
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.isBusy)
                    .accessibilityIdentifier("crop.open")
                }
                if state.overviewImage != nil && state.selectionRect != nil {
                    Button {
                        state.selectionRect = nil
                    } label: {
                        Label("Clear selection", systemImage: "xmark.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .disabled(state.isBusy)
                    .accessibilityLabel(Text("Clear selection"))
                    .accessibilityIdentifier("crop.clear")
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var usesFlatbed: Bool {
        state.capabilities?.sources.contains(.flatbed) == true && state.settings.source == .flatbed
    }

    /// The scanner the pages come from; nil in camera mode, or until printer mode's scanner is found.
    private var sourceDevice: ScannerInfo? {
        IOSShell.printerScanner(mode, scanner: printerID, selected: state.selectedDeviceID, devices: state.devices)
    }

    /// Scan once the scanner is connected and nothing else runs.
    private var canScan: Bool {
        state.capabilities != nil && !state.isBusy
    }

    /// The scanner in use while connecting to it failed last and nothing runs: Try again opens it again.
    private var retryDevice: ScannerInfo? {
        guard let device = sourceDevice, state.capabilities == nil, !state.isBusy,
              state.lastFailure?.deviceName == device.name else { return nil }
        return device
    }

    private func scan() {
        state.performScan()
    }

    // MARK: Saving

    /// Save, then what After saving has checked, in its order (`IOSAfterSave.steps`). Send to computer and Print
    /// take the queue, which the save empties, so they go first: the save waits for the copy screen Print
    /// opens to close. Email goes out with the saved file. A send that failed, or whose pages wait for a
    /// computer that did not answer, says so in an alert, and the other steps run once it is closed.
    private func saveWithActions() {
        let paired: Bool = IOSShell.offersSendToComputer(state.settings, status: state.companionStatus)
        let steps: [IOSAfterSave] = IOSAfterSave.steps(UserDefaults.standard, paired: paired)
        guard steps.contains(.send) else {
            printThenSave(steps)
            return
        }
        let appState: AppState = state
        Task { @MainActor in
            sendsToComputer = true
            await appState.sendQueueToDesktop(target: .new)
            reportUnsent(appState)
            sendsToComputer = false
            if appState.errorMessage != nil {
                stepsAfterAlert = steps
                return
            }
            printThenSave(steps)
        }
    }

    /// After saving's Print, handed to Lazy Print where it is installed, else on the copy screen the save waits
    /// for, then the save, emailing when checked.
    private func printThenSave(_ steps: [IOSAfterSave]) {
        let emails: Bool = steps.contains(.email)
        guard steps.contains(.print) else {
            saveNow(emails: emails)
            return
        }
        emailsAfterPrint = emails
        // Lazy Print takes the pages as a PDF, so there is no copy screen: the save follows once it has them.
        if state.canPrintQueueWithLazyPrint {
            savesAfterHandoff = true
            state.printQueueWithLazyPrint()
            if !state.isBusy {
                savesAfterHandoff = false
            }
            return
        }
        savesAfterPrint = true
        state.printQueueAsCopy()
        if !state.isBusy {
            savesAfterPrint = false
        }
    }

    /// Send to computer's alert has closed: the steps after it run once it has gone.
    private func alertClosed() {
        guard let steps = stepsAfterAlert else { return }
        stepsAfterAlert = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            printThenSave(steps)
        }
    }

    private func saveNow(emails: Bool) {
        if emails {
            saveAndEmail()
        } else {
            save()
        }
    }

    private func save() {
        IOSShell.saveQueue(state)
    }

    /// Email… in Options: this save only is sent by email once written.
    private func saveAndEmail() {
        state.saveAndEmail(images: savesImages)
    }

    private var savesImages: Bool {
        state.appendTarget == nil && IOSShell.savesImages(state.settings)
    }

    private func sharePackage() {
        sharesPackage = true
        let appState: AppState = state
        Task { @MainActor in
            await IOSShell.sharePackage(appState)
            sharesPackage = false
        }
    }

    private func sendToComputer(_ target: CompanionTarget) {
        sendsToComputer = true
        let appState: AppState = state
        Task { @MainActor in
            await appState.sendQueueToDesktop(target: target)
            reportUnsent(appState)
            sendsToComputer = false
        }
    }

    /// A send whose document stays in the outbox, the computer not answering or no longer knowing the
    /// phone, says so in an alert, naming the cloud folder when the document went there, unless it failed with
    /// an error of its own.
    private func reportUnsent(_ appState: AppState) {
        if appState.errorMessage == nil {
            appState.errorMessage = IOSAfterSave.notSentMessage(appState.companionStatus,
                                                                waiting: appState.companionOutboxCount,
                                                                inFolder: appState.companionInSyncFolderCount)
        }
    }

    // MARK: The bottom bar

    /// The queue as Save would save it.
    private var savePlan: SavePlan {
        SavePlan.make(state.scannedPages, options: state.settings.document)
    }

    /// Saving deletes the spooled pages a share or a send may still be writing.
    private var saveBlocked: Bool {
        state.isBusy || importer.isImporting || state.readsQueue || sharesPackage || sendsToComputer
    }

    /// Options and Save; Save while the pages are saved here (`IOSShell.offersSave`) and one is queued.
    private var pictureButtons: some View {
        let plan: SavePlan = savePlan
        let offered: Bool = IOSShell.offersSave(state.settings, pageCount: state.scannedPages.count)
        return PictureButtons(title: IOSShell.saveTitle(target: state.appendTarget),
                              detail: IOSShell.saveDetail(state.settings, plan: plan, target: state.appendTarget),
                              canSave: offered && !saveBlocked && plan.pageCount > 0,
                              adding: state.appendTarget?.lastPathComponent,
                              onOptions: openOptions, onSave: { afterOptions(saveWithActions) })
    }

    private func openOptions() {
        guard !importer.isImporting else { return }
        openGroup = .options
    }

    /// Scan, the round button of the bottom bar, once the scanner is connected and nothing else runs. It is
    /// named for the step as the scanner tab says it ("Scan page", "Scan stack").
    private var scanRing: some View {
        ShutterRing(progress: 0, enabled: canScan, label: scanLabel, hint: IOSShell.scanHint,
                    identifier: "scan.button", action: scan)
    }

    private var scanLabel: String {
        guard let step = state.taskFlow?.current else { return state.primaryActionLabel }
        return IOSShell.printerStep(step, settings: state.settings).primaryActionLabel
    }

    /// The Options row that goes back to saving new files.
    static func clearTargetLabel(_ target: URL) -> String {
        String(localized: "Stop Adding to \(target.lastPathComponent)")
    }
}

/// A sheet of the scan screen: the Options of what is saved, and the Scanner's, opened from the Scanner row.
enum ScanOptionGroup: String, Identifiable {
    case options
    case scanner

    var id: String { rawValue }

    var title: String {
        switch self {
        case .options: return String(localized: "Options")
        case .scanner: return String(localized: "Scanner")
        }
    }
}

/// The confirmation asking where Send to computer sends the pages, and Files to pick the PDF the Options sheet
/// adds them to; on the screen whichever mode is shown.
@MainActor
private struct SaveDialogs: ViewModifier {
    @ObservedObject var state: AppState
    @Binding var asksSendTarget: Bool
    @Binding var picksPDF: Bool
    let onSend: (CompanionTarget) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(IOSCompanionText.sendQuestion, isPresented: $asksSendTarget, titleVisibility: .visible) {
                Button(IOSCompanionText.newDocument) {
                    onSend(.new)
                }
                .accessibilityIdentifier("send.computer.new")
                Button(IOSCompanionText.intoOpenDocument) {
                    onSend(.current)
                }
                .accessibilityIdentifier("send.computer.current")
            }
            .fileImporter(isPresented: $picksPDF, allowedContentTypes: [UTType.pdf]) { (result: Result<URL, Error>) in
                picked(result)
            }
    }

    private func picked(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            state.appendToPDF(at: url)
        case .failure(let error):
            state.errorMessage = error.localizedDescription
        }
    }
}

/// What waits on the keep-pages question: why the pages would be left without a Save
/// (`IOSShell.keepPagesReason`), and what was asked for, run once a save has emptied the queue (`discarding`
/// false) or to go on with the pages dropped (`discarding` true).
struct PagesLeave {
    let reason: String
    let action: @MainActor (_ discarding: Bool) -> Void
}

/// Keep the 3 pages? Asked before something that would leave the queued pages without a Save: the ID card
/// (`AppState.pagesLeftBehind(by:)`), a preset that does not collect pages, a document
/// opened as new. Save first (`IOSShell.saveFirstLabel`) saves them as Save would, without After saving's
/// steps, and goes on once the save has emptied the queue; a save that fails or is cancelled keeps the pages
/// and changes nothing. It is left out when the save could write nothing (every page skipped) or cannot run
/// now (`blocked`, or a share or a send reading the pages, `AppState.readsQueue`). Discard goes on and drops the pages, Cancel keeps both.
/// What was asked for is taken when the alert opens, as the ID card's question takes it: the alert's
/// dismissal clears it, and SwiftUI may run that before the button.
@MainActor
struct KeepPagesQuestion: ViewModifier {
    @ObservedObject var state: AppState
    @Binding var leave: PagesLeave?
    let blocked: Bool
    /// What Save first was asked for, until its save ends.
    @State private var afterSave: PagesLeave?

    func body(content: Content) -> some View {
        let count: Int = state.scannedPages.count
        content
            .alert(IOSShell.keepPagesTitle(count), isPresented: shown, presenting: leave) { (asked: PagesLeave) in
                if canSave {
                    Button(saveFirstLabel) {
                        saveFirst(asked)
                    }
                    .accessibilityIdentifier("keepPages.save")
                }
                Button(IOSShell.discardPagesLabel(count), role: .destructive) {
                    asked.action(true)
                }
                .accessibilityIdentifier("keepPages.discard")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("keepPages.cancel")
            } message: { (asked: PagesLeave) in
                Text(IOSShell.keepPagesLine(asked.reason, count: count, canSave: canSave))
            }
            .onChange(of: state.isBusy) { (_: Bool, busy: Bool) in
                if !busy {
                    saveEnded()
                }
            }
    }

    private var plan: SavePlan {
        SavePlan.make(state.scannedPages, options: state.settings.document)
    }

    private var canSave: Bool {
        !blocked && !state.isBusy && !state.readsQueue && plan.pageCount > 0
    }

    private var saveFirstLabel: String {
        IOSShell.saveFirstLabel(state.settings, pageCount: plan.pageCount, target: state.appendTarget)
    }

    private func saveFirst(_ asked: PagesLeave) {
        afterSave = asked
        IOSShell.saveQueue(state)
        if !state.isBusy {
            afterSave = nil
        }
    }

    private func saveEnded() {
        guard let waiting = afterSave else { return }
        afterSave = nil
        if state.scannedPages.isEmpty {
            waiting.action(false)
        }
    }

    private var shown: Binding<Bool> {
        let question: Binding<PagesLeave?> = $leave
        return Binding<Bool>(
            get: { question.wrappedValue != nil },
            set: { (isShown: Bool) in
                if !isShown {
                    question.wrappedValue = nil
                }
            })
    }
}

/// A notice over the picture: on a rounded card of the system's plain background.
private struct NoticeCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// A scan's progress: the scanner's message ("Transferring page 3…", which counts a feeder's pages) with a
/// bar, determinate when the scanner says how far it is.
private struct ScanProgressRow: View {
    let progress: ScanProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let fraction = progress?.fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            if let message = progress?.message, !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("scan.progress")
    }
}

/// A stack turned over by hand, as the Mac's banner offers it: on to the backs after a feeder stopped early,
/// more fronts for a stack larger than the feeder, and once the backs did not pair up, combining the pages
/// anyway or scanning the backs again; the fronts alone while the backs are due. The status line asks for
/// these by name.
struct TurnedOverButtons: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if state.canFinishFronts {
                    Button("Done with fronts") {
                        state.finishFronts()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint(Text("Turn the stack over and scan the back sides"))
                    .accessibilityIdentifier("sides.doneWithFronts")
                }
                if state.awaitingBacks && state.sidesMismatch != nil {
                    Button(CameraTaskCatalog.combineLabel) {
                        state.combineSidesAnyway()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(Text("Puts the pages in order as they are; the extra pages go at the end"))
                    .accessibilityIdentifier("sides.combine")
                    Button("Scan backs again") {
                        state.scanBacksAgain()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(Text("Removes the back sides scanned so far"))
                    .accessibilityIdentifier("sides.backsAgain")
                }
                if state.canScanMoreFronts {
                    Button("Scan more fronts") {
                        state.scanMoreFronts()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(Text("For the sheets that did not fit in the feeder"))
                    .accessibilityIdentifier("sides.moreFronts")
                }
                if state.awaitingBacks {
                    Button("Keep fronts only") {
                        state.keepFrontsOnly()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(Text("Leaves out the back sides"))
                    .accessibilityIdentifier("sides.frontsOnly")
                }
            }
        }
        .disabled(state.isBusy)
    }

    /// Whether any button shows, so the scan screen leaves out an empty row.
    static func showsAny(_ state: AppState) -> Bool {
        state.canFinishFronts || state.awaitingBacks
    }
}

/// The files saved last, with Undo (when the save can be taken back), Print (PDFs and pictures), Share and
/// Show in Files. Print hands the files to Lazy Print when it is installed, else shows the AirPrint sheet.
private struct SavedFilesRow: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let urls: [URL] = state.lastSavedURLs
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.green)
                .accessibilityHidden(true)
            Text(savedNames(urls))
                .font(.subheadline)
                .lineLimit(2)
                .accessibilityIdentifier("saved.files")
            Spacer(minLength: 0)
            if state.canUndoSave {
                Button {
                    state.undoSave()
                } label: {
                    ViewThatFits(in: .horizontal) {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .labelStyle(.titleAndIcon)
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .labelStyle(.iconOnly)
                    }
                    .font(.subheadline)
                }
                .accessibilityLabel(Text("Undo"))
                .accessibilityHint(Text("Puts the pages back in the queue, deleting the saved files or restoring the PDF they were added to. Files already shared or sent stay where they went."))
                .accessibilityIdentifier("save.undo")
            }
            if SaveActions.canPrintWithLazyPrint(urls) {
                Button {
                    printSaved(urls)
                } label: {
                    Label("Print", systemImage: "printer")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel(Text("Print"))
                .accessibilityIdentifier("saved.print")
            }
            Button {
                state.runFileAction(.share, urls: urls)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel(Text("Share"))
            .accessibilityIdentifier("share.button")
            Button {
                state.runFileAction(.reveal, urls: urls)
            } label: {
                Label("Show in Files", systemImage: "folder")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel(Text("Show in Files"))
            .accessibilityIdentifier("reveal.button")
        }
    }

    private func printSaved(_ urls: [URL]) {
        if state.lazyPrintInstalled {
            state.runFileAction(.lazyPrint, urls: urls)
            return
        }
        guard let service = state.printService as? IOSPrintService else { return }
        let appState: AppState = state
        Task { @MainActor in
            do {
                _ = try await service.printFiles(urls)
            } catch {
                appState.errorMessage = error.localizedDescription
            }
        }
    }

    private func savedNames(_ urls: [URL]) -> String {
        var names: [String] = []
        for url in urls {
            names.append(url.lastPathComponent)
        }
        return names.joined(separator: ", ")
    }
}

/// A Lazy Scan document opened in the app or picked in Files, offered until it is taken or closed:
/// "Opened Receipt.lsdoc: 3 pages", with Add to pages (after the queued pages) and Open as new (in place
/// of them, `onOpenAsNew`). A kind that keeps no pages offers only Open in Document, and Document with
/// Collect pages before saving off only Open as new, which turns it on.
private struct PackageBanner: View {
    @EnvironmentObject private var state: AppState
    let offered: PendingPackage
    let onOpenAsNew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "doc.on.doc.fill")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text(PackageText.openedMessage(offered.fileName, pageCount: offered.pageCount))
                    .font(.subheadline)
                    .lineLimit(2)
                    .accessibilityIdentifier("package.opened")
                Spacer(minLength: 0)
                Button {
                    state.dismissPendingPackage()
                } label: {
                    Label("Close", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel(Text("Close"))
                .accessibilityIdentifier("package.close")
            }
            HStack(spacing: 12) {
                if IOSShell.takesWholePages(state.settings) {
                    Button(PackageText.addToPages) {
                        _ = state.addPendingPackageToPages()
                    }
                    .accessibilityIdentifier("package.add")
                    Button(PackageText.openAsNew) {
                        onOpenAsNew()
                    }
                    .accessibilityIdentifier("package.new")
                } else {
                    Button(openLabel) {
                        onOpenAsNew()
                    }
                    .accessibilityIdentifier("package.new")
                }
            }
            .buttonStyle(.bordered)
            .disabled(!state.canIngest)
        }
    }

    private var openLabel: String {
        IOSShell.shownKind(state.settings) == .document ? PackageText.openAsNew : IOSShell.openPackageInDocumentLabel
    }
}

/// The scan screen's full-screen covers (the scan area, the ID card's review, Quick scan's page,
/// the copy screen) and a book spread's split sheet. The root view presents them, not the scan screen: the
/// window's two layouts each build their own scan screen, and one going away would close them mid-task.
@MainActor
struct ScanCovers: ViewModifier {
    @ObservedObject var state: AppState
    @Binding var cover: ScanCover?
    @Binding var spreadEditor: SpreadEditorSource?

    func body(content: Content) -> some View {
        content
            .sheet(item: $spreadEditor) { (source: SpreadEditorSource) in
                SpreadSplitSheet(source: source, onClose: closeSpreadEditor)
                    .environmentObject(state)
            }
            .fullScreenCover(item: $cover) { (shown: ScanCover) in
                switch shown {
                case .crop:
                    CropScreen(onClose: closeCover)
                        .environmentObject(state)
                case .idCardReview:
                    IdCardReviewScreen(model: IOSIdCardReviewModel(state: state))
                        .environmentObject(state)
                case .quickScan:
                    QuickScanScreen(model: IOSQuickScanModel(state: state))
                        .environmentObject(state)
                case .copy:
                    CopyScreen(model: IOSCopyModel(state: state))
                        .environmentObject(state)
                }
            }
    }

    private func closeCover() {
        cover = nil
    }

    private func closeSpreadEditor() {
        spreadEditor = nil
    }
}
#endif
