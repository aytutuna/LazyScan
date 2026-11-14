#if os(iOS)
import ContactsUI
import SwiftUI
import UIKit

/// The system's new-contact screen filled in with `fields`, in a SwiftUI sheet. It saves the contact itself, so
/// no Contacts permission is asked; `onDone` runs when it closes, with whether the contact was saved.
struct NewContactView: UIViewControllerRepresentable {
    let fields: ContactFields
    let onDone: @MainActor (Bool) -> Void

    func makeCoordinator() -> NewContactCoordinator {
        NewContactCoordinator(onDone: onDone)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller: CNContactViewController = CNContactViewController(forNewContact: NewContactView.contact(for: fields))
        controller.delegate = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    static func contact(for fields: ContactFields) -> CNMutableContact {
        let contact: CNMutableContact = CNMutableContact()
        contact.phoneNumbers = fields.phones.map { (number: String) -> CNLabeledValue<CNPhoneNumber> in
            CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: number))
        }
        contact.emailAddresses = fields.emails.map { (email: String) -> CNLabeledValue<NSString> in
            CNLabeledValue(label: CNLabelWork, value: email as NSString)
        }
        contact.urlAddresses = fields.links.map { (link: String) -> CNLabeledValue<NSString> in
            CNLabeledValue(label: CNLabelWork, value: link as NSString)
        }
        contact.postalAddresses = fields.addresses.map { (address: ContactFields.Address) -> CNLabeledValue<CNPostalAddress> in
            let postal: CNMutablePostalAddress = CNMutablePostalAddress()
            postal.street = address.street
            postal.city = address.city
            postal.state = address.state
            postal.postalCode = address.postalCode
            postal.country = address.country
            return CNLabeledValue(label: CNLabelWork, value: postal)
        }
        return contact
    }
}

/// Hears when the new-contact screen is done; it gives the saved contact, or nil when cancelled.
final class NewContactCoordinator: NSObject, CNContactViewControllerDelegate {
    private let onDone: @MainActor (Bool) -> Void

    init(onDone: @escaping @MainActor (Bool) -> Void) {
        self.onDone = onDone
    }

    func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) {
        let done: @MainActor (Bool) -> Void = onDone
        let saved: Bool = contact != nil
        Task { @MainActor in
            done(saved)
        }
    }
}
#endif
