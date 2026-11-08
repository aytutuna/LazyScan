#if os(iOS)
import AVFoundation
import Foundation

/// Whether the camera can be used here, and if not, why (one short line).
public enum IOSCameraAvailability: Equatable, Sendable {
    /// It can be used (asking for the camera the first time, as iOS does).
    case available
    /// This device has no camera (the Simulator, an iPad without one).
    case noCamera
    /// The user turned camera access off for this app in Settings.
    case denied
    /// Camera access is not allowed here (Screen Time or a device profile).
    case restricted

    /// From whether a camera exists and the camera permission (`AVCaptureDevice.authorizationStatus(for: .video)`).
    public static func resolve(isSupported: Bool, authorization: AVAuthorizationStatus) -> IOSCameraAvailability {
        if !isSupported { return .noCamera }
        switch authorization {
        case .denied: return .denied
        case .restricted: return .restricted
        default: return .available
        }
    }

    /// Our own camera (`CameraScreen`) on this device, now: a camera to capture with
    /// (`IOSCameraLens.hasCamera`; none in the Simulator) and the camera permission.
    @MainActor
    public static var ownCamera: IOSCameraAvailability {
        resolve(isSupported: IOSCameraLens.hasCamera, authorization: AVCaptureDevice.authorizationStatus(for: .video))
    }

    public var isAvailable: Bool { self == .available }

    /// Why the camera cannot be used: the line under the dimmed Camera button; nil when it can.
    public var reason: String? {
        switch self {
        case .available: return nil
        case .noCamera: return String(localized: "No camera here")
        case .denied: return String(localized: "Camera access is off")
        case .restricted: return String(localized: "Camera not allowed")
        }
    }

    /// Settings can turn camera access back on.
    public var opensSettings: Bool { self == .denied }
}
#endif
