#if os(iOS)
import LazyScanKit
import CoreGraphics
import Foundation
import ImageIO

/// A file in the save folder as the Saved files screen lists it.
public struct IOSSavedFile: Identifiable, Equatable, Sendable {
    public let url: URL
    public let modified: Date
    public let byteCount: Int
    /// Saved by the last save of this session (`AppState.lastSavedURLs`).
    public let isNew: Bool

    public init(url: URL, modified: Date, byteCount: Int, isNew: Bool) {
        self.url = url
        self.modified = modified
        self.byteCount = byteCount
        self.isNew = isNew
    }

    /// The modification date is part of it, so a file written again gets a fresh row.
    public var id: String { "\(url.path)|\(modified.timeIntervalSince1970)" }
    public var name: String { url.lastPathComponent }
    public var isPDF: Bool { url.pathExtension.lowercased() == "pdf" }
    public var isImage: Bool { SaveActions.isImageFile(url) }

    /// The icon shown until (or instead of) its picture.
    public var symbol: String {
        if isPDF { return "doc.richtext" }
        if isImage { return "photo" }
        return "doc.text"
    }

    /// "3 pages · 498 KB · Oct 20", with the year when it is not this year's; the page count is left out
    /// until it is known (`IOSSavedFiles.pageCount(of:)`, PDFs only).
    public func detail(pages: Int?, now: Date = Date(), calendar: Calendar = Calendar.current) -> String {
        let style: Date.FormatStyle = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
        let sameYear: Bool = calendar.isDate(modified, equalTo: now, toGranularity: .year)
        let date: String = sameYear ? modified.formatted(style.month(.abbreviated).day())
                                    : modified.formatted(style.month(.abbreviated).day().year())
        var parts: [String] = []
        if let pages {
            parts.append(L10n.plural(pages, one: "{0} page", other: "{0} pages"))
        }
        parts.append(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))
        parts.append(date)
        return parts.joined(separator: " \u{00B7} ")
    }
}

/// How recently a file was saved, as the Saved files list groups its rows.
public enum IOSSavedSection: Sendable {
    case today, thisWeek, earlier

    public var title: String {
        switch self {
        case .today: return L10n.t("Today")
        case .thisWeek: return L10n.t("This week")
        case .earlier: return L10n.t("Earlier")
        }
    }
}

public struct IOSSavedGroup: Identifiable, Equatable, Sendable {
    public let section: IOSSavedSection
    public let files: [IOSSavedFile]
    public var id: IOSSavedSection { section }
}

/// The save folder read: its files newest first, or that it could not be read.
public struct IOSSavedFolder: Equatable, Sendable {
    public let files: [IOSSavedFile]
    /// The folder is there but could not be listed.
    public let failed: Bool
}

/// The Saved files screen without a screen: everything in the save folder the app writes (PDF, JPEG,
/// PNG, TIFF, text and Word files), newest first, as on the Mac and Windows; the files of the last save
/// are marked. Each file offers what iOS has of the saved files' actions (`SaveActions.offered`): Share and
/// Show in Files first. Nothing is deleted here, as on the desktop: the Files app does that.
public enum IOSSavedFiles {
    public static var title: String { String(localized: "Saved files") }
    public static var emptyTitle: String { String(localized: "Nothing saved yet") }
    public static var emptyLine: String { String(localized: "Saved files appear here, newest first.") }
    public static var failedLine: String { String(localized: "The save folder could not be read.") }
    public static var newBadge: String { String(localized: "New") }
    public static var revealLabel: String { String(localized: "Show in Files") }
    public static var moreLabel: String { String(localized: "More") }

    /// The extensions of the files the app saves.
    public static let knownExtensions: Set<String> = ["pdf", "jpg", "jpeg", "png", "tiff", "tif", "txt", "docx"]

