import CoreGraphics
import Foundation

public enum PageMarkRenderer {
    /// `image`, the page picture turned `quarterTurns` clockwise from the file, with the strokes of `marks`
    /// drawn on it: the pen opaque, the highlighter multiplied so the text under it stays dark. `image` itself
    /// when there are no marks, they sit on the other version of the page (`showsOriginal`), or drawing fails.
    public static func burned(_ image: CGImage, marks: PageMarks?, quarterTurns: Int, showsOriginal: Bool) -> CGImage {
        guard let marks, !marks.isEmpty, marks.onOriginal == showsOriginal,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let shorter: CGFloat = min(width, height)
        for stroke in marks.strokes where !stroke.points.isEmpty {
            let rgb = stroke.ink.rgb
            let color = CGColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
            context.setBlendMode(stroke.tool == .highlighter ? .multiply : .normal)
            let lineWidth: CGFloat = CGFloat(stroke.tool.width) * shorter
            let points: [CGPoint] = stroke.points.map { (point: MarkPoint) -> CGPoint in
                let turned = point.turned(quarterTurns: quarterTurns)
                return CGPoint(x: CGFloat(turned.x) * width, y: (1 - CGFloat(turned.y)) * height)
            }
            if points.count == 1 {
                context.setFillColor(color)
                context.fillEllipse(in: CGRect(x: points[0].x - lineWidth / 2, y: points[0].y - lineWidth / 2,
                                               width: lineWidth, height: lineWidth))
                continue
            }
            context.setStrokeColor(color)
            context.setLineWidth(lineWidth)
            context.addLines(between: points)
            context.strokePath()
        }
        return context.makeImage() ?? image
    }
}
