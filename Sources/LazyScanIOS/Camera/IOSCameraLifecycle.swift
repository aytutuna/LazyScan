#if os(iOS)
import AVFoundation
import LazyScanKit
import Foundation

/// Why the camera was taken from us for a while (`AVCaptureSession` interruptions: a phone call,
/// another app using the camera, the iPad showing two apps side by side, the device under strain).
public enum IOSCameraInterruption: Equatable, Sendable {
    /// Another app (a call, FaceTime) has the camera.
    case inUse
    /// The device is too warm or under strain (system pressure).
    case tooWarm
    /// The iPad shows other apps beside this one (Split View, Slide Over, Stage Manager).
    case multitasking
    /// Anything else.
    case other

    /// The interruption a session reports.
    public static func from(_ reason: AVCaptureSession.InterruptionReason) -> IOSCameraInterruption {
        switch reason {
        case .videoDeviceInUseByAnotherClient: return .inUse
        case .videoDeviceNotAvailableDueToSystemPressure: return .tooWarm
        case .videoDeviceNotAvailableWithMultipleForegroundApps: return .multitasking
        default: return .other
        }
    }

    /// The camera screen's one line while it lasts.
    public var reason: String {
        switch self {
        case .inUse: return IOSCameraText.inUse
        case .tooWarm: return IOSCameraText.tooWarm
        case .multitasking: return IOSCameraText.needsFullScreen
        case .other: return IOSCameraText.paused
        }
    }
}

/// What happens to the camera screen and the app that decides whether the camera may run.
public enum IOSCameraEvent: Equatable, Sendable {
    /// The camera screen is shown, or gone.
    case shown
    case hidden
    /// The app went to the background, or is active (again: back from the background, or after a moment
    /// inactive in the front).
    case background
    case foreground
    /// The camera is allowed and set up (true), or not (false).
    case ready(Bool)
    /// The device's thermal state changed (`ProcessInfo.thermalState`).
    case thermal(ProcessInfo.ThermalState)
    /// The session was interrupted (the system stopped it), or the interruption ended (the system
    /// started it again).
    case interrupted(IOSCameraInterruption)
    case interruptionEnded
    /// A photo taken is in the corner editor, or the editor closed.
    case reviewStarted
    case reviewEnded
    /// The session stopped with an error (media services were reset, say).
    case runtimeError
}

/// What the camera screen does with the session after an event.
public enum IOSCameraCommand: Equatable, Sendable {
    /// Leave the session as it is.
    case keep
    case start
    case stop
}

/// When our camera runs: only while its screen is shown, the app is in the front, the camera is allowed
/// and set up, the device is not too warm (thermal state `.serious` or worse stops it) and no photo is in
/// the corner editor. It starts again as soon as all of that holds. An interruption (a call, Control
/// Center, another app using the camera) is the system stopping the session: it is not stopped again
/// here, so AVFoundation starts it again by itself when the interruption ends; meanwhile the camera is
/// not live (`isLive`: no frames, no shutter) and the screen says why. Coming back from the background or
/// to the screen forgets an interruption whose end was not reported; the app made active again without
/// having gone to the background (`.foreground` while in the front) does not. After a session error it is started again,
/// up to `maxRestarts` times while the screen is shown. A value: `handle` answers what to do with the
/// session.
public struct IOSCameraLifecycle: Equatable, Sendable {
    /// Restarts after session errors while the screen is shown, before it stays stopped.
    public static let maxRestarts: Int = 3

    public private(set) var isShown: Bool = false
    public private(set) var isInForeground: Bool = true
    public private(set) var isReady: Bool = false
    public private(set) var isTooWarm: Bool = false
    public private(set) var interruption: IOSCameraInterruption?
    public private(set) var isReviewing: Bool = false
    /// The session runs (the last command was start).
    public private(set) var isRunning: Bool = false
    /// The session stopped with errors more often than `maxRestarts`.
    public private(set) var hasFailed: Bool = false
    private var restarts: Int = 0

    public init() {}

    /// Everything allows the camera to run now (an interruption aside, which the system handles).
    public var shouldRun: Bool {
        isShown && isInForeground && isReady && !isTooWarm && !isReviewing && !hasFailed
    }