    /// The folder the settings save to, in this install's Documents folder when it was the app's own
    /// folder of an earlier one. A picked folder's path is its own, even in another app's Documents.
    public static func folder(_ settings: ScanSettings) -> URL {
        var path: String = (settings.destinationPath as NSString).expandingTildeInPath
        if settings.destinationBookmark == nil {
            path = ScanSettings.rebasedDestinationPath(path, documents: IOSShell.documentsFolder)
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// The folder the Saved files list and the Save to row show: the app's own folder while a picked
    /// folder is out of reach (its drive unplugged, say), since a save goes there meanwhile
    /// (`AppState.destinationDirectory`); else `folder(_:)`.
    public static func shownFolder(_ settings: ScanSettings) -> URL {
        let picked: URL = folder(settings)
        guard settings.destinationBookmark != nil, (try? picked.checkResourceIsReachable()) != true else { return picked }
        let path: String = ScanSettings.rebasedDestinationPath(ScanSettings.defaultDestinationPath, documents: IOSShell.documentsFolder)
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// The files of `folder` and of the folders a file name template makes under it
    /// (`NamingTemplate.filesUnder`) the app saves, newest first (a hidden file, a folder or another kind
    /// of file is left out); those in `justSaved` marked new. A folder not made yet is empty, not a failure.
    public static func list(in folder: URL, justSaved: [URL]) -> IOSSavedFolder {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        let urls: [URL]
        do {
            urls = try NamingTemplate.filesUnder(folder, keys: keys)
        } catch {
            return IOSSavedFolder(files: [], failed: FileManager.default.fileExists(atPath: folder.path))
        }
        var saved: Set<String> = []
        for url in justSaved {
            saved.insert(url.standardizedFileURL.path)
        }
        var files: [IOSSavedFile] = []
        for url in urls {
            guard knownExtensions.contains(url.pathExtension.lowercased()) else { continue }
            let values: URLResourceValues? = try? url.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == false { continue }
            let file: IOSSavedFile = IOSSavedFile(url: url, modified: values?.contentModificationDate ?? Date.distantPast,
                                                  byteCount: values?.fileSize ?? 0,
                                                  isNew: saved.contains(url.standardizedFileURL.path))
            files.append(file)
        }
        files.sort { (a: IOSSavedFile, b: IOSSavedFile) -> Bool in
            if a.modified != b.modified { return a.modified > b.modified }
            return a.name < b.name
        }
        return IOSSavedFolder(files: files, failed: false)
    }

    /// `files` (newest first) cut into Today, This week (earlier than today, in the calendar's current week)
    /// and Earlier; a group with no files is left out.
    public static func groups(_ files: [IOSSavedFile], now: Date = Date(), calendar: Calendar = Calendar.current) -> [IOSSavedGroup] {
        let startOfToday: Date = calendar.startOfDay(for: now)
        let startOfWeek: Date = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfToday
        var today: [IOSSavedFile] = []
        var week: [IOSSavedFile] = []
        var earlier: [IOSSavedFile] = []
        for file in files {
            if file.modified >= startOfToday {
                today.append(file)
            } else if file.modified >= startOfWeek {
                week.append(file)
            } else {
                earlier.append(file)
            }
        }
        var groups: [IOSSavedGroup] = []
        if !today.isEmpty { groups.append(IOSSavedGroup(section: .today, files: today)) }
        if !week.isEmpty { groups.append(IOSSavedGroup(section: .thisWeek, files: week)) }
        if !earlier.isEmpty { groups.append(IOSSavedGroup(section: .earlier, files: earlier)) }
        return groups
    }

    /// The actions of a file's More menu: what `SaveActions` offers for one file, but Share, which has its own
    /// button, Show in Files, which the screen puts first in the menu, and Open with, which iOS answers with
    /// the share sheet too.
    /// Lazy Print is in it when `lazyPrint` says it can take the file.
    public static func moreActions(lazyPrint: Bool) -> [FileAction] {
        var actions: [FileAction] = []
        for action in SaveActions.offered(fileCount: 1, lazyPrint: lazyPrint) where action != .share && action != .reveal && action != .openWith {
            actions.append(action)
        }
        return actions
    }

    public static var rotateLabel: String { L10n.t("Rotate 90\u{00B0} clockwise") }

    /// An action's name here: Show in folder is the Files app on iOS.
    public static func label(_ action: FileAction) -> String {
        action == .reveal ? revealLabel : action.label
    }

    public static func symbol(_ action: FileAction) -> String {
        switch action {
        case .open: return "eye"
        case .openWith: return "arrow.up.forward.app"
        case .reveal: return "folder"
        case .share: return "square.and.arrow.up"
        case .addPages: return "text.badge.plus"
        case .email: return "envelope"
        case .lazyPrint: return "printer"
        case .copy: return "doc.on.doc"
        }
    }

    /// A small picture of a saved file: a picture's own (ImageIO), a PDF's first page (Core Graphics);
    /// nil for text and Word files, which show their icon. Safe off the main thread.
    public static func thumbnail(of url: URL, maxSide: Int) -> CGImage? {
        let ext: String = url.pathExtension.lowercased()
        if ext == "pdf" { return pdfThumbnail(url, maxSide: maxSide) }
        guard SaveActions.isImageFile(url), let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The pages of a PDF; nil when it cannot be opened or is locked. Safe off the main thread.
    public static func pageCount(of url: URL) -> Int? {
        guard let document = CGPDFDocument(url as CFURL), !document.isEncrypted || document.isUnlocked else { return nil }
        return document.numberOfPages > 0 ? document.numberOfPages : nil
    }

    private static func pdfThumbnail(_ url: URL, maxSide: Int) -> CGImage? {
        guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else { return nil }
        let box: CGRect = page.getBoxRect(.cropBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale: CGFloat = CGFloat(maxSide) / max(box.width, box.height)
        let width: Int = max(1, Int((box.width * scale).rounded()))
        let height: Int = max(1, Int((box.height * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        context.drawPDFPage(page)
        return context.makeImage()
    }
}
#endif
