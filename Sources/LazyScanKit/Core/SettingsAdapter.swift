import CoreGraphics
import Foundation

/// Which setting `SettingsAdapter.adapt` changed. Twin of C# `SettingsChange`
/// (`windows/LazyScan.Core/SettingsAdapter.cs`).
public enum SettingsChange: String, Sendable {
    case source
    case resolution
    case duplex
    case paperSize
}

/// A setting changed to suit the scanner, with a sentence saying so.
public struct SettingsNote: Equatable, Sendable {
    public let change: SettingsChange
    public let message: String
    /// What the status line keeps of it (`StatusDetail`).
    public let warning: StatusWarning

    public init(change: SettingsChange, message: String, warning: StatusWarning) {
        self.change = change
        self.message = message
        self.warning = warning
    }
}

/// The settings as the scanner can use them, and what had to change.
public struct AdaptedSettings: Equatable, Sendable {
    public let settings: ScanSettings
    public let notes: [SettingsNote]
}

/// Fits settings to what a scanner offers: a source it has (the first one it lists when the
/// chosen one is missing; the flatbed when it lists none), two-sided feeder scans by hand when
/// its feeder scans one side, a paper size that fits the glass or the feeder (Automatic
/// otherwise), and the nearest resolution it supports. Used whenever settings meet a scanner:
/// applying a preset or task, and connecting to another scanner. Twin of C# `SettingsAdapter`.
public enum SettingsAdapter {
    /// `settings` adapted to `capabilities` (unchanged when nil: no scanner connected yet).
    public static func adapt(_ settings: ScanSettings, to capabilities: ScannerCapabilities?) -> AdaptedSettings {
        var s = settings
        var notes: [SettingsNote] = []
        guard let capabilities else { return AdaptedSettings(settings: s, notes: notes) }

        if !capabilities.sources.contains(s.source) {
            let fallback = capabilities.sources.first ?? .flatbed
            if fallback != s.source {
                notes.append(SettingsNote(change: .source, message: fallback == .documentFeeder
                    ? L10n.t("This scanner has no flatbed, so the document feeder is used.")
                    : L10n.t("This scanner has no document feeder, so the flatbed is used."),
                                          warning: fallback == .documentFeeder ? .feederUsed : .flatbedUsed))
                s.source = fallback
            }
        }

        if s.source == .documentFeeder && s.duplex == .both && !capabilities.supportsDuplex {
            notes.append(SettingsNote(change: .duplex,
                                      message: L10n.t("This scanner's feeder scans one side at a time, so you'll turn the stack over by hand."),
                                      warning: .twoSidedByHand))
            s.duplex = .manual
        }

        let feeder = s.source == .documentFeeder
        let area: CGSize? = feeder ? capabilities.feederSizeInches : capabilities.flatbedSizeInches
        if s.paperSize == .longPaper && !feeder {
            notes.append(SettingsNote(change: .paperSize,
                                      message: L10n.t("Long paper is scanned from the feeder, so the paper size is Automatic."),
                                      warning: .paperAutomatic))
            s.paperSize = .auto
        } else if !PaperSizes.fits(s.paperSize, in: area, custom: s.customPaper) {
            let name: String = s.paperSize == .custom
                ? L10n.t("{0} × {1} in", s.customPaper.width, s.customPaper.height)
                : s.paperSize.label
            notes.append(SettingsNote(change: .paperSize,
                                      message: feeder
                                          ? L10n.t("{0} paper does not fit this scanner's feeder, so the paper size is Automatic.", name)
                                          : L10n.t("{0} paper does not fit this scanner's glass, so the paper size is Automatic.", name),
                                      warning: .paperAutomatic))
            s.paperSize = .auto
        }

        let resolution = capabilities.nearestResolution(to: s.resolution)
        if resolution != s.resolution {
            notes.append(SettingsNote(change: .resolution,
                                      message: L10n.t("This scanner does not offer {0} dpi, so {1} dpi is used.", L10n.plain(s.resolution), L10n.plain(resolution)),
                                      warning: .dpiUsed(resolution)))
            s.resolution = resolution
        }
        return AdaptedSettings(settings: s, notes: notes)
    }
}
