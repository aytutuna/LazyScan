#if os(iOS)
import LazyScanKit
import CoreGraphics
import Foundation

/// The iPhone's short texts of the copy screen (I16), the Mac inspector's Photocopy words where it has them.
public enum IOSCopyText {
    public static var title: String { L10n.t("Copy|photocopy title") }
    public static var pageName: String { String(localized: "Page to copy") }
    public static var scaleLabel: String { String(localized: "Scale") }
    public static var scaleHint: String { String(localized: "Real size, shrink to fit, fill the page, or a percentage.") }
    public static var customChoice: String { String(localized: "Custom percent…") }
    public static var customValue: String { String(localized: "Custom") }
    public static var customLabel: String { String(localized: "Custom percent") }
    public static var centerLabel: String { String(localized: "Center") }
    public static var centerHint: String { String(localized: "Off: the page starts at its top-left corner.") }
    public static var pdfLabel: String { String(localized: "Also save a PDF") }
    public static var pdfHint: String { String(localized: "Keeps a PDF of each copy in your save folder") }
    public static var printLabel: String { String(localized: "Print") }
    public static var printHint: String { String(localized: "Choose an AirPrint printer, then print") }
    public static var againLabel: String { String(localized: "Copy again") }
    public static var discardLabel: String { String(localized: "Discard") }
    public static var discardHint: String { String(localized: "Delete the page; can't be undone") }
    public static var discardTitle: String { String(localized: "Discard the copy?") }
    public static var discardLine: String { String(localized: "The copy has not been printed.") }
    public static var closeLabel: String { String(localized: "Close") }
    public static var doneLabel: String { String(localized: "Done") }
    public static var addPageLabel: String { String(localized: "Add page") }
    public static var addPageHint: String { String(localized: "Shoot another page of this copy") }
    // The queue's pages (Save's Print…, After saving's Print) are printed, not copied.
    public static var printTitle: String { String(localized: "Print") }
    public static var printPageName: String { String(localized: "Page to print") }
    public static var printAgainLabel: String { String(localized: "Print again") }
    public static var noPrinterYet: String { String(localized: "You choose the printer when printing") }

    /// "Copies: 2".
    public static func copiesTitle(_ count: Int) -> String {
        String(localized: "Copies: \(count)")
    }

    /// "Prints on Office Printer".
    public static func printsOn(_ printerName: String) -> String {
        String(localized: "Prints on \(printerName)")
    }

    /// "Print again on Office Printer", for VoiceOver.
    public static func againHint(_ printerName: String) -> String {
        String(localized: "Print again on \(printerName)")
    }

    /// "Page 2 of 5", under the pages; shown for two or more.
    public static func pageOfCount(_ number: Int, _ count: Int) -> String {
        String(localized: "Page \(number) of \(count)")
    }

    /// "Custom percent: 120%", beside the stepper.
    public static func customTitle(_ percent: Int) -> String {
        String(localized: "Custom percent: \(percent)%")
    }

    /// "120 percent", for VoiceOver on the stepper.
    public static func customSpoken(_ percent: Int) -> String {
        String(localized: "\(percent) percent")
    }

    /// "2 of 5", for VoiceOver on each page.
    public static func positionOfCount(_ number: Int, _ count: Int) -> String {
        String(localized: "\(number) of \(count)")
    }
}

/// The copy screen without a screen (I16): the pages a photocopy holds (`AppState.copyPages`, in memory
/// only), how many copies, the scale (Fit to page and fixed when a page has no known size,
/// `AppState.copyNeedsFit`) and centering, Also save a PDF, the printer the copy goes to, and Print, Copy again on the
/// printer picked last, or Discard.
@MainActor
public final class IOSCopyModel: ObservableObject {
    public let state: AppState
    private let pickedPrinter: @MainActor () -> String?

    /// `pickedPrinter` nil: the printer picked last in AirPrint's picker (`IOSPrintService.lastPrinterName`);
    /// tests say.
    public init(state: AppState, pickedPrinter: (@MainActor () -> String?)? = nil) {
        self.state = state
        if let pickedPrinter {
            self.pickedPrinter = pickedPrinter
        } else {
            let service: IOSPrintService? = state.printService as? IOSPrintService
            self.pickedPrinter = { () -> String? in service?.lastPrinterName }
        }
    }

    /// The first page; nil once discarded.
    public var image: CGImage? { state.copyPages.first?.image }

    /// "Page 2 of 5" for the page at `index` when the copy has several; nil for one.
    public func pageCaption(_ index: Int) -> String? {
        let count: Int = state.copyPages.count
        return count > 1 ? IOSCopyText.pageOfCount(index + 1, count) : nil
    }

    /// The screen's title, in printing's words for the queue's pages (`AppState.copyIsOfQueue`), as are
    /// `pageName` and `againLabel`.
    public var title: String { state.copyIsOfQueue ? IOSCopyText.printTitle : IOSCopyText.title }

