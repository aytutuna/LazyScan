#if os(iOS)
import AVFoundation
import CoreImage
import LazyScanKit
import Metal
import QuartzCore
import UIKit

/// The filtered picture over the camera's preview: a Metal layer laid exactly over the video, drawing each
/// frame through `LiveFilter` (Core Image on the GPU). `show(_:)` says what to draw (from the main thread);
/// `draw(_:)` takes each frame, `measuresDue(_:)` and `measure(_:atMs:)` the small copies the paper is
/// measured on, all on the frame queue. The settings and measures are read under a lock, so a frame never
/// waits for the main actor. Nothing is drawn, and the layer stays hidden, while there is no look, the app is
/// not active, or the first measure of a new look is not in yet; the preview underneath shows meanwhile. A
/// frame is dropped, not queued, while the one before is still being drawn.
final class LiveViewfinder: @unchecked Sendable {
    /// A new measure comes at most this often.
    static let measureGapMs: Double = 180

    let layer: CAMetalLayer = CAMetalLayer()
    private let queue: MTLCommandQueue
    private let context: CIContext
    private let measureQueue: DispatchQueue = DispatchQueue(label: "LazyScan.camera.look", qos: .utility)
    private let drawing: DispatchSemaphore = DispatchSemaphore(value: 1)
    private let lock: NSLock = NSLock()
    private var look: LiveLook?
    private var stats: LiveStats?
    private var turn: Int = 90
    private var mirrored: Bool = false
    private var revealed: Bool = false
    private var inactive: Bool = false
    private var measuring: Bool = false
    private var lastMeasuredMs: Double?
    private var observers: [NSObjectProtocol] = []
    private weak var preview: AVCaptureVideoPreviewLayer?

