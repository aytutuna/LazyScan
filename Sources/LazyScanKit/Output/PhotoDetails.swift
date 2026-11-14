import Foundation

/// When a picture was taken and a caption for it, written into saved images as EXIF DateTimeOriginal and
/// ImageDescription. Empty values write no tags. Twin of C# `PhotoDetails`.
public struct PhotoDetails: Equatable, Sendable {
    public var year: Int?
    public var month: Int?
    public var day: Int?
    public var caption: String

    public static let none = PhotoDetails()

    public init(year: Int? = nil, month: Int? = nil, day: Int? = nil, caption: String = "") {
        self.year = year
        self.month = month
        self.day = day
        self.caption = caption
    }

    /// "yyyy:MM:dd 00:00:00", or nil without a four-digit year. A month or day that is missing or out
    /// of range counts as 1.
    public var exifDate: String? {
        guard let year, (1000...9999).contains(year) else { return nil }
        let m = month.flatMap { (1...12).contains($0) ? $0 : nil } ?? 1
        let last = Self.daysIn(month: m, year: year)
        let d = day.flatMap { (1...last).contains($0) ? $0 : nil } ?? 1
        return String(format: "%04ld:%02ld:%02ld 00:00:00", year, m, d)
    }

    /// The caption without surrounding white space, or nil when nothing is left.
    public var exifCaption: String? {
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        switch month {
        case 2: return leap ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}
