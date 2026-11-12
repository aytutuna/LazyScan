#if os(iOS)
import AVFoundation
import AVKit
import LazyScanKit
import QuartzCore
import SwiftUI
import UIKit

/// Camera mode, the iPhone's scan screen unless printer mode was picked (`IOSScanMode`): the viewfinder is
/// the screen. Its top bar (`ScanTopBar`) has the library (`onLibrary`; none where the sidebar has it), a
/// small round arrow that opens the options drawer (`ScanDrawer`) above the bottom bar, the Auto chip (on or
/// off, a tap switches it), the flash button where the camera has a light, and the scanner, which switches
/// to printer mode (`onPrinter`). The photo size ("24 MP", where the camera offers more than one: a tap
/// steps to the next, the first pick of a size that may not fit in the phone's memory says so once) is in
/// the drawer's Camera group. The viewfinder shows the whole photo as it will be taken (black bands where the screen is
/// taller or wider), the page's outline, or every print's or receipt's, over it (yellow, green once the page holds still), one status line at
/// its top (the glare hint, why the automatic shutter waits, "Page found · hold still", else the task's
/// camera line, `CameraTaskCatalog`), the ID card's guide frame, and at its foot what the scan screen hands
/// in (`notices`: the package banner, the app's progress with Cancel while it is busy, an import's progress
/// with Stop, the files saved last) and the task's buttons between shots (`CameraTaskButtons`, No back side
/// for the ID card). Where the camera cannot be used (no camera, as in the Simulator; access off, with
/// Settings; not allowed) or waits (too warm, interrupted), one short line says why in its place. Over the
/// viewfinder's bottom corners the scan screen's Options and Save buttons (`pictureButtons`, `PictureButtons`),
/// which the notices, the ID card's guide and the message keep clear of. Under it the bottom bar: the pages
/// as a stack with their count (`onPages`, the page strip's sheet), the shutter with a ring that fills while
/// the page holds still, and Photos and Files. With Auto on the photo is taken by itself once the page held still on a sharp, lit
/// frame (`IOSCameraModel`), with a short tap felt; VoiceOver says the wait once per wait
/// (`IOSWaitAnnouncer`). Each photo goes through the photo import (`IOSImportSession.importShot`); in
/// continuous capture (`IOSShell.capturesContinuously`) a page found clearly goes straight into the queue,
/// otherwise the root view's corner editor opens. The camera rests while anything covers it (`resting`: a
/// sheet, a cover, the corner editor; Photos or Files), so Auto takes nothing meanwhile, and waits for the
/// card saying why it is asked for (`waitsForIntro`) before iOS asks. With a keyboard, Space takes a photo.
/// In landscape (a compact height) the viewfinder fills the height between a column of the top bar's buttons and
/// Photos and Files, and a column with the arrow, Auto, Flash, the shutter and the pages; the drawer opens as a
/// panel over the viewfinder's trailing edge.
struct CameraScreen<Notices: View, Buttons: View>: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var importer: IOSImportSession
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @StateObject private var model: IOSCameraModel
    @State private var waitAnnouncer: IOSWaitAnnouncer = IOSWaitAnnouncer()
    /// The count of prints or receipts found, waiting to be spoken once it has stayed the same for a second.
    @State private var countAnnouncement: Task<Void, Never>?
    @State private var announcedCount: String?
    @State private var showsDrawer: Bool = false
    @State private var drawerGroup: DrawerGroup = .colour
    /// Photos or Files is open over the camera.
    @State private var picking: Bool = false
    /// The photo size picked, as Options keeps it; 0 until one is.
    @AppStorage(IOSCameraLens.megapixelsKey) private var chosenMegapixels: Int = 0
    @AppStorage(IOSShell.itemsInFrameKey) private var items: IOSItemsInFrame = .auto
    /// The size just picked here that may not fit in this phone's memory, for its alert.
    @State private var memoryWarned: IOSPhotoSize?
    /// The preview's zoom, 1 at the wide lens's view, and whether its readout is up (while pinching and a moment after).
    @State private var zoomValue: Double = 1
    @State private var showsZoom: Bool = false
    private let resting: Bool
    private let holdsAuto: Bool
    private let waitsForIntro: Bool
    private let allowPending: Bool
    private let onAllow: () -> Void
    private let onLibrary: (() -> Void)?
    private let onPrinter: () -> Void
    private let onPages: () -> Void
    private let notices: () -> Notices
    private let pictureButtons: () -> Buttons

    init(resting: Bool, holdsAuto: Bool, waitsForIntro: Bool, allowPending: Bool, onAllow: @escaping () -> Void,
         onLibrary: (() -> Void)?,
         onPrinter: @escaping () -> Void, onPages: @escaping () -> Void,
         @ViewBuilder notices: @escaping () -> Notices, @ViewBuilder pictureButtons: @escaping () -> Buttons) {
        _model = StateObject(wrappedValue: IOSCameraModel.makeLive())
        self.resting = resting
        self.holdsAuto = holdsAuto
        self.waitsForIntro = waitsForIntro
        self.allowPending = allowPending
        self.onAllow = onAllow
        self.onLibrary = onLibrary
        self.onPrinter = onPrinter
        self.onPages = onPages
        self.notices = notices
        self.pictureButtons = pictureButtons
    }

    var body: some View {
        layout
            .background(Color(uiColor: .systemBackground))
            .onAppear {
                if !waitsForIntro {
                    start()
                }
            }
            .onDisappear {
                model.disappear()
            }
            .onChange(of: waitsForIntro) { (_: Bool, waits: Bool) in
                if !waits {
                    start()
                }
            }
            .onChange(of: scenePhase) { (_: ScenePhase, phase: ScenePhase) in
                if phase == .background {
                    model.apply(IOSCameraEvent.background)
                } else if phase == .active {
                    model.apply(IOSCameraEvent.foreground)
                }
            }
            .onChange(of: covered) { (_: Bool, rests: Bool) in
                model.apply(rests ? IOSCameraEvent.reviewStarted : IOSCameraEvent.reviewEnded)
            }
            .onChange(of: holdsAuto) { (_: Bool, holds: Bool) in
                allowPages()
                if !holds {
                    model.rearm()
                }
            }
            .onChange(of: canShoot) { (_: Bool, can: Bool) in
                // A page Auto decided on while no photo could be taken (the shot queue full, a save) is judged again now.
                if can {
                    model.rearm()
                }
            }
            .onChange(of: kind) { (_: CaptureKind, next: CaptureKind) in
                announcedCount = nil
                model.setKind(next, singleItem: singleItem)
            }
            .onChange(of: singleItem) { (_: Bool, single: Bool) in
                model.setKind(kind, singleItem: single)
            }
            .onChange(of: countLine) { (_: String?, line: String?) in
                announceCount(line)
            }
            .onChange(of: model.tapToTake) { (_: Bool, on: Bool) in
                if on {
                    AccessibilityNotification.Announcement(IOSCameraText.tapToTake).post()
                }
            }
            .onChange(of: waitCue) { (_: IOSWaitCue, cue: IOSWaitCue) in
                // Spoken once per wait, when the line is first shown, so a VoiceOver user knows why nothing is
                // taken yet without hearing it again each time a frame flips it.
                if let reason = waitAnnouncer.next(cue) {
                    AccessibilityNotification.Announcement(reason).post()
                }
            }
            .onChange(of: chosenMegapixels) { (_: Int, megapixels: Int) in
                if let controller = model.driver as? IOSCameraController {
                    controller.usePhotoSize(megapixels: megapixels)
                }
            }
            .alert(IOSCameraText.memoryTitle, isPresented: memoryAlertShown, presenting: memoryWarned) { (size: IOSPhotoSize) in
                Button(IOSCameraText.useLabel(size)) {}
                if let safer = IOSCameraLens.saferSize(among: IOSCameraLens.choices(IOSCameraLens.offered),
                                                       physicalMemory: ProcessInfo.processInfo.physicalMemory) {
                    Button(IOSCameraText.useLabel(safer)) {
                        chosenMegapixels = IOSCameraLens.megapixels(safer)
                    }
                }
            } message: { (size: IOSPhotoSize) in
                Text(IOSCameraText.memoryWarning(size, among: IOSCameraLens.choices(IOSCameraLens.offered),
                                                 physicalMemory: ProcessInfo.processInfo.physicalMemory) ?? "")
            }
            .sensoryFeedback(SensoryFeedback.impact(weight: SensoryFeedback.Weight.medium), trigger: model.shotCount)
    }

    private var layout: some View {
        let compact: Bool = verticalSizeClass == .compact
        let stack: AnyLayout = compact ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        return stack {
            if compact {
                leadingColumn
            } else {
                topBar
            }
            viewfinder
                .overlay(alignment: .trailing) {
                    sidePanel
                }
            if compact {
                trailingColumn
            } else {
                lowerRow
                CaptureRow(onPages: onPages, onPresenting: setPicking) {
                    shutter
                }
            }
        }
    }

    // MARK: The landscape layout

    private var leadingColumn: some View {
        VStack(spacing: 8) {
            libraryButton
            printerButton
            Spacer(minLength: 0)
            ImportButtons(round: true, stacked: true, onPresenting: setPicking)
        }
        .frame(width: 56)
        .padding(.vertical, 4)
    }

    private var trailingColumn: some View {
        VStack(spacing: 8) {
            sideToggle
            autoQuickButton
            torchQuickButton
            Spacer(minLength: 0)
            shutter
            Spacer(minLength: 0)
            PagesStack(onPages: onPages)
        }
        .frame(width: 96)
        .padding(.vertical, 4)
    }

    /// The options drawer in landscape: a panel over the viewfinder's trailing edge, since there is no
    /// height under the picture.
    @ViewBuilder
    private var sidePanel: some View {
        if showsDrawer && verticalSizeClass == .compact {
            ScrollView {
                ScanDrawer(model: model, torch: model.hasTorch, group: $drawerGroup)
                    .padding(.top, 8)
            }
            .frame(width: 300)
            .background(UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 14, style: .continuous)
                .fill(Color(uiColor: .systemBackground).opacity(0.95)))
            .transition(.move(edge: .trailing))
        }
    }

    @ViewBuilder
    private var libraryButton: some View {
        if let open = onLibrary {
            Button {
                open()
            } label: {
                Image(systemName: "books.vertical")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(IOSSettingsText.libraryLabel))
            .accessibilityIdentifier("open.library")
        }
    }

    private var sideToggle: some View {
        let open: Bool = showsDrawer
        let symbol: String = open ? "chevron.forward" : "chevron.backward"
        let label: String = open ? IOSCameraText.hideOptions : IOSCameraText.showOptions
        return Button {
            withAnimation(Animation.snappy) {
                showsDrawer.toggle()
            }
        } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(open ? Color.white : Color.primary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(open ? Color.accentColor : Color(uiColor: .tertiarySystemFill)))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier("drawer.toggle")
    }

    /// The drawer's Auto shutter switch as a round button, for landscape where the drawer is not in sight.
    private var autoQuickButton: some View {
        let on: Bool = model.autoShutter
        let value: String = on ? IOSCameraText.onValue : IOSCameraText.offValue
        let shown: IOSCameraModel = model
        return Button {
            shown.setAutoShutter(!on)
        } label: {
            quickLabel("a.circle", on: on)
        }
        .buttonStyle(.plain)
        .disabled(state.isBusy || importer.isImporting)
        .accessibilityLabel(Text(IOSCameraText.autoShutterLabel))
        .accessibilityValue(Text(value))
        .accessibilityHint(Text(IOSCameraText.autoHint))
        .accessibilityIdentifier("camera.autoQuick")
    }

    /// The drawer's Flash group as a round button, where the camera has a light.
    @ViewBuilder
    private var torchQuickButton: some View {
        if model.hasTorch {
            let on: Bool = model.torchOn
            let symbol: String = on ? "bolt" : "bolt.slash"
            let value: String = on ? IOSCameraText.onValue : IOSCameraText.offValue
            let shown: IOSCameraModel = model
            Button {
                Task { @MainActor in
                    await shown.toggleTorch()
                }
            } label: {
                quickLabel(symbol, on: on)
            }
            .buttonStyle(.plain)
            .disabled(!model.lifecycle.isLive || state.isBusy || importer.isImporting)
            .accessibilityLabel(Text(IOSCameraText.flashLabel))
            .accessibilityValue(Text(value))
            .accessibilityIdentifier("camera.torchQuick")
        }
    }

    private func quickLabel(_ symbol: String, on: Bool) -> some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(on ? Color.white : Color.primary)
            .frame(width: 44, height: 44)
            .background(Circle().fill(on ? Color.accentColor : Color(uiColor: .tertiarySystemFill)))
            .contentShape(Circle())
    }

    // MARK: The top bar

    private var topBar: some View {
        ScanTopBar(showsDrawer: $showsDrawer, onLibrary: onLibrary) {
            HStack(spacing: 0) {
                autoChip
                flashButton
                printerButton
            }
        }
    }

    private var printerButton: some View {
        Button {
            onPrinter()
        } label: {
            Image(systemName: "scanner")
                .font(.title3)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(state.isBusy)
        .accessibilityLabel(Text(IOSCameraText.printerLabel))
        .accessibilityHint(Text(IOSCameraText.printerHint))
        .accessibilityIdentifier("mode.printer")
    }

    /// Whether the automatic shutter is on, and a switch for it, while the camera is shown (never in the
    /// Simulator, which has no camera).
    @ViewBuilder
    private var autoChip: some View {
        if model.showsPreview {
            let on: Bool = model.autoShutter
            let textColour: Color = on ? Color.white : Color.primary
            let fill: Color = on ? Color.accentColor : Color.clear
            Button {
                model.setAutoShutter(!on)
            } label: {
                Text(IOSCameraText.autoLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(textColour)
                    .padding(.horizontal, 12)
                    .frame(minWidth: 64, minHeight: 32)
                    .background(Capsule().fill(fill))
                    .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: 1))
                    .frame(minHeight: 44)
                    .opacity(state.isBusy ? 0.4 : 1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .disabled(state.isBusy)
            .accessibilityLabel(Text(IOSCameraText.autoShutterLabel))
            .accessibilityValue(Text(on ? IOSCameraText.onValue : IOSCameraText.offValue))
            .accessibilityHint(Text(IOSCameraText.autoHint))
            .accessibilityIdentifier("camera.autoChip")
        }
    }

    /// The camera's light, where it has one; the drawer's Flash group is the same switch.
    @ViewBuilder
    private var flashButton: some View {
        if model.showsPreview, model.hasTorch {
            let on: Bool = model.torchOn
            let enabled: Bool = model.lifecycle.isLive && !state.isBusy
            let glyphColour: Color = on ? Color.yellow : Color.primary
            let backing: Color = on ? Color.black.opacity(0.75) : Color.clear
            Button {
                turnLight(on: !on)
            } label: {
                Image(systemName: on ? "bolt.fill" : "bolt.slash")
                    .font(.title3)
                    .foregroundStyle(glyphColour)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(backing))
                    .frame(width: 44, height: 44)
                    .opacity(enabled ? 1 : 0.4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .disabled(!enabled)
            .accessibilityLabel(Text(IOSCameraText.flashLabel))
            .accessibilityValue(Text(on ? IOSCameraText.onValue : IOSCameraText.offValue))
            .accessibilityIdentifier("camera.flash")
        }
    }

    private func turnLight(on: Bool) {
        let shown: IOSCameraModel = model
        guard on != shown.torchOn else { return }
        Task { @MainActor in
            await shown.toggleTorch()
        }
    }

    // MARK: The viewfinder

    /// The look the viewfinder shows over the preview: the saved page's filter and adjustments, while the
    /// camera runs in the front; nil for Original with nothing adjusted, where the plain preview is all there is.
    private var filterLook: LiveLook? {
        guard scenePhase == .active, model.lifecycle.isLive else { return nil }
        let look: LiveLook = LiveLook(settings: state.settings)
        return look.isFiltering ? look : nil
    }

    private var viewfinder: some View {
        ZStack {
            Color.black
            if model.showsPreview, let controller = model.driver as? IOSCameraController {
                let zoomText: String = IOSCameraText.zoomLabel(controller.zoom)
                CameraPreview(controller: controller, outlines: outlines,
                              steady: model.live?.isSteady ?? false, look: filterLook, active: model.canShoot,
                              onZoom: showZoom, onShutter: shootFromButton)
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityElement(children: .ignore)
                    .accessibilityHidden(!model.canShoot)
                    .accessibilityLabel(Text(IOSCameraText.zoomLabel))
                    .accessibilityValue(Text(zoomText))
                    .accessibilityAdjustableAction { (direction: AccessibilityAdjustmentDirection) in
                        stepZoom(controller, up: direction == .increment)
                    }
                    .accessibilityIdentifier("camera.zoom")
            }
            if shownMessage == nil, let prompt = cardPrompt {
                IdCardGuide(prompt: prompt)
                    .padding(.bottom, PictureButtons.clearance)
            }
            if let line = shownMessage {
                messageCard(line)
                    .padding(.bottom, PictureButtons.clearance)
            }
            overlays
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, PictureButtons.clearance)
            pictureButtons()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onChange(of: model.canShoot) { (_: Bool, can: Bool) in
            // The camera starts afresh at its start zoom once it runs again.
            if !can {
                showsZoom = false
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera.screen")
    }

    private func showZoom(_ zoom: Double, shown: Bool) {
        zoomValue = zoom
        if shown {
            showsZoom = true
        } else {
            withAnimation(.easeOut(duration: 0.3)) {
                showsZoom = false
            }
        }
    }

    private func stepZoom(_ controller: IOSCameraController, up: Bool) {
        let step: Double = up ? 0.5 : -0.5
        zoomValue = controller.setZoom(controller.zoom + step)
    }

    /// The outlines over the preview: the one page's, or every print or receipt found.
    private var outlines: [Quad] {
        guard let update = model.live else { return [] }
        if !update.outlines.isEmpty {
            return update.outlines
        }
        if let page = update.outline {
            return [page]
        }
        return []
    }

    /// The status line at the top; at the foot the notices and the task's buttons.
    private var overlays: some View {
        VStack(spacing: 8) {
            if shownMessage == nil, let status = statusLine {
                StatusPill(text: status.text, hint: status.hint, action: status.action)
                    .accessibilityIdentifier(status.identifier)
            }
            if showsZoom {
                StatusPill(text: IOSCameraText.zoomLabel(zoomValue), hint: nil)
                    .transition(.opacity)
                    .accessibilityIdentifier("camera.zoomReadout")
            }
            Spacer(minLength: 0)
            notices()
            if let mismatch = state.sidesMismatch, state.cameraSides != nil {
                MismatchPill(text: mismatch)
            }
            CameraTaskButtons(onDark: true)
            if state.canSkipStep {
                Button(IdCardSteps.skipBackLabel) {
                    state.skipStep()
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isBusy || importer.isImporting)
                .accessibilityIdentifier("camera.skipBack")
            }
        }
    }

    /// The model's line, or that the camera is not on yet while it waits for Allow camera.
    private var shownMessage: String? {
        allowPending ? IOSCameraText.notOnYet : model.message
    }

    /// Why the camera cannot be used or waits, with Settings when access is off, or Allow camera.
    private func messageCard(_ line: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "camera.badge.ellipsis")
                .font(.largeTitle)
                .foregroundStyle(Color.white)
                .accessibilityHidden(true)
            Text(line)
                .font(.headline)
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("camera.message")
            if model.opensSettings {
                Button(IOSCameraText.settingsLabel) {
                    openSettings()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("camera.settings")
            }
            if allowPending {
                Button(IOSCameraText.allowLabel) {
                    onAllow()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint(Text(IOSCameraText.allowHint))
                .accessibilityIdentifier("camera.allow")
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.12)))
        .accessibilityElement(children: .contain)
    }

    /// The one line at the viewfinder's top: the glare hint for the ID card's back, "Tap to take" while the
    /// live search is off, how the page sits in the frame, the count of prints or receipts found, why a page
    /// held still is not taken yet, that it is about to be (these three only while a photo can be taken), else
    /// the task's camera line (none under the ID card's guide, which says the side itself).
    private var statusLine: CameraStatus? {
        if let glare = glareLine {
            return CameraStatus(text: glare, hint: nil, identifier: "camera.glare")
        }
        if model.tapToTake {
            return CameraStatus(text: IOSCameraText.tapToTake, hint: nil, identifier: "camera.tap")
        }
        if let placed = placementLine {
            return CameraStatus(text: placed, hint: nil, identifier: "camera.placement")
        }
        if let reason = waitLine {
            if offersLight {
                return CameraStatus(text: IOSCameraText.tooDarkTapForLight, hint: IOSCameraText.tooDarkHint,
                                    identifier: "camera.wait", action: { turnLight(on: true) })
            }
            return CameraStatus(text: reason, hint: nil, identifier: "camera.wait")
        }
        if let found = objectsStatus {
            return found
        }
        if model.autoShutter && canShoot && model.live?.state == CaptureState.steadying {
            return CameraStatus(text: IOSCameraText.pageFound(CaptureObjects.kind(for: state.settings)), hint: nil,
                                identifier: "camera.found")
        }
        guard cardPrompt == nil, let line = taskLine else { return nil }
        return CameraStatus(text: line.prompt, hint: line.help, identifier: "camera.prompt")
    }

    /// The count of prints or receipts outlined, as the status line says it (with "hold still" while Auto waits
    /// for the set to settle); nil for the other kinds or with none in view.
    private var objectsStatus: CameraStatus? {
        let current: CaptureKind = kind
        guard CaptureObjects.findsSeveral(current), let update = model.live, !update.outlines.isEmpty else { return nil }
        let count: Int = update.outlines.count
        if model.autoShutter && canShoot && update.state == CaptureState.steadying {
            return CameraStatus(text: IOSCameraText.objectsFoundHoldStill(current, count: count), hint: nil,
                                identifier: "camera.found")
        }
        return CameraStatus(text: IOSCameraText.objectsFound(current, count: count), hint: nil, identifier: "camera.count")
    }

    /// What VoiceOver says about the set found: the count, nil with none in view.
    private var countLine: String? {
        let current: CaptureKind = kind
        guard CaptureObjects.findsSeveral(current), let update = model.live, !update.outlines.isEmpty else { return nil }
        return IOSCameraText.objectsFound(current, count: update.outlines.count)
    }

    private var kind: CaptureKind {
        CaptureObjects.kind(for: state.settings)
    }

    /// Items in frame is One for a shot of prints, which then keeps only the largest.
    private var singleItem: Bool {
        IOSShell.offersItemsInFrame(state.settings) && items == .one
    }

    /// Speaks the count once it has stayed the same for a second, so a count that flickers is not read out,
    /// and not again while the same count comes back after a shot.
    private func announceCount(_ line: String?) {
        countAnnouncement?.cancel()
        guard let text = line, text != announcedCount else { return }
        countAnnouncement = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            announcedCount = text
            AccessibilityNotification.Announcement(text).post()
        }
    }

    /// The task's camera line now (`CameraTaskCatalog.current`); nil without a task.
    private var taskLine: CameraStepText? {
        CameraTaskCatalog.current(state.activeTask, options: state.settings.taskOptions, sides: state.cameraSides,
                                  newDocument: state.newDocumentPending)
    }

    /// The ID card's guide frame's line: the side to take ("Fit the front in the frame"); nil for other tasks.
    private var cardPrompt: String? {
        guard CaptureObjects.kind(for: state.settings) == .idCard else { return nil }
        return IOSIdCardGuide.prompt(stepID: state.taskFlow?.current?.id)
    }

    /// The glare hint while the back is next and the front was taken with glare on it.
    private var glareLine: String? {
        guard CaptureObjects.kind(for: state.settings) == .idCard else { return nil }
        return IOSIdCardGuide.glareLine(stepID: state.taskFlow?.current?.id, frontNote: state.idCardFrontNote)
    }

    /// Why the page held still is not taken yet (a blurred or dark frame), while the automatic shutter waits
    /// and a photo can be taken.
    private var waitLine: String? {
        guard model.autoShutter, canShoot, let update = model.live,
              update.state == CaptureState.steadying else { return nil }
        return IOSCameraText.waitReason(update.quality, suggestsShutter: update.suggestsShutter)
    }

    /// Move closer or fit the whole page, while a page is seen moving or held still, or seen cut off by the
    /// frame, and a photo can be taken; not for the kinds that take several objects, which the tracker's one
    /// page does not describe.
    private var placementLine: String? {
        let kind: CaptureKind = CaptureObjects.kind(for: state.settings)
        guard canShoot, let update = model.live, !CaptureObjects.findsSeveral(kind) else { return nil }
        let followed: Bool = update.outline != nil
            && (update.state == CaptureState.moving || update.state == CaptureState.steadying)
        guard followed || update.placement == CapturePlacement.cutOff else { return nil }
        return IOSCameraText.placementHint(update.placement, kind: kind)
    }

    /// The frame is dark and the camera has a light that is off: the wait line can turn it on.
    private var offersLight: Bool {
        model.hasTorch && !model.torchOn && model.lifecycle.isLive && model.live?.quality == CaptureQuality.dark
    }

    /// Whether a page held still waits, and the wait line as shown (nil while a message or the glare hint
    /// is shown in its place), for VoiceOver (`IOSWaitAnnouncer`).
    private var waitCue: IOSWaitCue {
        let steadying: Bool = model.autoShutter && model.live?.state == CaptureState.steadying
        let hidden: Bool = shownMessage != nil || glareLine != nil || placementLine != nil
        return IOSWaitCue(steadying: steadying, line: hidden ? nil : waitLine)
    }

    // MARK: Under the viewfinder

    @ViewBuilder
    private var lowerRow: some View {
        if showsDrawer {
            ScanDrawer(model: model, torch: model.hasTorch, group: $drawerGroup, onSizeStep: stepPhotoSize(from:in:))
                .transition(.opacity)
        }
    }

    private var shutter: some View {
        ShutterRing(progress: ringProgress, enabled: canShoot, label: IOSCameraText.shutterLabel,
                    hint: IOSCameraText.shutterHint(CaptureObjects.kind(for: state.settings)),
                    identifier: "camera.shutter", action: shoot)
            .keyboardShortcut(IOSShortcuts.shutter.keyboardShortcut)
    }

    /// How far the page is through the steady time, for the ring around the shutter (Auto on, while a photo
    /// can be taken).
    private var ringProgress: CGFloat {
        guard model.autoShutter, canShoot, let update = model.live,
              update.state == CaptureState.steadying else { return 0 }
        return CGFloat(update.progress)
    }

    // MARK: The camera's life

    /// The automatic shutter's way into the import, then the camera, resting first when it is covered.
    private func start() {
        let shown: IOSCameraModel = model
        let session: IOSImportSession = importer
        let appState: AppState = state
        // Read at each shot: a kind picked meanwhile changes it.
        shown.onAutoShot = { [weak shown] (shot: IOSCameraShot) async -> Void in
            let continuous: Bool = IOSShell.capturesContinuously(appState.settings)
            let outcome: IOSImportOutcome = await session.importShot(shot, asksOnlyWhenUnsure: continuous)
            shown?.shotImported(outcome)
        }
        allowPages()
        shown.setKind(kind, singleItem: singleItem)
        shown.apply(covered ? IOSCameraEvent.reviewStarted : IOSCameraEvent.reviewEnded)
        Task { @MainActor in
            await shown.appear()
        }
    }

    /// Auto takes a page only while the queue can take one and nothing, an open sheet say, holds it back.
    private func allowPages() {
        let session: IOSImportSession = importer
        let held: Bool = holdsAuto
        model.canTakePage = { () -> Bool in
            session.canQueueShot && (!session.isImporting || session.importsShot) && !held
        }
    }

    /// The session stops while something covers the camera (the corner editor among them) and runs again
    /// once nothing does.
    private var covered: Bool {
        resting || picking || memoryWarned != nil || importer.cornerRequest != nil
    }

    private func setPicking(_ shown: Bool) {
        picking = shown
    }

    /// The camera is live, no photo is being taken, and the queue can take another shot.
    private var canShoot: Bool {
        model.canShoot && importer.canQueueShot && (!importer.isImporting || importer.importsShot)
    }

    /// A volume button or the Camera Control; nothing happens while a sheet or the drawer is over the camera.
    private func shootFromButton() {
        guard !covered, !showsDrawer else { return }
        shoot()
    }

    private func shoot() {
        guard canShoot else { return }
        let shown: IOSCameraModel = model
        let session: IOSImportSession = importer
        let continuous: Bool = IOSShell.capturesContinuously(state.settings)
        Task { @MainActor in
            if let shot = await shown.shoot() {
                let outcome: IOSImportOutcome = await session.importShot(shot, asksOnlyWhenUnsure: continuous)
                shown.shotImported(outcome)
            }
        }
    }

    /// Picks the size after `current`; the first time a size that may not fit in this phone's memory is
    /// picked here (remembered for each size), the alert says so and offers the largest that does.
    private func stepPhotoSize(from current: IOSPhotoSize, in choices: [IOSPhotoSize]) {
        guard let next = IOSCameraLens.nextChoice(after: current, in: choices) else { return }
        let megapixels: Int = IOSCameraLens.megapixels(next)
        chosenMegapixels = megapixels
        let key: String = "camera.memoryWarned.\(megapixels)"
        let defaults: UserDefaults = UserDefaults.standard
        guard IOSCameraLens.warns(next, physicalMemory: ProcessInfo.processInfo.physicalMemory),
              !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        memoryWarned = next
    }

    private var memoryAlertShown: Binding<Bool> {
        Binding<Bool>(
            get: { memoryWarned != nil },
            set: { (shown: Bool) in
                if !shown {
                    memoryWarned = nil
                }
            })
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

/// The viewfinder's status line: its words, what VoiceOver says after them, and its identifier.
private struct CameraStatus {
    let text: String
    let hint: String?
    let identifier: String
    var action: (() -> Void)? = nil
}

/// A line on a dark capsule over a picture; with `action` it is a button, with a bolt before the words.
struct StatusPill: View {
    let text: String
    let hint: String?
    var action: (() -> Void)? = nil

    var body: some View {
        if let action {
            Button {
                action()
            } label: {
                pill
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(hint ?? ""))
        } else {
            pill
                .accessibilityHint(Text(hint ?? ""))
        }
    }

    private var pill: some View {
        HStack(spacing: 6) {
            if action != nil {
                Image(systemName: "bolt.fill")
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Color.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.75)))
    }
}

/// Says a scan area is set, with a button that clears it; the next flatbed scan uses the area.
struct AreaPill: View {
    let isBusy: Bool
    let onClear: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                label
                clearButton
            }
            VStack(spacing: 0) {
                label
                clearButton
            }
        }
        .padding(.horizontal, 12)
        .background(Capsule().fill(Color.black.opacity(0.75)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Scan area set"))
        .accessibilityIdentifier("area.pill")
    }

    private var label: some View {
        Text("Scan area set")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
    }

    private var clearButton: some View {
        Button {
            onClear()
        } label: {
            Text("Clear")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
        .disabled(isBusy)
        .accessibilityLabel(Text("Clear scan area"))
        .accessibilityHint(Text("The next scan covers the whole glass."))
        .accessibilityIdentifier("area.pill.clear")
    }
}

/// The camera's live preview with the page's outline drawn over it, and over the preview, under the
/// outline, the picture with the saved page's filter (`look`, `LiveViewfinder`) when there is one. The
/// outline comes as shares of the sensor's frame (as the live frames are searched) and is placed with the
/// preview layer's own conversion (`layerPointConverted(fromCaptureDevicePoint:)`), which knows how the
/// preview is turned and where the whole frame sits in the view.
struct CameraPreview: UIViewRepresentable {
    let controller: IOSCameraController
    let outlines: [Quad]
    let steady: Bool
    let look: LiveLook?
    /// A tap focuses and a pinch zooms only while this is true (the camera is live and no photo is being taken).
    let active: Bool
    /// Told the zoom (1 at the wide lens's view) while pinching, and once more, shown false, a second after the fingers lift.
    let onZoom: (Double, Bool) -> Void
    let onShutter: () -> Void

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.controller = controller
        controller.attach(previewLayer: view.previewLayer, viewfinder: view.viewfinder)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.onZoom = onZoom
        uiView.active = active
        uiView.onShutter = onShutter
        uiView.show(outlines: outlines, steady: steady)
        uiView.viewfinder?.show(look)
    }

    static func dismantleUIView(_ uiView: CameraPreviewView, coordinator: ()) {
        uiView.viewfinder?.show(nil)
    }
}

/// A view whose layer is the session's preview, with the filtered picture in a Metal layer over it and the
/// outline in a shape layer over that. A tap on it focuses and meters there (a white square marks the spot for
/// a second) and a pinch zooms; both are recognizers of this view, so nothing drawn above it loses a touch.
final class CameraPreviewView: UIView {
    private let outlineLayer = CAShapeLayer()
    private let focusSquare = UIView()
    private var pinchStart: Double = 1
    private var hideZoom: Task<Void, Never>?
    weak var controller: IOSCameraController?
    var onZoom: (Double, Bool) -> Void = { (_: Double, _: Bool) -> Void in }
    var active: Bool = true {
        didSet {
            guard active != oldValue else { return }
            for recognizer in gestureRecognizers ?? [] {
                recognizer.isEnabled = active
            }
            if !active {
                hideZoom?.cancel()
                focusSquare.layer.removeAllAnimations()
                focusSquare.alpha = 0
            }
        }
    }
    let viewfinder: LiveViewfinder? = LiveViewfinder()
    private var outlines: [Quad] = []
    private var steady: Bool = false
    var onShutter: (() -> Void)?

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // The layer class above makes this cast always succeed.
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black
        outlineLayer.lineWidth = 3
        outlineLayer.lineJoin = .round
        if let finder = viewfinder {
            layer.addSublayer(finder.layer)
        }
        layer.addSublayer(outlineLayer)
        addTouchHandling()
        addInteraction(AVCaptureEventInteraction { [weak self] (event: AVCaptureEvent) in
            if event.phase == .began {
                self?.onShutter?()
            }
        })
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        layer.addSublayer(outlineLayer)
        addTouchHandling()
    }

    private func addTouchHandling() {
        focusSquare.frame = CGRect(x: 0, y: 0, width: 72, height: 72)
        focusSquare.layer.borderWidth = 1.5
        focusSquare.layer.cornerRadius = 4
        focusSquare.layer.borderColor = UIColor.white.cgColor
        focusSquare.alpha = 0
        focusSquare.isUserInteractionEnabled = false
        focusSquare.accessibilityIdentifier = "camera.focusSquare"
        addSubview(focusSquare)
        layer.insertSublayer(focusSquare.layer, below: outlineLayer)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:))))
    }

    @objc private func tapped(_ tap: UITapGestureRecognizer) {
        let point: CGPoint = tap.location(in: self)
        let spot: CGPoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)
        // Outside the frame is a black band.
        guard (0...1).contains(spot.x), (0...1).contains(spot.y), let camera = controller,
              camera.focus(at: spot) else { return }
        showSquare(at: point)
    }

    private func showSquare(at point: CGPoint) {
        focusSquare.layer.removeAllAnimations()
        focusSquare.center = point
        focusSquare.alpha = 1
        if UIAccessibility.isReduceMotionEnabled {
            focusSquare.transform = CGAffineTransform.identity
        } else {
            focusSquare.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
            UIView.animate(withDuration: 0.2) {
                self.focusSquare.transform = CGAffineTransform.identity
            }
        }
        UIView.animate(withDuration: 0.3, delay: 1, options: [.allowUserInteraction]) {
            self.focusSquare.alpha = 0
        }
    }

    @objc private func pinched(_ pinch: UIPinchGestureRecognizer) {
        guard let camera = controller else { return }
        switch pinch.state {
        case .began:
            hideZoom?.cancel()
            pinchStart = camera.zoom
        case .changed:
            let zoom: Double = camera.setZoom(pinchStart * Double(pinch.scale))
            onZoom(zoom, true)
        case .ended, .cancelled, .failed:
            hideZoom?.cancel()
            hideZoom = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let view = self else { return }
                view.onZoom(view.controller?.zoom ?? 1, false)
            }
        default:
            break
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        outlineLayer.frame = bounds
        if let finder = viewfinder {
            finder.layer.contentsScale = traitCollection.displayScale
            finder.updateFrame()
        }
        redraw()
    }

    func show(outlines: [Quad], steady: Bool) {
        self.outlines = outlines
        self.steady = steady
        redraw()
    }

    private func redraw() {
        guard !outlines.isEmpty else {
            outlineLayer.path = nil
            return
        }
        let path = UIBezierPath()
        for quad in outlines {
            var index: Int = 0
            for corner in quad.corners {
                let point: CGPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: corner)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
                index += 1
            }
            path.close()
        }
        let color: UIColor = steady ? UIColor.systemGreen : UIColor.systemYellow
        outlineLayer.strokeColor = color.cgColor
        outlineLayer.fillColor = color.withAlphaComponent(0.15).cgColor
        outlineLayer.path = path.cgPath
    }
}
#endif
