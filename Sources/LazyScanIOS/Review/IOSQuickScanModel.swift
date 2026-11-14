#if os(iOS)
import LazyScanKit
import CoreGraphics
import Foundation
import VisionKit

/// Quick scan's screen without a screen (I14): the page one shot gave (`AppState.quickScanPage`, held in
/// memory), saved as a picture (JPEG unless an image format is chosen) or its text copied
/// (`OCRService`), or discarded; Live Text on the page (VisionKit's `ImageAnalyzer` with an
/// `ImageAnalysisInteraction`) selects part of its text where the device supports it. Add to Contacts reads
/// the text and offers what it finds as a new contact.
@MainActor
public final class IOSQuickScanModel: ObservableObject {
    public let state: AppState
    /// The contact being offered; the screen shows the system's new-contact sheet while it is set.
    @Published public var contact: ContactFields?
    private let liveTextSupported: @MainActor () -> Bool

    /// `liveTextSupported` nil: whether this device can run Live Text (`ImageAnalyzer.isSupported`; tests say).
    public init(state: AppState, liveTextSupported: (@MainActor () -> Bool)? = nil) {
        self.state = state
        if let liveTextSupported {
            self.liveTextSupported = liveTextSupported
        } else {
            self.liveTextSupported = { () -> Bool in
                IOSQuickScanModel.deviceSupportsLiveText()
            }
        }
    }

    /// Live Text runs on this device (not in every Simulator).
    public static func deviceSupportsLiveText() -> Bool {
        ImageAnalyzer.isSupported
    }

    /// The page to show; nil once saved or discarded.
    public var image: CGImage? { state.quickScanPage?.image }

    /// A page is held: the screen is shown.
    public var isShown: Bool { state.quickScanPage != nil }

    /// The page is shown with Live Text, so its text can be selected on it.
    public var offersLiveText: Bool { isShown && liveTextSupported() }

    /// Save and Copy text can be pressed: a page is held and nothing runs.
    public var canAct: Bool { isShown && !state.isBusy }

    /// The format the page is saved in: the task's picture format, JPEG otherwise.
    public var format: OutputFormat { state.settings.format.imageFormatOrJPEG }

    /// "Save JPEG".
    public var saveLabel: String { String(localized: "Save \(format.label)") }

    public static var copyTextLabel: String { String(localized: "Copy text") }
    public static var addToContactsLabel: String { String(localized: "Add to Contacts") }
    public static var addToContactsHint: String {
        String(localized: "Opens a new contact filled in from the text on this page.")
    }
    public static var contactSavedLine: String { String(localized: "Contact saved.") }
    public static var noContactLine: String { String(localized: "No phone number, email, link or address found.") }
    public static var discardLabel: String { String(localized: "Discard") }
    public static var discardTitle: String { String(localized: "Discard the page?") }
    public static var discardLine: String { String(localized: "The page has not been saved.") }
    public static var title: String { IOSScanKind.text.title }

    public func save() {
        guard canAct else { return }
        state.saveQuickScan()
    }

    public func copyText() {
        guard canAct else { return }
        state.copyQuickScanText()
    }

    public func addToContacts() {
        guard canAct else { return }
        state.readQuickScanText { [weak self] (text: String) in
            guard let self else { return }
            let fields: ContactFields = ContactFields.found(in: text)
            if fields.isEmpty {
                self.state.showQuickScanStatus(IOSQuickScanModel.noContactLine)
            } else {
                self.contact = fields
            }
        }
    }

    /// The new-contact sheet closed; `saved` is whether the contact was saved.
    public func contactClosed(saved: Bool) {
        contact = nil
        if saved {
            state.showQuickScanStatus(IOSQuickScanModel.contactSavedLine)
        }
    }

    public func discard() {
        guard canAct else { return }
        state.discardQuickScan()
    }
}

/// What the text of a card holds for a new contact, in the order it was found: phone numbers, emails, links and
/// addresses. The name is left to the person.
public struct ContactFields: Equatable, Identifiable {
    public struct Address: Equatable {
        public var street: String = ""
        public var city: String = ""
        public var state: String = ""
        public var postalCode: String = ""
        public var country: String = ""
    }

    public let id: UUID = UUID()
    public var phones: [String] = []
    public var emails: [String] = []
    public var links: [String] = []
    public var addresses: [Address] = []

    public var isEmpty: Bool { phones.isEmpty && emails.isEmpty && links.isEmpty && addresses.isEmpty }

    public static func == (lhs: ContactFields, rhs: ContactFields) -> Bool {
        lhs.phones == rhs.phones && lhs.emails == rhs.emails && lhs.links == rhs.links && lhs.addresses == rhs.addresses
    }

    /// The phone numbers (a number with the same digits once), emails, links and addresses `NSDataDetector` finds in `text`.
    public static func found(in text: String) -> ContactFields {
        var fields: ContactFields = ContactFields()
        let types: NSTextCheckingResult.CheckingType = [.phoneNumber, .link, .address]
        guard let detector = try? NSDataDetector(types: types.rawValue) else { return fields }
        var digitsSeen: Set<String> = []
        let range: NSRange = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, options: [], range: range) {
            switch match.resultType {
            case .phoneNumber:
                guard let number = match.phoneNumber else { continue }
                let digits: String = number.filter { $0.isNumber }
                if digitsSeen.insert(digits).inserted {
                    fields.phones.append(number)
                }
            case .link:
                guard let url = match.url else { continue }
                if url.scheme?.lowercased() == "mailto" {
                    fields.emails.append(String(url.absoluteString.dropFirst("mailto:".count)))
                } else {
                    fields.links.append(url.absoluteString)
                }
            case .address:
                guard let parts = match.addressComponents else { continue }
                var address: Address = Address()
                address.street = parts[.street] ?? ""
                address.city = parts[.city] ?? ""
                address.state = parts[.state] ?? ""
                address.postalCode = parts[.zip] ?? ""
                address.country = parts[.country] ?? ""
                if address.street.isEmpty && address.city.isEmpty && address.state.isEmpty
                    && address.postalCode.isEmpty && address.country.isEmpty {
                    address.street = (text as NSString).substring(with: match.range)
                }
                fields.addresses.append(address)
            default:
                continue
            }
        }
        return fields
    }
}
#endif
