#if os(macOS)
import AppKit
import LazyScanKit
import CoreGraphics
import SwiftUI

/// Manual crop correction for one detected photo: shows the whole bed scan with the
/// photo's (rotated) crop rectangle; corners drag to resize against the fixed opposite
/// corner, dragging inside moves the crop, and the handle above the top edge turns it.
/// "Apply" re-extracts the photo from the full-resolution source.
struct PhotoCropEditorView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    let photo: DetectedPhoto
    /// The sheet adds a new photo cut from `photo`'s scan, instead of correcting `photo`'s crop.
    let adds: Bool

    /// The crop being edited, in full-resolution source pixel coordinates.
    @State private var region: DetectedPhotoRegion
    /// Downsampled bed image for display.
    @State private var display: CGImage?
    @State private var dragMode: DragMode?
    @FocusState private var frameFocused: Bool

    init(photo: DetectedPhoto, adds: Bool = false) {
        self.photo = photo
        self.adds = adds
        _region = State(initialValue: photo.region)
    }

    private enum DragMode {
        case corner(Int, fixed: CGPoint)   // dragged corner index + the opposite corner (image coords)
        case move(originalCenter: CGPoint)
        case rotate(startAngle: Double, grab: Double)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleKey)
                        .font(.title3.bold())
                    Text("Drag corners to resize, or inside to move. Drag the top handle to rotate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Arrow keys move the crop, Shift and arrow keys resize it. Option and Left or Right rotate 0.1°, with Shift 1°.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(sizeCaption)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            GeometryReader { geo in
                let frame = fittedFrame(in: geo.size)
                ZStack {
                    Color(nsColor: .underPageBackgroundColor)
                    if let display {
                        Image(decorative: display, scale: 1)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    } else {
                        ProgressView()
                    }
                    cropOverlay(frame: frame, viewport: geo.size)
                }
                .contentShape(Rectangle())
                .gesture(cropDrag(frame: frame, viewport: geo.size))
                .environment(\.layoutDirection, .leftToRight)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($frameFocused)
            .onAppear { frameFocused = true }
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                let shift = press.modifiers.contains(.shift)
                let option = press.modifiers.contains(.option)
                if option, press.key == .leftArrow || press.key == .rightArrow {
                    let step = shift ? 1.0 : 0.1
                    turn(by: press.key == .rightArrow ? step : -step)
                } else {
                    nudge(press.key, resize: shift, bigger: option)
                }
                return .handled
            }
            .accessibilityLabel(Text("Crop frame"))
            .accessibilityValue(Text(sizeCaption))
            .accessibilityHint(Text("Arrow keys move the crop, Shift and arrow keys resize it. Option and Left or Right rotate 0.1°, with Shift 1°."))

            Divider()

            HStack {
                Button("Reset") { region = photo.region }
                    .disabled(region == photo.region)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(confirmKey) {
                    if adds {
                        state.appendReviewPhoto(region: region)
                    } else {
                        state.recropPhoto(id: photo.id, region: region)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 640, idealWidth: 820, minHeight: 520, idealHeight: 680)
        .task {
            if let source = state.photoSource(for: photo) {
                display = await Task.detached(priority: .userInitiated) {
                    editorDownsample(source, maxDimension: 2200)
                }.value
            }
        }
    }

    private var titleKey: LocalizedStringKey { adds ? "Add Photo" : "Adjust Crop" }

    private var confirmKey: LocalizedStringKey { adds ? "Add" : "Apply" }

    // MARK: - Geometry

    private var sourcePixelSize: CGSize {
        guard let source = state.photoSource(for: photo) else { return CGSize(width: 1, height: 1) }
        return CGSize(width: max(source.width, 1), height: max(source.height, 1))
    }

    private var sizeCaption: String {
        let pixels = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
        return String(localized: "\(region.size.width.formatted(pixels)) × \(region.size.height.formatted(pixels)) px  ·  \(angleCaption)°")
    }

    private var angleCaption: String {
        region.angleDegrees.formatted(.number.precision(.fractionLength(1)))
    }

    /// Aspect-fit frame of the bed image in the editor viewport.
    private func fittedFrame(in size: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: 20, dy: 20)
        let pixel = sourcePixelSize
        guard bounds.width > 0, bounds.height > 0 else { return bounds }
        let scale = min(bounds.width / pixel.width, bounds.height / pixel.height)
        let w = pixel.width * scale, h = pixel.height * scale
        return CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
    }

    private func viewPoint(_ imagePoint: CGPoint, frame: CGRect) -> CGPoint {
        let pixel = sourcePixelSize
        return CGPoint(x: frame.minX + imagePoint.x / pixel.width * frame.width,
                       y: frame.minY + imagePoint.y / pixel.height * frame.height)
    }

    private func imagePoint(_ viewPoint: CGPoint, frame: CGRect) -> CGPoint {
        let pixel = sourcePixelSize
        guard frame.width > 0, frame.height > 0 else { return .zero }
        return CGPoint(x: (viewPoint.x - frame.minX) / frame.width * pixel.width,
                       y: (viewPoint.y - frame.minY) / frame.height * pixel.height)
    }

    // MARK: - Overlay

    /// The rotate handle sits outside the middle of the top edge, along the edge's normal, and is
    /// pulled back into the viewport when the crop is near its top.
    private func rotateHandle(frame: CGRect, viewport: CGSize) -> (edge: CGPoint, handle: CGPoint) {
        let a = region.angleDegrees * .pi / 180
        let normal = CGPoint(x: sin(a), y: -cos(a))
        let half = region.size.height / 2
        let edge = viewPoint(CGPoint(x: region.center.x + normal.x * half, y: region.center.y + normal.y * half), frame: frame)
        let x = min(max(edge.x + normal.x * 26, 10), viewport.width - 10)
        let y = min(max(edge.y + normal.y * 26, 10), viewport.height - 10)
        return (edge, CGPoint(x: x, y: y))
    }

    private func cropOverlay(frame: CGRect, viewport: CGSize) -> some View {
        let corners = region.corners.map { viewPoint($0, frame: frame) }
        let knob = rotateHandle(frame: frame, viewport: viewport)
        return ZStack {
            Path { p in
                guard corners.count == 4 else { return }
                p.move(to: corners[0])
                p.addLine(to: corners[1])
                p.addLine(to: corners[2])
                p.addLine(to: corners[3])
                p.closeSubpath()
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2))

            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(Color.accentColor)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                    .frame(width: 13, height: 13)
                    .position(corners[index])
            }

            Path { p in
                p.move(to: knob.edge)
                p.addLine(to: knob.handle)
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5))

            Circle()
                .fill(Color.accentColor)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                .overlay(Image(systemName: "arrow.clockwise")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.white))
                .frame(width: 15, height: 15)
                .position(knob.handle)
                .accessibilityElement()
                .accessibilityLabel(Text("Rotate handle"))
                .accessibilityValue(Text(angleCaption))
                .accessibilityHint(Text("Option and Left or Right rotate the crop."))
                .accessibilityAddTraits(.isButton)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Keys

    /// One display pixel of the bed shown at about 800 points across; Shift changes the size instead of the place.
    private func nudge(_ key: KeyEquivalent, resize: Bool, bigger: Bool) {
        var dx = 0.0, dy = 0.0
        switch key {
        case .leftArrow: dx = -1
        case .rightArrow: dx = 1
        case .upArrow: dy = -1
        case .downArrow: dy = 1
        default: return
        }
        let pixel = sourcePixelSize
        var step = max(1, Double(pixel.width) / 800)
        if bigger { step *= 10 }
        if resize {
            let limit = Double(max(pixel.width, pixel.height))
            let width = min(max(Double(region.size.width) + dx * step, 24), limit)
            let height = min(max(Double(region.size.height) + dy * step, 24), limit)
            region.size = CGSize(width: width, height: height)
        } else {
            let x = min(max(Double(region.center.x) + dx * step, 0), Double(pixel.width))
            let y = min(max(Double(region.center.y) + dy * step, 0), Double(pixel.height))
            region.center = CGPoint(x: x, y: y)
        }
    }

    private func turn(by degrees: Double) {
        region = CropGeometry.rotated(region, toAngle: region.angleDegrees + degrees, page: sourcePixelSize)
    }

    // MARK: - Dragging

    private func cropDrag(frame: CGRect, viewport: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragMode == nil {
                    dragMode = beginDrag(at: value.startLocation, frame: frame, viewport: viewport)
                }
                guard let mode = dragMode else { return }
                switch mode {
                case .corner(_, let fixed):
                    resize(draggedTo: imagePoint(value.location, frame: frame), fixedCorner: fixed)
                case .move(let originalCenter):
                    let start = imagePoint(value.startLocation, frame: frame)
                    let now = imagePoint(value.location, frame: frame)
                    region.center = CGPoint(x: originalCenter.x + (now.x - start.x),
                                            y: originalCenter.y + (now.y - start.y))
                case .rotate(let startAngle, let grab):
                    let now = CropGeometry.angle(from: region.center, to: imagePoint(value.location, frame: frame))
                    var angle = startAngle + now - grab
                    if NSEvent.modifierFlags.contains(.shift) { angle = angle.rounded() }
                    region = CropGeometry.rotated(region, toAngle: angle, page: sourcePixelSize)
                }
            }
            .onEnded { _ in dragMode = nil }
    }

    private func beginDrag(at start: CGPoint, frame: CGRect, viewport: CGSize) -> DragMode? {
        let knob = rotateHandle(frame: frame, viewport: viewport).handle
        if hypot(knob.x - start.x, knob.y - start.y) <= 14 {
            let grab = CropGeometry.angle(from: region.center, to: imagePoint(start, frame: frame))
            return .rotate(startAngle: region.angleDegrees, grab: grab)
        }
        let corners = region.corners
        let viewCorners = corners.map { viewPoint($0, frame: frame) }
        for (index, corner) in viewCorners.enumerated() {
            if hypot(corner.x - start.x, corner.y - start.y) <= 14 {
                return .corner(index, fixed: corners[(index + 2) % 4])
            }
        }
        if pointInsidePolygon(imagePoint(start, frame: frame), corners) {
            return .move(originalCenter: region.center)
        }
        return nil
    }

    /// Resize keeping `fixedCorner` in place: express the dragged point in the region's
    /// rotated frame relative to the fixed corner; the absolute components are the new
    /// width/height and the center sits halfway along the diagonal.
    private func resize(draggedTo dragged: CGPoint, fixedCorner: CGPoint) {
        let a = region.angleDegrees * .pi / 180
        let ux = CGPoint(x: cos(a), y: sin(a))    // local +x axis in image coords
        let uy = CGPoint(x: -sin(a), y: cos(a))   // local +y axis
        let vx = dragged.x - fixedCorner.x
        let vy = dragged.y - fixedCorner.y
        var lx = vx * ux.x + vy * ux.y
        var ly = vx * uy.x + vy * uy.y
        let minSide: CGFloat = 24
        lx = lx < 0 ? min(lx, -minSide) : max(lx, minSide)
        ly = ly < 0 ? min(ly, -minSide) : max(ly, minSide)
        region.size = CGSize(width: abs(lx), height: abs(ly))
        region.center = CGPoint(x: fixedCorner.x + (ux.x * lx + uy.x * ly) / 2,
                                y: fixedCorner.y + (ux.y * lx + uy.y * ly) / 2)
    }
}