    /// The camera runs and is not interrupted: frames come and a photo can be taken.
    public var isLive: Bool {
        isRunning && interruption == nil
    }

    /// Takes `event` in and answers what to do with the session.
    public mutating func handle(_ event: IOSCameraEvent) -> IOSCameraCommand {
        switch event {
        case .shown:
            isShown = true
            interruption = nil
            restarts = 0
            hasFailed = false
        case .hidden:
            isShown = false
        case .background:
            isInForeground = false
        case .foreground:
            // Only back from the background: the app made active again without leaving the front (Control
            // Center pulled down and closed) leaves an interruption still in effect as it is.
            if !isInForeground {
                interruption = nil
            }
            isInForeground = true
        case .ready(let ready):
            isReady = ready
        case .thermal(let state):
            isTooWarm = !IOSCameraLifecycle.thermalAllows(state)
        case .interrupted(let why):
            interruption = why
        case .interruptionEnded:
            interruption = nil
        case .reviewStarted:
            isReviewing = true
        case .reviewEnded:
            isReviewing = false
        case .runtimeError:
            // The session stopped by itself: started again below while it may run.
            isRunning = false
            restarts += 1
            if restarts > IOSCameraLifecycle.maxRestarts {
                hasFailed = true
            }
        }
        return settle()
    }

    /// The camera screen's one line while the camera waits (too warm, interrupted, failed); nil while it
    /// runs or waits for nothing the user should know about.
    public var pauseReason: String? {
        if hasFailed { return IOSCameraText.notStarted }
        if isTooWarm { return IOSCameraText.tooWarm }
        if let why = interruption { return why.reason }
        return nil
    }

    /// The camera may run at this thermal state: nominal or fair, not serious or critical.
    public static func thermalAllows(_ state: ProcessInfo.ThermalState) -> Bool {
        state.rawValue < ProcessInfo.ThermalState.serious.rawValue
    }

    private mutating func settle() -> IOSCameraCommand {
        let run: Bool = shouldRun
        if run && !isRunning {
            isRunning = true
            return .start
        }
        if !run && isRunning {
            isRunning = false
            return .stop
        }
        return .keep
    }
}

