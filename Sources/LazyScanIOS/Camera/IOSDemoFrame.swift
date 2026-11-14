#if os(iOS)
import CoreGraphics
import LazyScanKit
import SwiftUI
import UIKit

/// What the viewfinder shows under `-demoCameraFrame` where the Simulator has no camera: one drawn frame of
/// a page on a dark table, with the outline the live page search (`LiveQuadTracker.detect`) finds in it, so
/// the screenshot run can picture the camera screen. Nothing else uses it.
enum IOSDemoFrame {
    static let isOn: Bool = ProcessInfo.processInfo.arguments.contains(IOSLaunchOptions.demoCameraFrameArgument)

    static let width: Int = 360
    static let height: Int = 480
    private static let cosine: Double = 0.99619469809174555
    private static let sine: Double = 0.087155742747658166
    private static let halfWidth: Double = 130
    private static let halfHeight: Double = 180

    static let frame: RgbaImage = drawn()

    /// The page the search finds in `frame`, as shares of it; empty when it finds none.
    static let outline: [CGPoint] = found()

    static let picture: UIImage = {
        guard let image = frame.makeCGImage() else { return UIImage() }
        return UIImage(cgImage: image)
    }()

    private static func found() -> [CGPoint] {
        let detection: PhotoDocumentDetection = LiveQuadTracker.detect(frame, hint: nil)
        guard let quad = detection.quad else { return [] }
        return LiveQuadTracker.normalized(quad, width: width, height: height).corners
    }

    private static func sample(_ px: Double, _ py: Double) -> (Int, Int, Int) {
        let dx: Double = px - Double(width) / 2
        let dy: Double = py - Double(height) / 2
        let u: Double = dx * cosine + dy * sine
        let v: Double = -dx * sine + dy * cosine
        if !(abs(u) < halfWidth && abs(v) < halfHeight) { return (38, 40, 46) }
        let top: Double = v + halfHeight
        let left: Double = u + halfWidth
        let inside: Bool = left >= 24 && left < 2 * halfWidth - 24
        if top >= 14 && top < 30 && inside { return (60, 70, 110) }
        if top >= 44 && top < 330 && inside && (Int(top) - 44) % 20 < 7 { return (70, 70, 78) }
        return (238, 236, 230)
    }

    private static func drawn() -> RgbaImage {
        var pixels: [UInt8] = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var red: Int = 0
                var green: Int = 0
                var blue: Int = 0
                for k in 0..<4 {
                    let color: (Int, Int, Int) = sample(Double(x) + 0.25 + 0.5 * Double(k & 1),
                                                        Double(y) + 0.25 + 0.5 * Double(k >> 1))
                    red += color.0
                    green += color.1
                    blue += color.2
                }
                let o: Int = (y * width + x) * 4
                pixels[o] = UInt8((red + 2) / 4)
                pixels[o + 1] = UInt8((green + 2) / 4)
                pixels[o + 2] = UInt8((blue + 2) / 4)
            }
        }
        return RgbaImage(width: width, height: height, pixels: pixels)
    }
}

/// The demo frame fitted in the viewfinder with its outline in the colour of a page that holds still.
struct DemoCameraFrame: View {
    var body: some View {
        Image(uiImage: IOSDemoFrame.picture)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { (proxy: GeometryProxy) in
                    outline(in: proxy.size)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                }
            }
            .accessibilityHidden(true)
    }

    private func outline(in size: CGSize) -> Path {
        var path: Path = Path()
        let corners: [CGPoint] = IOSDemoFrame.outline
        guard let first = corners.first else { return path }
        path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
        for corner in corners.dropFirst() {
            path.addLine(to: CGPoint(x: corner.x * size.width, y: corner.y * size.height))
        }
        path.closeSubpath()
        return path
    }
}
#endif