/// Angle math of the crop editor; the names follow `CropGeometry` in the Windows app.
enum CropGeometry {
    /// Angle in degrees that turns a region about `center` so the rotate handle (straight above
    /// the center in the region's own frame) points at `point`.
    static func angle(from center: CGPoint, to point: CGPoint) -> Double {
        atan2(Double(point.y - center.y), Double(point.x - center.x)) * 180 / .pi + 90
    }

    /// `region` turned about its center to `angle` (kept within -180...180), then moved back onto the page.
    static func rotated(_ region: DetectedPhotoRegion, toAngle angle: Double, page: CGSize) -> DetectedPhotoRegion {
        var turned = region
        var wrapped = angle.truncatingRemainder(dividingBy: 360)
        if wrapped > 180 { wrapped -= 360 }
        if wrapped < -180 { wrapped += 360 }
        turned.angleDegrees = wrapped
        keepOnPage(&turned, page: page)
        return turned
    }

    /// Moves `region`, without resizing it, so its bounding box lies on the page; a box larger
    /// than the page is centered on that axis.
    static func keepOnPage(_ region: inout DetectedPhotoRegion, page: CGSize) {
        let box = region.boundingBox
        let hx = box.width / 2, hy = box.height / 2
        let x = box.width >= page.width ? page.width / 2 : min(max(region.center.x, hx), page.width - hx)
        let y = box.height >= page.height ? page.height / 2 : min(max(region.center.y, hy), page.height - hy)
        region.center = CGPoint(x: x, y: y)
    }
}

// MARK: - File-private helpers

fileprivate func pointInsidePolygon(_ p: CGPoint, _ corners: [CGPoint]) -> Bool {
    guard corners.count >= 3 else { return false }
    var sign = 0.0
    for i in 0..<corners.count {
        let a = corners[i], b = corners[(i + 1) % corners.count]
        let cross = Double((b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x))
        if cross != 0 {
            if sign == 0 { sign = cross > 0 ? 1 : -1 }
            else if (cross > 0 ? 1.0 : -1.0) != sign { return false }
        }
    }
    return true
}

fileprivate func editorDownsample(_ image: CGImage, maxDimension: CGFloat) -> CGImage {
    let w = CGFloat(image.width), h = CGFloat(image.height)
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
