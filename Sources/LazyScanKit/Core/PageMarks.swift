import Foundation

public enum MarkTool: String, Codable, Sendable {
    case pen
    case highlighter

    /// The width of the line as a fraction of the shorter side of the page picture.
    public var width: Double {
        switch self {
        case .pen: return 0.008
        case .highlighter: return 0.04
        }
    }
}

public enum MarkInk: String, Codable, Sendable, CaseIterable {
    case black, blue, red, green, yellow, pink, orange

    /// Red, green and blue, 0...1.
    var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .black: return (0.05, 0.05, 0.05)
        case .blue: return (0.1, 0.3, 0.85)
        case .red: return (0.85, 0.1, 0.1)
        case .green: return (0.1, 0.6, 0.2)
        case .yellow: return (1, 0.92, 0.2)
        case .pink: return (1, 0.45, 0.7)
        case .orange: return (1, 0.6, 0.1)
        }
    }
}

/// A point on the page picture as the file holds it, before any turn: x and y are 0...1 from the top left.
public struct MarkPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// This point of the file picture on the picture turned `quarterTurns` clockwise.
    public func turned(quarterTurns: Int) -> MarkPoint {
        var point: MarkPoint = self
        for _ in 0..<(((quarterTurns % 4) + 4) % 4) {
            point = MarkPoint(x: 1 - point.y, y: point.x)
        }
        return point
    }

    /// The point of the file picture that shows at this point of the picture turned `quarterTurns` clockwise.
    public func unturned(quarterTurns: Int) -> MarkPoint {
        var point: MarkPoint = self
        for _ in 0..<(((quarterTurns % 4) + 4) % 4) {
            point = MarkPoint(x: point.y, y: 1 - point.x)
        }
        return point
    }
}

public struct MarkStroke: Codable, Equatable, Sendable {
    public var tool: MarkTool
    public var ink: MarkInk
    public var points: [MarkPoint]

    public init(tool: MarkTool, ink: MarkInk, points: [MarkPoint]) {
        self.tool = tool
        self.ink = ink
        self.points = points
    }
}

/// The pen and highlighter strokes on a queued page, kept with the queue and drawn into what is saved, printed
/// and copied (`PageMarkRenderer`). They sit on the picture the page showed when they were drawn: the page as
/// scanned when `onOriginal`, else the cropped and straightened one.
public struct PageMarks: Codable, Equatable, Sendable {
    public private(set) var strokes: [MarkStroke]
    public var onOriginal: Bool

    public init(strokes: [MarkStroke] = [], onOriginal: Bool = false) {
        self.strokes = strokes
        self.onOriginal = onOriginal
    }

    public var isEmpty: Bool { strokes.isEmpty }

    public mutating func begin(tool: MarkTool, ink: MarkInk, at point: MarkPoint) {
        strokes.append(MarkStroke(tool: tool, ink: ink, points: [point]))
    }

    /// Carries the stroke being drawn on to `point`; a point that has not moved adds nothing.
    public mutating func extend(_ point: MarkPoint) {
        guard let last = strokes.last?.points.last, last != point else { return }
        strokes[strokes.count - 1].points.append(point)
    }

    public mutating func removeLast() {
        if !strokes.isEmpty { strokes.removeLast() }
    }
}
