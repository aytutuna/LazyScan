import Foundation

/// Scan sizes for display. Settings and the scanner report inches; regions that use the metric
/// system read millimeters.
enum ScanSizeText {
    static func usesInches(_ locale: Locale = .current) -> Bool { locale.measurementSystem == .us }

    static let millimetersPerInch = 25.4

    /// "8.5 × 11.0 in", or "216 × 279 mm" on a metric Mac.
    static func size(widthInches: Double, heightInches: Double, locale: Locale = .current) -> String {
        if usesInches(locale) {
            let digits = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1)).locale(locale)
            return String(localized: "\(widthInches.formatted(digits)) × \(heightInches.formatted(digits)) in")
        }
        let digits = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0)).locale(locale)
        let wide = (widthInches * millimetersPerInch).formatted(digits)
        let high = (heightInches * millimetersPerInch).formatted(digits)
        return String(localized: "\(wide) × \(high) mm")
    }

    /// One side, such as the smallest photo side: "1.5 in" or "38 mm".
    static func length(inches: Double, locale: Locale = .current) -> String {
        if usesInches(locale) {
            let value = inches.formatted(.number.precision(.fractionLength(1)).locale(locale))
            return String(localized: "\(value) in")
        }
        let value = (inches * millimetersPerInch).formatted(.number.precision(.fractionLength(0)).locale(locale))
        return String(localized: "\(value) mm")
    }
}
