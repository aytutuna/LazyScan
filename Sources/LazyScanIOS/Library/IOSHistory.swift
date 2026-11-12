#if os(iOS)
import LazyScanKit
import CoreGraphics
import Foundation

/// A scan of this session as the Scans screen lists it: its small picture, "Document · 300 dpi", the
/// time it was taken (with the day for earlier days), and the whole of it for VoiceOver.
public struct IOSHistoryRow: Identifiable {
    public let id: UUID
    public let thumbnail: CGImage
    public let title: String
    public let time: String
    public let symbol: String
    public let accessibilityLabel: String
}

/// The Scans screen without a screen: `AppState.scanHistory` (this session's scans, newest first, small
/// pictures only), read-only as on the Mac and Windows.
public enum IOSHistory {
    public static var title: String { String(localized: "Scans") }
    public static var emptyTitle: String { String(localized: "No scans yet") }
    public static var emptyLine: String { String(localized: "Scans from this session appear here, newest first.") }
    public static var clearButton: String { String(localized: "Clear") }
    public static var clearQuestion: String { String(localized: "Clear this session's scans? Saved files are not touched.") }
    public static var clearAction: String { String(localized: "Clear Scans") }

    /// "1 scan", "13 scans".
    public static func countText(_ count: Int) -> String {
        L10n.plural(count, one: "{0} scan", other: "{0} scans")
    }

    public static func rows(_ entries: [ScanHistoryEntry], now: Date, calendar: Calendar = Calendar.current,
                            locale: Locale = Locale.current) -> [IOSHistoryRow] {
        var rows: [IOSHistoryRow] = []
        for entry in entries {
            let time: String = timeText(entry.date, now: now, calendar: calendar, locale: locale)
            let width: Int = Int(entry.pixelSize.width)
            let height: Int = Int(entry.pixelSize.height)
            let photo: Bool = entry.intent == .photo
            let dpi: String = entry.dpi.formatted(.number.grouping(.never))
            let w: String = width.formatted(.number.grouping(.never))
            let h: String = height.formatted(.number.grouping(.never))
            let spoken: String = photo
                ? String(localized: "Photo scan, \(dpi) dpi, \(w) by \(h) pixels, \(time)")
                : String(localized: "Document scan, \(dpi) dpi, \(w) by \(h) pixels, \(time)")
            rows.append(IOSHistoryRow(id: entry.id, thumbnail: entry.thumbnail,
                                      title: String(localized: "\(entry.intent.label) \u{00B7} \(dpi) dpi"), time: time,
                                      symbol: photo ? "photo" : "doc.text", accessibilityLabel: spoken))
        }
        return rows
    }

    /// The time of a scan of today ("4:23 PM"), with the day for an earlier one ("Oct 19, 4:23 PM").
    public static func timeText(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter: DateFormatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let template: String = calendar.isDate(date, inSameDayAs: now) ? "jmm" : "MMMdjmm"
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
#endif