/// The camera screen's short texts.
public enum IOSCameraText {
    public static var title: String { String(localized: "Camera") }
    public static var doneLabel: String { String(localized: "Done") }
    public static var shutterLabel: String { String(localized: "Take photo") }
    /// The automatic shutter's toggle.
    public static var autoLabel: String { String(localized: "Auto") }
    public static var autoHint: String { String(localized: "Takes each page once it holds still") }
    /// The automatic shutter's switch in the options drawer.
    public static var autoShutterLabel: String { String(localized: "Auto shutter") }
    /// Why Separate documents or Both sides is dimmed while the other is on: one task holds either.
    public static var notWithBothSides: String { String(localized: "Not with Both sides") }
    public static var notWithSeparate: String { String(localized: "Not with Separate documents") }
    /// The options drawer's Items in frame (`IOSItemsInFrame`) and the line under it for `kind`. Photo has no
    /// Several: its Auto cuts out every print found already.
    public static var itemsInFrameLabel: String { String(localized: "Items in frame") }
    public static func itemsInFrameHint(_ kind: IOSScanKind) -> String {
        if kind == .photos {
            return String(localized: "Auto cuts out each print it sees. Pick One to keep only the largest.")
        }
        return String(localized: "Auto splits the shot when it sees more than one page or photo. Pick One for a page with slips on it.")
    }
    /// The chevron that swaps the kinds for the options drawer.
    public static var showOptions: String { String(localized: "Show options") }
    public static var hideOptions: String { String(localized: "Hide options") }
    /// Camera mode's button to printer mode, and its hint.
    public static var printerLabel: String { String(localized: "Scanner") }
    public static var printerHint: String { String(localized: "Scans with a scanner instead of the camera") }
    /// Printer mode's button back to the camera.
    public static var cameraModeHint: String { String(localized: "Takes the pages with the camera") }
    /// The scan screen's Camera button, whether Auto is on or off.
    public static var cameraHint: String { String(localized: "Opens the camera to take pages") }
    /// A toggle's spoken value (Auto, the flash).
    public static var onValue: String { String(localized: "On") }
    public static var offValue: String { String(localized: "Off") }
    /// Why a page held still is not taken yet (`CaptureQuality`), and what may help (`LiveQuadUpdate`).
    public static var notSharp: String { String(localized: "Not sharp yet") }
    public static var tooDark: String { String(localized: "Too dark") }
    /// The same line when the light is off and can be turned on by tapping it.
    public static var tooDarkTapForLight: String { String(localized: "Too dark. Tap for light") }
    public static var tooDarkHint: String { String(localized: "Turns the light on") }
    public static var tapShutter: String { String(localized: "Tap the shutter") }
    public static var moveCloser: String { String(localized: "Move closer") }
    public static var fitWholePage: String { String(localized: "Fit the whole page") }
    public static var fitWholeCard: String { String(localized: "Fit the whole card") }
    /// The camera's light, a torch, by the name people know it by (the drawer's group and its switch).
    public static var flashLabel: String { String(localized: "Flash") }
    public static var settingsLabel: String { String(localized: "Settings") }
    /// The last page and the count: back to the page strip (both tabs).
    public static var pagesHint: String { String(localized: "Shows the pages taken") }
    /// The card before the first camera permission prompt (`IOSShell.cameraOnOpen`).
    public static var introLine: String { String(localized: "Lazy Scan scans with the camera.") }
    public static var introHelp: String { String(localized: "iOS asks once for access. Photos and Files work without it.") }
    public static var continueLabel: String { String(localized: "Continue") }
    public static var useScannerLabel: String { String(localized: "Use a scanner") }
    public static var useScannerHint: String { String(localized: "Opens the scanner tab without asking for the camera") }
    public static var notNowLabel: String { String(localized: "Not now") }
    public static var notNowHint: String { String(localized: "Skips the camera for now") }
    /// The viewfinder after Not now, until the camera is allowed.
    public static var notOnYet: String { String(localized: "Camera is not on yet") }
    public static var allowLabel: String { String(localized: "Allow camera") }
    public static var allowHint: String { String(localized: "Asks iOS for camera access") }
    /// The session could not be set up, or stopped with errors.
    public static var notStarted: String { String(localized: "Camera did not start") }
    public static var tooWarm: String { String(localized: "Paused: too warm") }
    public static var inUse: String { String(localized: "Camera in use") }
    public static var needsFullScreen: String { String(localized: "Needs full screen") }
    public static var paused: String { String(localized: "Camera paused") }
    public static var photoFailed: String { String(localized: "Photo not taken") }
    /// The pages in the queue: "1 page", "3 pages".
    public static func pageCount(_ count: Int) -> String {
        L10n.plural(count, one: "{0} page", other: "{0} pages")
    }

    /// The top bar's button that steps through the photo sizes, for VoiceOver; its value is the size.
    public static var resolutionLabel: String { String(localized: "Camera resolution") }
    /// The preview's zoom for VoiceOver (its value is `zoomLabel`).
    public static var zoomLabel: String { String(localized: "Camera zoom") }

    /// A zoom as the readout shows it, relative to the wide lens: "1.0x", "2.4x", "10x".
    public static func zoomLabel(_ zoom: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let digits: Int = zoom < 10 ? 1 : 0
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        let number: String = formatter.string(from: NSNumber(value: zoom)) ?? String(Int(zoom))
        return String(localized: "\(number)x")
    }
    /// The alert over the camera when a size picked there `warns`.
    public static var memoryTitle: String { String(localized: "Not much memory for this size") }

    /// A photo size as the camera's button and Settings show it: "24 MP".
    public static func sizeLabel(_ size: IOSPhotoSize) -> String {
        String(localized: "\(IOSCameraLens.megapixels(size)) MP")
    }

    /// "Use 24 MP", the memory alert's buttons.
    public static func useLabel(_ size: IOSPhotoSize) -> String {
        String(localized: "Use \(sizeLabel(size))")
    }

