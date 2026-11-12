#if os(iOS)
import LazyScanKit
import Foundation
#if canImport(MessageUI)
import MessageUI
#endif
import Photos
import UIKit
import UniformTypeIdentifiers

/// The share sheet a file action asks for: the files, and the title the Mac's share menu would show.
public struct ShareRequest: Identifiable, Equatable {
    public let id: UUID
    public let urls: [URL]
    public let title: String

    public init(urls: [URL], title: String) {
        self.id = UUID()
        self.urls = urls
        self.title = title
    }
}

/// A mail message with files attached, for the Mail composer (`MailComposeView`): the files and its subject.
public struct MailRequest: Identifiable, Equatable {
    public let id: UUID
    public let urls: [URL]
    public let subject: String

    public init(urls: [URL], subject: String) {
        self.id = UUID()
        self.urls = urls
        self.subject = subject
    }
}

/// Why pictures did not reach the photo library: the user (or a restriction) refused access, or the add failed.
public enum PhotosProblem: Identifiable, Equatable {
    case denied
    case failed

    public var id: Self { self }

    public static var title: String { String(localized: "Couldn't save to Photos") }

    public var message: String {
        switch self {
        case .denied:
            return String(localized: "Lazy Scan isn't allowed to add to your photo library. Turn on Add Photos Only for Lazy Scan in Settings.")
        case .failed:
            return String(localized: "The pictures are saved in your folder, but they could not be added to Photos.")
        }
    }
}

/// The iPhone's and iPad's `FileActionService`. iOS has no Finder and no "Open With" menu, so: Open
/// previews the file (Quick Look), Open With and Share open the share sheet (`UIActivityViewController`,
/// where the user picks Mail, Files or another app), Email opens a Mail message with the files attached
/// when Mail is set up (`MFMailComposeViewController.canSendMail`) and the share sheet otherwise, Show in
/// folder opens the Files app at the file's folder, and Copy puts the files (and the picture of a single
/// image) on the pasteboard, on this device only. Show in folder for a folder opens that folder. Lazy Print
/// takes files through the app group both apps hold (`LazyPrintUrl.handoffGroup`), since an iPhone app
/// cannot read another app's paths: the files are copied into a folder there and Lazy Print is opened
/// with the folder's name. The app's root view presents what `shareRequest`,
/// `mailRequest` and `previewURL` ask for; nothing leaves the device unless the user sends the message or
/// picks where it goes in the share sheet.
@MainActor
public final class IOSFileActions: ObservableObject, FileActionService {
    /// The share sheet to show; the root view sets it back to nil when the sheet closes.
    @Published public var shareRequest: ShareRequest?
    /// The file to preview with Quick Look; nil when none is shown.
    @Published public var previewURL: URL?
    /// The Mail message to compose; the root view sets it back to nil when the composer closes.
    @Published public var mailRequest: MailRequest?
    /// Why the last add to Photos failed; the root view's alert sets it back to nil when it closes.
    @Published public var photosProblem: PhotosProblem?
    /// An add to Photos is under way.
    @Published public private(set) var addingToPhotos: Bool = false
    /// The files the last add to Photos took, so the saved row shows them as added.
    @Published public private(set) var addedToPhotos: [URL] = []

    private let pasteboard: UIPasteboard
    /// Opens an address and says whether the system did, once it knows.
    private let openSystemURL: @MainActor (URL, @escaping @MainActor (Bool) -> Void) -> Void
    private let mailAvailable: @MainActor () -> Bool
    private let lazyPrintReachable: @MainActor () -> Bool
    private let handoffContainer: @MainActor () -> URL?
    /// Tells the user of a failure that comes after the action returned (Lazy Print not opening); the app's
    /// state shows it as an error (`IOSShell.makeForIOS`).
    var reportFailure: (@MainActor (String) -> Void)?

