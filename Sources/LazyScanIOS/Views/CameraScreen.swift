#if os(iOS)
import AVFoundation
import LazyScanKit
import QuartzCore
import SwiftUI
import UIKit

/// Camera mode, the iPhone's scan screen unless printer mode was picked (`IOSScanMode`): the viewfinder is
/// the screen. Its top bar (`ScanTopBar`) has the library (`onLibrary`; none where the sidebar has it), a
/// small round arrow that opens the options drawer (`ScanDrawer`) above the bottom bar, the photo size
/// ("24 MP", where the camera offers more than one: a tap steps to the next, the first pick of a size that
/// may not fit in the phone's memory says so once), and the scanner, which switches to printer mode
/// (`onPrinter`). The viewfinder shows the whole photo as it will be taken (black bands where the screen is
/// taller or wider), the page's outline over it (yellow, green once the page holds still), one status line at
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
struct CameraScreen<Notices: View, Buttons: View>: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var importer: IOSImportSession
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: IOSCameraModel
    @State private var waitAnnouncer: IOSWaitAnnouncer = IOSWaitAnnouncer()
    @State private var showsDrawer: Bool = false
    @State private var drawerGroup: DrawerGroup = .colour
    /// Photos or Files is open over the camera.
    @State private var picking: Bool = false
    /// The photo size picked, as Options keeps it; 0 until one is.
    @AppStorage(IOSCameraLens.megapixelsKey) private var chosenMegapixels: Int = 0
    /// The size just picked here that may not fit in this phone's memory, for its alert.
    @State private var memoryWarned: IOSPhotoSize?
    private let resting: Bool
    private let holdsAuto: Bool
    private let waitsForIntro: Bool
    private let onLibrary: (() -> Void)?
    private let onPrinter: () -> Void
    private let onPages: () -> Void
    private let notices: () -> Notices
    private let pictureButtons: () -> Buttons

    init(resting: Bool, holdsAuto: Bool, waitsForIntro: Bool, onLibrary: (() -> Void)?,
         onPrinter: @escaping () -> Void, onPages: @escaping () -> Void,
         @ViewBuilder notices: @escaping () -> Notices, @ViewBuilder pictureButtons: @escaping () -> Buttons) {
        _model = StateObject(wrappedValue: IOSCameraModel.makeLive())
        self.resting = resting
        self.holdsAuto = holdsAuto
        self.waitsForIntro = waitsForIntro
        self.onLibrary = onLibrary
        self.onPrinter = onPrinter
        self.onPages = onPages
        self.notices = notices
        self.pictureButtons = pictureButtons
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            viewfinder
            lowerRow
            CaptureRow(onPages: onPages, onPresenting: setPicking) {
                shutter
            }
        }
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
            // A page Auto decided on while no photo could be taken (an import, a save) is judged again now.
            if can {
                model.rearm()
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

    // MARK: The top bar

    private var topBar: some View {
        ScanTopBar(showsDrawer: $showsDrawer, onLibrary: onLibrary) {
            HStack(spacing: 0) {
                resolutionButton
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

    /// The size the next photo is taken at, while the camera is live and offers more than one (never in
    /// the Simulator, which has no camera).
    @ViewBuilder
    private var resolutionButton: some View {
        let choices: [IOSPhotoSize] = IOSCameraLens.choices(IOSCameraLens.offered)
        if model.showsPreview, choices.count > 1,
           let current = IOSCameraLens.photoSize(IOSCameraLens.offered, megapixels: chosenMegapixels) {
            let label: String = IOSCameraText.sizeLabel(current)
            Button {
                stepPhotoSize(from: current, in: choices)
            } label: {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 4)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .disabled(model.isTakingPhoto)
            .accessibilityLabel(Text(IOSCameraText.resolutionLabel))
            .accessibilityValue(Text(label))
            .accessibilityIdentifier("camera.resolution")
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
                CameraPreview(controller: controller, outline: model.live?.outline,
                              steady: model.live?.isSteady ?? false, look: filterLook)
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityHidden(true)
            }
            if model.message == nil, let prompt = cardPrompt {
                IdCardGuide(prompt: prompt)
                    .padding(.bottom, PictureButtons.clearance)
            }
            if let line = model.message {
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("camera.screen")
    }

    /// The status line at the top; at the foot the notices and the task's buttons.
    private var overlays: some View {
        VStack(spacing: 8) {
            if model.message == nil, let status = statusLine {
                StatusPill(text: status.text, hint: status.hint)
                    .accessibilityIdentifier(status.identifier)
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

    /// Why the camera cannot be used or waits, with Settings when access is off.
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
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.12)))
        .accessibilityElement(children: .contain)
    }

    /// The one line at the viewfinder's top: the glare hint for the ID card's back, why a page held still
    /// is not taken yet, that it is about to be (these two only while a photo can be taken), else the task's
    /// camera line (none under the ID card's guide, which says the side itself).
    private var statusLine: CameraStatus? {
        if let glare = glareLine {
            return CameraStatus(text: glare, hint: nil, identifier: "camera.glare")
        }
        if let reason = waitLine {
            return CameraStatus(text: reason, hint: nil, identifier: "camera.wait")
        }
        if model.autoShutter && canShoot && model.live?.state == CaptureState.steadying {
            return CameraStatus(text: IOSCameraText.pageFound(CaptureObjects.kind(for: state.settings)), hint: nil,
                                identifier: "camera.found")
        }
        guard cardPrompt == nil, let line = taskLine else { return nil }
        return CameraStatus(text: line.prompt, hint: line.help, identifier: "camera.prompt")
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
        return IOSCameraText.waitReason(update.quality)
    }

    /// Whether a page held still waits, and the wait line as shown (nil while a message or the glare hint
    /// is shown in its place), for VoiceOver (`IOSWaitAnnouncer`).
    private var waitCue: IOSWaitCue {
        let steadying: Bool = model.autoShutter && model.live?.state == CaptureState.steadying
        let hidden: Bool = model.message != nil || glareLine != nil
        return IOSWaitCue(steadying: steadying, line: hidden ? nil : waitLine)
    }

    // MARK: Under the viewfinder

    @ViewBuilder
    private var lowerRow: some View {
        if showsDrawer {
            ScanDrawer(model: model, torch: model.hasTorch, group: $drawerGroup)
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
            !session.isImporting && session.canImport && !held
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

    /// The camera is live, no photo is being taken or read, and the queue can take a page.
    private var canShoot: Bool {
        model.canShoot && !importer.isImporting && importer.canImport
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
}

/// A line on a dark capsule over a picture.
struct StatusPill: View {
    let text: String
    let hint: String?

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.75)))
            .accessibilityHint(Text(hint ?? ""))
    }
}

/// The camera's live preview with the page's outline drawn over it, and over the preview, under the
/// outline, the picture with the saved page's filter (`look`, `LiveViewfinder`) when there is one. The
/// outline comes as shares of the sensor's frame (as the live frames are searched) and is placed with the
/// preview layer's own conversion (`layerPointConverted(fromCaptureDevicePoint:)`), which knows how the
/// preview is turned and where the whole frame sits in the view.
struct CameraPreview: UIViewRepresentable {
    let controller: IOSCameraController
    let outline: Quad?
    let steady: Bool
    let look: LiveLook?

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        controller.attach(previewLayer: view.previewLayer, viewfinder: view.viewfinder)
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.show(outline: outline, steady: steady)
        uiView.viewfinder?.show(look)
    }

    static func dismantleUIView(_ uiView: CameraPreviewView, coordinator: ()) {
        uiView.viewfinder?.show(nil)
    }
}

/// A view whose layer is the session's preview, with the filtered picture in a Metal layer over it and the
/// outline in a shape layer over that.
final class CameraPreviewView: UIView {
    private let outlineLayer = CAShapeLayer()
    let viewfinder: LiveViewfinder? = LiveViewfinder()
    private var outline: Quad?
    private var steady: Bool = false

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
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        layer.addSublayer(outlineLayer)
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

    func show(outline: Quad?, steady: Bool) {
        self.outline = outline
        self.steady = steady
        redraw()
    }

    private func redraw() {
        guard let quad = outline else {
            outlineLayer.path = nil
            return
        }
        let path = UIBezierPath()
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
        let color: UIColor = steady ? UIColor.systemGreen : UIColor.systemYellow
        outlineLayer.strokeColor = color.cgColor
        outlineLayer.fillColor = color.withAlphaComponent(0.15).cgColor
        outlineLayer.path = path.cgPath
    }
}
#endif