    /// Why a page from a photo of `size` may not fit in this phone's memory (`IOSCameraLens.warns`), with
    /// the largest of `choices` that would (`saferSize`); nil when it fits. The memory in whole gigabytes,
    /// the page's in hundreds of megabytes.
    public static func memoryWarning(_ size: IOSPhotoSize, among choices: [IOSPhotoSize], physicalMemory: UInt64) -> String? {
        guard IOSCameraLens.warns(size, physicalMemory: physicalMemory) else { return nil }
        let memory: String = ByteCountFormatter.string(fromByteCount: Int64(IOSCameraLens.gigabytes(physicalMemory)) * 1_000_000_000, countStyle: .decimal)
        let page: String = ByteCountFormatter.string(fromByteCount: Int64((Double(IOSCameraLens.processingBytes(size)) / 100_000_000).rounded()) * 100_000_000, countStyle: .decimal)
        var text: String = String(localized: "This iPhone has \(memory) of memory. At \(sizeLabel(size)), each page needs about \(page) while it is processed, so the app may close.")
        if let safer = IOSCameraLens.saferSize(among: choices, physicalMemory: physicalMemory) {
            text += " " + String(localized: "\(sizeLabel(safer)) is safer.")
        }
        return text
    }

    /// What the shutter does with its photo for `kind`, for VoiceOver.
    public static func shutterHint(_ kind: CaptureKind) -> String {
        switch kind {
        case .document:
            return String(localized: "The page is found again in the photo")
        case .receipt:
            return String(localized: "The receipts are found in the photo")
        case .photo:
            return String(localized: "The photos are found in the shot")
        case .idCard:
            return String(localized: "Takes the side of the card in the frame")
        }
    }

    /// The status line while the page, card, photo or receipt of `kind` holds still for the automatic shutter.
    public static func pageFound(_ kind: CaptureKind) -> String {
        switch kind {
        case .document:
            return String(localized: "Page found \u{00B7} hold still")
        case .receipt:
            return String(localized: "Receipt found \u{00B7} hold still")
        case .photo:
            return String(localized: "Photo found \u{00B7} hold still")
        case .idCard:
            return String(localized: "Card found \u{00B7} hold still")
        }
    }

    /// The line under the outline while a page held still waits (`CaptureQuality`): "Not sharp yet" (once it
    /// has lasted, "Tap the shutter") or "Too dark"; nil for a good frame.
    public static func waitReason(_ quality: CaptureQuality, suggestsShutter: Bool = false) -> String? {
        switch quality {
        case .good:
            return nil
        case .blurry:
            return suggestsShutter ? tapShutter : notSharp
        case .dark:
            return tooDark
        }
    }

    /// The line while the page found sits badly in the frame: "Move closer" or "Fit the whole page" (the
    /// card, under the ID card's guide); nil for a page that sits well.
    public static func placementHint(_ placement: CapturePlacement, kind: CaptureKind) -> String? {
        switch placement {
        case .fine:
            return nil
        case .far:
            return moveCloser
        case .cutOff:
            return kind == .idCard ? fitWholeCard : fitWholePage
        }
    }
}

/// What the camera screen shows of the automatic shutter's wait, for VoiceOver: whether a page held still
/// waits (Auto on, `CaptureState.steadying`) and the wait line as shown (nil without one, or while the
/// import's progress or a message is shown in its place).
public struct IOSWaitCue: Equatable, Sendable {
    public var steadying: Bool
    public var line: String?

    public init(steadying: Bool, line: String?) {
        self.steadying = steadying
        self.line = line
    }
}

/// When VoiceOver says the wait line: once per wait. The line follows each live frame, so near the limits
/// of sharpness or light it comes and goes from frame to frame while the page holds still; it is said the
/// first time it is shown in a wait and not again until the page is no longer held still (taken, moved,
/// lost, or Auto turned off). A line covered by another is not said; it is said when it is first shown.
public struct IOSWaitAnnouncer: Equatable, Sendable {
    /// Whether the line was said in this wait.
    public private(set) var hasAnnounced: Bool = false

    public init() {}

    /// The line to say for `cue`, the screen's latest, if any.
    public mutating func next(_ cue: IOSWaitCue) -> String? {
        guard cue.steadying else {
            hasAnnounced = false
            return nil
        }
        guard !hasAnnounced, let line = cue.line else { return nil }
        hasAnnounced = true
        return line
    }
}
#endif