    /// The page's name for VoiceOver.
    public var pageName: String { state.copyIsOfQueue ? IOSCopyText.printPageName : IOSCopyText.pageName }

    public var againLabel: String { state.copyIsOfQueue ? IOSCopyText.printAgainLabel : IOSCopyText.againLabel }

    /// Pages are held: the screen is shown.
    public var isShown: Bool { !state.copyPages.isEmpty }

    /// Print, Copy again and Discard can be pressed: pages are held and nothing runs.
    public var canAct: Bool { isShown && !state.isBusy }

    public var copies: Int { PrintCopies.clamp(state.settings.taskOptions.copyCount) }

    public func setCopies(_ count: Int) {
        state.setCopyCount(count)
    }

    /// The scale can't be changed: some page's real size is not known, so the copy is fitted.
    public var fitIsForced: Bool { state.copyNeedsFit }

    /// One entry of the Scale menu.
    public enum ScaleChoice: Hashable {
        case actual
        case fit
        case fill
        case preset(Int)
        case custom
    }

    /// The scale in force: Fit while it is forced, else the stored one.
    public var scale: CopyScale { fitIsForced ? .fit : state.settings.taskOptions.copyScale }

    /// The stored percentage, between 25 and 400.
    public var customPercent: Int { PrintScale.clamp(state.settings.taskOptions.copyScalePercent) }

    /// The entry the Scale menu shows as chosen. `customPicked` is set once Custom percent is picked, so the
    /// stepper stays when its value reaches a preset; a stored percentage that is no preset shows as Custom
    /// without it.
    public func scaleChoice(customPicked: Bool) -> ScaleChoice {
        switch scale {
        case .actual: return .actual
        case .fit: return .fit
        case .fill: return .fill
        case .percent:
            let percent: Int = customPercent
            return customPicked || !PrintScale.presetPercents.contains(percent) ? .custom : .preset(percent)
        }
    }

    /// The stepper under the Scale row shows: Custom is the choice.
    public func showsCustomPercent(customPicked: Bool) -> Bool { scaleChoice(customPicked: customPicked) == .custom }

    /// Center applies to the scale chosen (Fit and Fill always center).
    public var showsCenter: Bool { PrintScale.hasCenterChoice(scale) }

    /// What the Scale row says: the choice's words, "Custom" for a percentage of one's own.
    public func scaleValue(customPicked: Bool) -> String {
        showsCustomPercent(customPicked: customPicked) ? IOSCopyText.customValue : PrintScale.label(for: scale, percent: customPercent)
    }

    /// The menu entry's words.
    public func scaleTitle(_ choice: ScaleChoice) -> String {
        switch choice {
        case .actual: return PrintScale.label(for: .actual, percent: customPercent)
        case .fit: return PrintScale.label(for: .fit, percent: customPercent)
        case .fill: return PrintScale.label(for: .fill, percent: customPercent)
        case .preset(let percent): return PrintScale.label(for: .percent, percent: percent)
        case .custom: return IOSCopyText.customChoice
        }
    }

    public func setScaleChoice(_ choice: ScaleChoice) {
        guard !fitIsForced else { return }
        switch choice {
        case .actual: state.setCopyScale(.actual)
        case .fit: state.setCopyScale(.fit)
        case .fill: state.setCopyScale(.fill)
        case .preset(let percent):
            state.setCopyScalePercent(percent)
            state.setCopyScale(.percent)
        case .custom: state.setCopyScale(.percent)
        }
    }

    public func setCustomPercent(_ percent: Int) {
        state.setCopyScalePercent(percent)
    }

    public var centers: Bool { state.settings.taskOptions.copyCenter }

    public func setCenters(_ center: Bool) {
        state.setCopyCenter(center)
    }

    public var alsoSavesPDF: Bool { state.settings.taskOptions.copyAlsoSavePdf }

    public func setAlsoSavesPDF(_ save: Bool) {
        state.setCopyAlsoSavePdf(save)
    }

    /// The printer picked last; nil until one is picked.
    public var printerName: String? { pickedPrinter() }

    /// "Prints on Office Printer" once a printer was picked, else that it is chosen when printing.
    public var printerLine: String {
        printerName.map { IOSCopyText.printsOn($0) } ?? IOSCopyText.noPrinterYet
    }

    /// Copy again is offered once a printer was picked.
    public var offersCopyAgain: Bool { printerName != nil }

    public func print() {
        guard canAct else { return }
        state.printHeldCopy()
    }

    public func printAgain() {
        guard canAct, offersCopyAgain else { return }
        state.printHeldCopyAgain()
    }

    /// Another page can be shot into this copy: not the queue's pages, and not once printed, since a page
    /// after a print starts a new copy.
    public var offersAddPage: Bool { !state.copyIsOfQueue && !state.copyIsPrinted }

    /// The exit reads Done once the copy has printed, Discard before.
    public var exitIsDone: Bool { !state.copyIsOfQueue && state.copyIsPrinted }

    public func discard() {
        guard canAct else { return }
        state.discardHeldCopy()
    }
}
#endif