    /// `pasteboard` nil: the general pasteboard. `openSystemURL` nil: `UIApplication.open` (tests
    /// pass their own to see the Files app's address without opening it). `mailAvailable` nil: whether
    /// Mail is set up on the device (`canSendMail`; tests say). `lazyPrintReachable` nil: `canOpenURL` for
    /// `lazyprint:`. `handoffContainer` nil: the app group's container, which a build signed without the
    /// entitlement does not have.
    public init(pasteboard: UIPasteboard? = nil, openSystemURL: (@MainActor (URL) -> Void)? = nil,
                mailAvailable: (@MainActor () -> Bool)? = nil, lazyPrintReachable: (@MainActor () -> Bool)? = nil,
                handoffContainer: (@MainActor () -> URL?)? = nil) {
        self.pasteboard = pasteboard ?? UIPasteboard.general
        if let openSystemURL {
            self.openSystemURL = { (url: URL, done: @escaping @MainActor (Bool) -> Void) -> Void in
                openSystemURL(url)
                done(true)
            }
        } else {
            self.openSystemURL = { (url: URL, done: @escaping @MainActor (Bool) -> Void) -> Void in
                UIApplication.shared.open(url, options: [:]) { (opened: Bool) -> Void in
                    Task { @MainActor in done(opened) }
                }
            }
        }
        if let mailAvailable {
            self.mailAvailable = mailAvailable
        } else {
            self.mailAvailable = { () -> Bool in
                IOSFileActions.canSendMail()
            }
        }
        if let lazyPrintReachable {
            self.lazyPrintReachable = lazyPrintReachable
        } else {
            self.lazyPrintReachable = { () -> Bool in
                guard let address = URL(string: LazyPrintUrl.scheme + ":") else { return false }
                return UIApplication.shared.canOpenURL(address)
            }
        }
        if let handoffContainer {
            self.handoffContainer = handoffContainer
        } else {
            self.handoffContainer = { () -> URL? in
                FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: LazyPrintUrl.handoffGroup)
            }
        }
    }

    /// Mail is set up on this device, so a message can be composed here.
    public static func canSendMail() -> Bool {
        #if canImport(MessageUI)
        return MFMailComposeViewController.canSendMail()
        #else
        return false
        #endif
    }

    public func open(_ url: URL) throws {
        previewURL = url
    }

    public func openWith(_ url: URL) throws {
        shareRequest = ShareRequest(urls: [url], title: url.lastPathComponent)
    }

    public func forgetAddedToPhotos() {
        addedToPhotos = []
    }

    /// Adds the pictures to the photo library through add-only access, asking for it the first time. The files
    /// stay where they are. A refusal or a failure is left in `photosProblem`.
    public func addToPhotos(_ urls: [URL]) async {
        guard !addingToPhotos, !urls.isEmpty else { return }
        addingToPhotos = true
        defer { addingToPhotos = false }
        let status: PHAuthorizationStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            photosProblem = status == .denied ? .denied : .failed
            return
        }
        do {
            let pictures: [Data] = try await Task.detached(priority: .userInitiated) { () throws -> [Data] in
                try urls.map { (url: URL) -> Data in try Data(contentsOf: url) }
            }.value
            try await PHPhotoLibrary.shared().performChanges {
                for data in pictures {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                }
            }
            addedToPhotos = urls
        } catch {
            photosProblem = .failed
        }
    }

    /// Opens this app's page in Settings, where the Photos access is turned on.
    public func openSettings() {
        guard let address = URL(string: UIApplication.openSettingsURLString) else { return }
        openSystemURL(address) { (_: Bool) -> Void in }
    }

    public func reveal(_ urls: [URL]) {
        guard let target = IOSFileActions.filesAppURL(for: urls) else { return }
        openSystemURL(target) { (_: Bool) -> Void in }
    }

    public func sendProbe(for urls: [URL]) -> SendProbe {
        SendProbe(canCompose: mailAvailable(), canShare: true)
    }

    public func share(_ urls: [URL], title: String) throws {
        guard !urls.isEmpty else {
            throw ScanError.unsupported(String(localized: "There is nothing to share."))
        }
        shareRequest = ShareRequest(urls: urls, title: title)
    }

    public func composeEmail(_ urls: [URL]) throws {
        guard mailAvailable(), !urls.isEmpty else {
            try share(urls, title: SaveActions.shareTitle(urls))
            return
        }
        mailRequest = MailRequest(urls: urls, subject: SaveActions.shareTitle(urls))
    }

    public func copy(_ content: ClipboardContent) throws {
        var items: [[String: Any]] = []
        for url in content.files {
            let item: [String: Any] = [UTType.fileURL.identifier: url]
            items.append(item)
        }
        if let imageURL = content.imageFile {
            // The file's own bytes, under its own type (PNG, JPEG, TIFF), once they read as a picture.
            let data: Data? = try? Data(contentsOf: imageURL)
            let type: UTType? = UTType(filenameExtension: imageURL.pathExtension)
            guard let data, let type, type.conforms(to: UTType.image), UIImage(data: data) != nil else {
                throw ScanError.exportFailed(String(localized: "\(imageURL.lastPathComponent) could not be read."))
            }
            let item: [String: Any] = [type.identifier: data]
            items.append(item)
        }
        guard !items.isEmpty else {
            throw ScanError.unsupported(String(localized: "There is nothing to copy."))
        }
        pasteboard.setItems(items, options: [UIPasteboard.OptionsKey.localOnly: true])
    }

    public func copyText(_ text: String) throws {
        let item: [String: Any] = [UTType.utf8PlainText.identifier: text]
        pasteboard.setItems([item], options: [UIPasteboard.OptionsKey.localOnly: true])
    }

    /// Lazy Print is installed and the shared container is there to hand files over in.
    public func lazyPrintInstalled() -> Bool {
        handoffContainer() != nil && lazyPrintReachable()
    }

    public func openInLazyPrint(_ urls: [URL]) throws {
        guard let container = handoffContainer(), lazyPrintReachable() else {
            throw ScanError.unsupported(L10n.t("Lazy Print is not installed."))
        }
        let id = try IOSFileActions.stageHandoff(urls, in: container)
        guard let address = URL(string: LazyPrintUrl.buildHandoff(id)) else {
            IOSFileActions.removeHandoff(id, in: container)
            throw ScanError.unsupported(L10n.t("Lazy Print can't open this file."))
        }
        openSystemURL(address) { [weak self] (opened: Bool) -> Void in
            guard !opened else { return }
            IOSFileActions.removeHandoff(id, in: container)
            self?.reportFailure?(L10n.t("Lazy Print could not be opened, so nothing was handed over."))
        }
    }

    /// Deletes what earlier hand-offs left in the shared folder; Lazy Print has read them by now.
    public func clearHandoffs() {
        guard let container = handoffContainer() else { return }
        try? FileManager.default.removeItem(at: container.appendingPathComponent(LazyPrintUrl.handoffFolder))
    }

    /// Copies `urls` under their own names into a new folder `Handoff/<id>` of `container`, after
    /// deleting the folders of earlier hand-offs, and returns the id. The folder is kept out of backups, and
    /// goes again if a file cannot be copied.
    public nonisolated static func stageHandoff(_ urls: [URL], in container: URL, id: UUID = UUID()) throws -> UUID {
        let manager = FileManager.default
        var root = container.appendingPathComponent(LazyPrintUrl.handoffFolder, isDirectory: true)
        if manager.fileExists(atPath: root.path) {
            try manager.removeItem(at: root)
        }
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
        do {
            for url in urls {
                try manager.copyItem(at: url, to: folder.appendingPathComponent(url.lastPathComponent))
            }
        } catch {
            try? manager.removeItem(at: folder)
            throw error
        }
        return id
    }

    /// Deletes hand-off `id`'s folder.
    nonisolated static func removeHandoff(_ id: UUID, in container: URL) {
        let folder = container.appendingPathComponent(LazyPrintUrl.handoffFolder, isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
    }

    /// The Files app's address of the folder holding the first file (`shareddocuments://` and the
    /// folder's path), or of the folder itself when the first is a folder (Show in Files for the save
    /// folder); nil for none or one that is not local.
    public nonisolated static func filesAppURL(for urls: [URL]) -> URL? {
        guard let first = urls.first, first.isFileURL else { return nil }
        let folder: URL = first.hasDirectoryPath ? first : first.deletingLastPathComponent()
        let text: String = folder.absoluteString
        let prefix: String = "file://"
        guard text.hasPrefix(prefix) else { return nil }
        let path: String = String(text.dropFirst(prefix.count))
        return URL(string: "shareddocuments://" + path)
    }
}
#endif
