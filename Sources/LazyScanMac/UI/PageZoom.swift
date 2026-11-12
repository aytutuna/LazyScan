#if os(macOS)
import AppKit
import CoreGraphics
import SwiftUI

/// How the canvas shows the viewed page: fitted to the window, or at a scale and moved off center.
struct PageZoom: Equatable {
    /// Points per image pixel; nil fits the page into the canvas.
    var scale: CGFloat?
    /// Where the page's center lies relative to the canvas's center.
    var pan: CGSize = .zero
}

/// The numbers behind `PageZoom` for one page in one canvas. Anchors are points relative to the canvas's center.
struct PageZoomGeometry {
    /// The page's true size, not the downsampled copy.
    let pixels: CGSize
    let viewport: CGSize
    /// Screen pixels per point, so that 100% is one image pixel per screen pixel.
    let displayScale: CGFloat

    static let maxPercent: CGFloat = 5
    static let step: CGFloat = 1.5

    var fitScale: CGFloat {
        let box = canvasBounds(for: viewport)
        guard pixels.width > 0, pixels.height > 0 else { return 1 }
        return min(box.width / pixels.width, box.height / pixels.height)
    }

    var actualScale: CGFloat { 1 / displayScale }

    /// A page smaller than the canvas is fitted larger than its actual size; zooming out may reach that size.
    var lowestScale: CGFloat { min(fitScale, actualScale) }

    var highestScale: CGFloat { max(PageZoomGeometry.maxPercent / displayScale, fitScale) }

    func scale(of zoom: PageZoom) -> CGFloat { zoom.scale ?? fitScale }

    /// The zoom as the readout shows it: 1 is 100%.
    func percent(of zoom: PageZoom) -> CGFloat { scale(of: zoom) * displayScale }

    func isFit(_ zoom: PageZoom) -> Bool { zoom.scale == nil }

    func isActualSize(_ zoom: PageZoom) -> Bool { abs(percent(of: zoom) - 1) < 0.005 }

    func canZoomOut(_ zoom: PageZoom) -> Bool { scale(of: zoom) > lowestScale * 1.001 }

    func canZoomIn(_ zoom: PageZoom) -> Bool { scale(of: zoom) < highestScale * 0.999 }

    /// The pan with no edge of a page larger than the canvas pulled inside it; a smaller page stays centered.
    func clampedPan(_ pan: CGSize, scale: CGFloat) -> CGSize {
        let reachX = max(0, (pixels.width * scale - viewport.width) / 2)
        let reachY = max(0, (pixels.height * scale - viewport.height) / 2)
        return CGSize(width: min(max(pan.width, -reachX), reachX),
                      height: min(max(pan.height, -reachY), reachY))
    }

    /// The zoom at `target`, keeping the page point under `anchor` where it is.
    func zoomed(_ zoom: PageZoom, to target: CGFloat, about anchor: CGPoint = .zero) -> PageZoom {
        let old = scale(of: zoom)
        let new = min(max(target, lowestScale), highestScale)
        if abs(new - fitScale) < fitScale * 0.001 { return PageZoom() }
        let pan = clampedPan(zoom.pan, scale: old)
        let pageX = (anchor.x - pan.width) / old
        let pageY = (anchor.y - pan.height) / old
        let moved = CGSize(width: anchor.x - pageX * new, height: anchor.y - pageY * new)
        return PageZoom(scale: new, pan: clampedPan(moved, scale: new))
    }

    func zoomedIn(_ zoom: PageZoom) -> PageZoom { zoomed(zoom, to: scale(of: zoom) * PageZoomGeometry.step) }

    func zoomedOut(_ zoom: PageZoom) -> PageZoom { zoomed(zoom, to: scale(of: zoom) / PageZoomGeometry.step) }

    func actualSize(_ zoom: PageZoom, about anchor: CGPoint = .zero) -> PageZoom {
        zoomed(zoom, to: actualScale, about: anchor)
    }

    /// A double-click: back to Fit from any zoom, else to 100% at the pointer.
    func toggled(_ zoom: PageZoom, about anchor: CGPoint) -> PageZoom {
        isFit(zoom) ? actualSize(zoom, about: anchor) : PageZoom()
    }

    func panned(_ zoom: PageZoom, by delta: CGSize) -> PageZoom {
        guard let scale = zoom.scale else { return zoom }
        let pan = clampedPan(zoom.pan, scale: scale)
        let moved = CGSize(width: pan.width + delta.width, height: pan.height + delta.height)
        return PageZoom(scale: scale, pan: clampedPan(moved, scale: scale))
    }
}

/// The page view's zoom, offered to the View menu while the canvas shows a page.
struct PageZoomActions {
    var fit: () -> Void
    var actualSize: () -> Void
    var zoomIn: () -> Void
    var zoomOut: () -> Void
}

private struct PageZoomActionsKey: FocusedValueKey {
    typealias Value = PageZoomActions
}

extension FocusedValues {
    var pageZoom: PageZoomActions? {
        get { self[PageZoomActionsKey.self] }
        set { self[PageZoomActionsKey.self] = newValue }
    }
}

/// View > Zoom to Fit, Actual Size, Zoom In and Zoom Out, on while the canvas shows a page.
struct PageZoomCommands: Commands {
    @FocusedValue(\.pageZoom) private var zoom

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Zoom to Fit") { zoom?.fit() }
                .keyboardShortcut("9")
                .disabled(zoom == nil)
            Button("Actual Size") { zoom?.actualSize() }
                .keyboardShortcut("0")
                .disabled(zoom == nil)
            Button("Zoom In") { zoom?.zoomIn() }
                .keyboardShortcut("=")
                .disabled(zoom == nil)
            Button("Zoom Out") { zoom?.zoomOut() }
                .keyboardShortcut("-")
                .disabled(zoom == nil)
        }
    }
}

/// Reports scroll-wheel and trackpad scrolling over its area without taking clicks. Plain scrolling pans, and
/// scrolling with Option held zooms, which SwiftUI has no gesture for.
struct PageScrollCatcher: NSViewRepresentable {
    /// The scroll's distance, where it happened (from the top left) and whether Option was held.
    var onScroll: (CGSize, CGPoint, Bool) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onScroll = onScroll
    }

    final class CatcherView: NSView {
        var onScroll: ((CGSize, CGPoint, Bool) -> Void)?
        private var monitor: Any?

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(point) else { return event }
                // A wheel without a trackpad's fine deltas moves in lines.
                let unit: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
                let delta = CGSize(width: event.scrollingDeltaX * unit, height: event.scrollingDeltaY * unit)
                self.onScroll?(delta, point, event.modifierFlags.contains(.option))
                return nil
            }
        }
    }
}
#endif
