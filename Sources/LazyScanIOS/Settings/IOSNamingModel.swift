#if os(iOS)
import LazyScanKit
import Foundation

/// The file name editor without a screen: the template as typed, the parts to insert (`NamingTokens.all`),
/// the name the next file gets and what is wrong with the template. A template that is not blank is put in
/// use as it is typed (one with an unknown part too, which stays as typed, as on Windows); a blank one
/// keeps the last name in use. The same template names every task's files, as on the desktop.
@MainActor
public final class IOSNamingModel: ObservableObject {
    public static var title: String { String(localized: "File name") }
    public static var insertTitle: String { String(localized: "Insert") }
    public static var exampleLabel: String { String(localized: "Next file") }
    public static var resetLabel: String { String(localized: "Reset") }

    @Published public private(set) var text: String
    private let state: AppState

    public init(state: AppState) {
        self.state = state
        self.text = state.settings.namingTemplate
    }

    /// `NamingTokens.all`, but on the phone a document's name comes from its QR sheet, not the page strip,
    /// {docdate} is the day the file is saved (receipts are not read for the date printed on them), and the
    /// task is the Type.
    public var parts: [NamingToken] {
        NamingTokens.all.map { (part: NamingToken) -> NamingToken in
            switch part.token {
            case "{label}":
                return NamingToken(label: part.label, token: part.token, help: String(localized: "The document's name from its QR sheet"))
            case "{intent}":
                return NamingToken(label: String(localized: "Document or photos"), token: part.token, help: part.help)
            case "{task}":
                return NamingToken(label: String(localized: "Type"), token: part.token, help: String(localized: "The type, e.g. “Receipt”"))
            case "{docdate}":
                return NamingToken(label: String(localized: "Day saved"), token: part.token, help: String(localized: "The day the file is saved"))
            default:
                return part
            }
        }
    }

    /// What is wrong with the template typed; nil when it is fine.
    public var problem: String? { NamingTokens.problem(text) }

    /// The format the next file is saved in: the one chosen where the scan screen saves what it collects
    /// (`IOSShell.collectsPages`: any format for Photos and Receipts, a picture a page when pictures are saved,
    /// `IOSShell.savesImages`), else what the desktop's save writes.
    public var format: OutputFormat {
        let settings: ScanSettings = state.settings
        if IOSSettingsSections.offersEveryFormat(settings) {
            return settings.format
        }
        if IOSShell.collectsPages(settings) && IOSShell.savesImages(settings) {
            return settings.format.imageFormatOrJPEG
        }
        return NamingTokens.savedFormat(settings)
    }

    /// The name the next file gets ("Scan 2026-10-20 4.pdf"), with the template in use.
    public var example: String {
        state.fileNameExample(state.settings.namingTemplate, format: format)
    }

    /// `example` without its extension, for the Options row: the format has a row of its own.
    public var exampleName: String {
        String(example.dropLast(format.fileExtension.count + 1))
    }

    /// The template typed: in use at once unless it is blank.
    public func setText(_ newText: String) {
        text = newText
        if NamingTokens.problem(newText) != NamingTokens.emptyProblem {
            state.settings.namingTemplate = newText
        }
    }

    /// A part put at the end of the template (`NamingTokens.insert`), with a space before it.
    public func insert(_ token: String) {
        let insertion: NamingInsertion = NamingTokens.insert(token, into: text, at: text.count)
        setText(insertion.text)
    }

    /// Back to a fresh install's template, "Scan {date} {counter}".
    public func reset() {
        setText(ScanSettings().namingTemplate)
    }
}
#endif