    /// Nil where there is no Metal device: the plain preview is all there is.
    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let commands = device.makeCommandQueue() else { return nil }
        queue = commands
        context = CIContext(mtlCommandQueue: commands, options: [
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull(),
            .cacheIntermediates: false,
        ])
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        // Core Image writes into the drawable's texture.
        layer.framebufferOnly = false
        layer.isOpaque = true
        layer.isHidden = true
        inactive = UIApplication.shared.applicationState != .active
        let center: NotificationCenter = NotificationCenter.default
        let resign: NSObjectProtocol = center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil,
                                                          queue: nil) { [weak self] (_: Notification) -> Void in
            self?.setInactive(true)
        }
        let become: NSObjectProtocol = center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                                          queue: nil) { [weak self] (_: Notification) -> Void in
            self?.setInactive(false)
        }
        observers = [resign, become]
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: From the main thread

    /// What to draw from now on; nil hides the layer and forgets the measure.
    func show(_ next: LiveLook?) {
        lock.lock()
        if next == look {
            lock.unlock()
            return
        }
        if next == nil || look == nil || (next?.mode == .photo) != (look?.mode == .photo) {
            stats = nil
            lastMeasuredMs = nil
            revealed = false
        }
        look = next
        lock.unlock()
        if next == nil {
            layer.isHidden = true
        }
    }

    /// The preview's turn (clockwise degrees, a multiple of 90) and whether it is mirrored; the layer is
    /// laid over the video again, since the video's rectangle follows the turn.
    func setTurn(_ angle: CGFloat, mirrored flipped: Bool, over preview: AVCaptureVideoPreviewLayer) {
        let quarters: Int = Int((Double(angle) / 90).rounded())
        lock.lock()
        turn = ((quarters % 4 + 4) % 4) * 90
        mirrored = flipped
        lock.unlock()
        self.preview = preview
        updateFrame()
    }

    /// The layer over the video as the preview shows it (the whole frame, fitted).
    func updateFrame() {
        guard let shown = preview else { return }
        var rect: CGRect = shown.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        if rect.isNull || rect.isInfinite || rect.width < 1 || rect.height < 1 {
            rect = shown.bounds
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = rect
        layer.drawableSize = CGSize(width: (rect.width * layer.contentsScale).rounded(),
                                    height: (rect.height * layer.contentsScale).rounded())
        CATransaction.commit()
    }

    private func setInactive(_ off: Bool) {
        lock.lock()
        inactive = off
        lock.unlock()
    }

    // MARK: From the frame queue

    /// Draws `buffer` as the look says; nothing when there is none, the measure is not in, the previous
    /// frame is still being drawn or no drawable is free.
    func draw(_ buffer: CVPixelBuffer) {
        lock.lock()
        let wanted: LiveLook? = inactive ? nil : look
        let measured: LiveStats? = stats
        let quarter: Int = turn
        let flipped: Bool = mirrored
        lock.unlock()
        guard let current = wanted, current.mode == nil || measured != nil else { return }
        guard drawing.wait(timeout: .now()) == .success else { return }
        guard let drawable = layer.nextDrawable(), let commands = queue.makeCommandBuffer() else {
            drawing.signal()
            return
        }
        let size: CGSize = CGSize(width: drawable.texture.width, height: drawable.texture.height)
        var image: CIImage = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
        image = LiveFilter.apply(image, look: current, stats: measured)
        image = LiveViewfinder.placed(image, turn: quarter, mirrored: flipped, in: size)
        let destination: CIRenderDestination = CIRenderDestination(mtlTexture: drawable.texture, commandBuffer: commands)
        destination.colorSpace = nil
        destination.isFlipped = true
        do {
            _ = try context.startTask(toRender: image, to: destination)
        } catch {
            drawing.signal()
            return
        }
        let finished: DispatchSemaphore = drawing
        commands.addCompletedHandler { (_: MTLCommandBuffer) -> Void in
            finished.signal()
        }
        drawable.addPresentedHandler { [weak self] (_: MTLDrawable) -> Void in
            self?.reveal()
        }
        commands.present(drawable)
        commands.commit()
    }

    /// The frame turned upright as the preview shows it (and mirrored), scaled to fill `size`.
    static func placed(_ image: CIImage, turn: Int, mirrored: Bool, in size: CGSize) -> CIImage {
        var orientation: CGImagePropertyOrientation = .up
        switch turn {
        case 90: orientation = .right
        case 180: orientation = .down
        case 270: orientation = .left
        default: break
        }
        var upright: CIImage = image.oriented(orientation)
        let origin: CGRect = upright.extent
        upright = upright.transformed(by: CGAffineTransform(translationX: -origin.minX, y: -origin.minY))
        if mirrored {
            upright = upright.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: origin.width, ty: 0))
        }
        let fit: CGAffineTransform = CGAffineTransform(scaleX: size.width / origin.width, y: size.height / origin.height)
        return upright.transformed(by: fit).cropped(to: CGRect(origin: CGPoint.zero, size: size))
    }

    /// The layer is shown once it has a frame of the current look, so an old picture is never seen.
    private func reveal() {
        lock.lock()
        let first: Bool = !revealed && look != nil
        if first {
            revealed = true
        }
        lock.unlock()
        guard first else { return }
        DispatchQueue.main.async {
            self.lock.lock()
            let still: Bool = self.look != nil
            self.lock.unlock()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.layer.isHidden = !still
            CATransaction.commit()
        }
    }

    /// Whether a new measure is due at `ms` (the frame's time on the capture clock) and none is under way.
    func measuresDue(_ ms: Double) -> Bool {
        lock.lock()
        defer {
            lock.unlock()
        }
        guard !inactive, let current = look, current.mode != nil, !measuring else { return false }
        if let last = lastMeasuredMs, ms >= last, ms - last < LiveViewfinder.measureGapMs {
            return false
        }
        return true
    }

    /// Measures the small copy `image` of a frame off the frame queue and keeps the result for the frames
    /// that follow.
    func measure(_ image: RgbaImage, atMs ms: Double) {
        lock.lock()
        guard let mode = look?.mode, !measuring else {
            lock.unlock()
            return
        }
        measuring = true
        lastMeasuredMs = ms
        let before: LiveStats? = stats
        lock.unlock()
        measureQueue.async {
            let fresh: LiveStats = LiveStats.measure(image, mode: mode, after: before)
            self.lock.lock()
            if self.look?.mode != nil {
                self.stats = fresh
            }
            self.measuring = false
            self.lock.unlock()
        }
    }
}
#endif
