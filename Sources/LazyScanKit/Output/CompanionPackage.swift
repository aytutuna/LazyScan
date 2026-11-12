import CoreGraphics
import CryptoKit
import Foundation

// Twin of windows/LazyScan.Core/CompanionPackage.cs: the same manifest, the same bytes for
// the same document, the same checks and messages when reading one.

/// How a page's picture is stored in a companion package.
public enum CompanionImageFormat: String, Equatable, Sendable {
    case jpeg
    case png
    /// A bilevel TIFF (CCITT G4), for black & white pages only.
    case tiff
}

/// One picture in a companion package: its encoded bytes and what they show. `pixelWidth` and
/// `pixelHeight` are 0 when a package did not say (decode the picture).
public struct CompanionImage: Equatable, Sendable {
    public var data: Data
    public var format: CompanionImageFormat
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var dpi: Int
    public var colorMode: ColorMode

    public init(data: Data, format: CompanionImageFormat, pixelWidth: Int, pixelHeight: Int, dpi: Int,
                colorMode: ColorMode) {
        self.data = data
        self.format = format
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.dpi = dpi
        self.colorMode = colorMode
    }
}

/// One page of a companion package: its picture as the app shows it and, optionally, what the app
/// knows about it.
public struct CompanionPage {
    public var image: CompanionImage
    /// Quarter turns clockwise still to apply to `image` (0...3), as `ScannedPage.rotationQuarterTurns`.
    public var rotationQuarterTurns: Int
    /// Which side of its sheet the page is, for two-sided scans.
    public var side: PageSide?
    /// The sheet the page belongs to (0 = first), for two-sided scans.
    public var sheetIndex: Int?
    /// The recognized text (Vision-normalized boxes, origin bottom-left); nil when not recognized,
    /// empty when no text was found.
    public var ocrLines: [OCRLine]?
    /// The page as scanned, before crop, clean-up and the like; nil when there is no other version.
    public var original: CompanionImage?
    /// What the camera recorded about the page (`ScannedPage.capture`), its corners in the pixels of
    /// `original` as stored; nil for a page not taken by a camera, and when a package's record of it
    /// cannot be read.
    public var capture: CaptureFacts?

    public init(image: CompanionImage, rotationQuarterTurns: Int = 0, side: PageSide? = nil, sheetIndex: Int? = nil,
                ocrLines: [OCRLine]? = nil, original: CompanionImage? = nil, capture: CaptureFacts? = nil) {
        self.image = image
        self.rotationQuarterTurns = rotationQuarterTurns
        self.side = side
        self.sheetIndex = sheetIndex
        self.ocrLines = ocrLines
        self.original = original
        self.capture = capture
    }
}

/// The app that wrote a package: its name, version and platform ("windows", "macos", "ios").
public struct CompanionWriterInfo: Equatable, Sendable {
    public var app: String
    public var appVersion: String
    public var platform: String

    public init(app: String, appVersion: String, platform: String) {
        self.app = app
        self.appVersion = appVersion
        self.platform = platform
    }
}

/// A document moved between the phone and the desktop as one `.lsdoc` package.
public struct CompanionDocument {
    public var title: String
    public var pages: [CompanionPage]
    public var writer: CompanionWriterInfo
    /// When the document was made; kept to the second, in UTC.
    public var created: Date?
    /// The id of the task the document was scanned with (a `ScanTask` id).
    public var taskId: String?
    /// The name the sender's document was given (its first page's), without an extension; none without one.
    public var suggestedName: String?
    /// The naming template the sender used (see `NamingTemplate`).
    public var namingTemplate: String?

    public init(title: String, pages: [CompanionPage],
                writer: CompanionWriterInfo = CompanionWriterInfo(app: "Lazy Scan", appVersion: "", platform: ""),
                created: Date? = nil, taskId: String? = nil, suggestedName: String? = nil,
                namingTemplate: String? = nil) {
        self.title = title
        self.pages = pages
        self.writer = writer
        self.created = created
        self.taskId = taskId
        self.suggestedName = suggestedName
        self.namingTemplate = namingTemplate
    }
}

/// Why a companion package could not be written or read.
public enum CompanionPackageErrorKind: String, Equatable, Sendable {
    /// The zip archive itself was refused (see `ZipReadError`).
    case invalidArchive
    /// No manifest, or a manifest that is not a Lazy Scan document's.
    case notPackage
    /// A newer major format version than this app reads.
    case newerVersion
    /// The manifest is not JSON, too large, or names a picture twice.
    case invalidManifest
    case noPages
    case tooManyPages
    case missingImage
    /// A picture's SHA-256 or byte count does not match the manifest.
    case checksumMismatch
    /// A picture is not a JPEG, PNG or TIFF, or not the format the manifest names.
    case unsupportedImage
    /// Writing: a page that cannot be packaged (see the message).
    case invalidDocument
    /// Writing: the package would be past the limits a reader holds it to.
    case tooLarge
}

/// A companion package that cannot be written or read, with a message for the user.
public struct CompanionPackageError: LocalizedError, Equatable, Sendable {
    public let kind: CompanionPackageErrorKind
    public let message: String

    public init(_ kind: CompanionPackageErrorKind, _ message: String) {
        self.kind = kind
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// The `.lsdoc` package: a `ZipStore` archive holding `manifest.json` first and then each page's
/// picture ("pages/0001.jpg") followed by its original ("pages/0001-original.png"). Writing is
/// deterministic: the manifest is compact JSON written by hand with a fixed key order and fixed
/// number format, entries are stored and dated 1980-01-01, so this and the C# twin write the same
/// bytes for the same document. Reading goes through `ZipStoreReader`, decodes the manifest
/// leniently (rule 6: unknown keys ignored, missing or wrong-typed fields default, unknown enum
/// values fall back), refuses a newer major version, and checks every picture's byte count,
/// SHA-256 and format.
public enum CompanionPackage {
    public static let fileExtension = "lsdoc"
    public static let formatName = "lsdoc"
    /// The major version: a reader refuses a larger one.
    public static let formatVersion = 1
    /// The minor version: raised for additions older readers can ignore (1: the pages' capture facts).
    public static let formatMinor = 1
    public static let manifestName = "manifest.json"
    public static let maxPages = 2000
    public static let maxManifestBytes = 16 * 1024 * 1024
    /// The resolution a page gets when its manifest gives none.
    public static let defaultDpi = 300

    // MARK: - Writing

    /// The package for `document`; throws `CompanionPackageError` for a document it cannot hold.
    public static func make(_ document: CompanionDocument) throws -> Data {
        ZipStore.make(try entries(document))
    }

    /// Writes the package for `document` to `url`, one entry at a time, with the bytes `make` returns;
    /// throws `CompanionPackageError` for a document it cannot hold. Pictures held as mapped files
    /// stay out of memory, as the package is never built whole.
    public static func write(_ document: CompanionDocument, to url: URL) throws {
        let items = try entries(document)
        // In the temporary folder, not beside `url`, so a part left by a killed app is cleared by the system.
        let part = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).lsdoc.part")
        FileManager.default.createFile(atPath: part.path, contents: nil)
        do {
            let handle = try FileHandle(forWritingTo: part)
            defer { try? handle.close() }
            let writer = ZipStore.Writer(handle: handle)
            for item in items { try writer.add(item) }
            try writer.finish()
            try FileManager.default.moveItem(at: part, to: url)
        } catch {
            try? FileManager.default.removeItem(at: part)
            throw error
        }
    }

    /// The entries of the package for `document`, in package order.
    public static func entries(_ document: CompanionDocument) throws -> [ZipStoreEntry] {
        try validate(document)
        var entries = [ZipStoreEntry(name: manifestName, data: Data(manifestJSON(document).utf8))]
        for (index, page) in document.pages.enumerated() {
            entries.append(ZipStoreEntry(name: imageEntryName(index + 1, format: page.image.format, original: false),
                                         data: page.image.data))
            if let original = page.original {
                entries.append(ZipStoreEntry(name: imageEntryName(index + 1, format: original.format, original: true),
                                             data: original.data))
            }
        }
        let limits = ZipReadLimits.standard
        let total = entries.reduce(0) { $0 + $1.data.count }
        if entries[0].data.count > maxManifestBytes || total > limits.maxTotalBytes
            || entries.contains(where: { $0.data.count > limits.maxEntryBytes }) {
            throw CompanionPackageError(.tooLarge, tooLargeMessage)
        }
        return entries
    }

    /// "The document is larger than 512 MB, too large for one package."
    public static var tooLargeMessage: String {
        L10n.t("The document is larger than {0} MB, too large for one package.", ZipReadLimits.standard.maxTotalBytes / (1024 * 1024))
    }

    /// The manifest's exact text: compact JSON, keys in a fixed order, a line break at the end.
    public static func manifestJSON(_ document: CompanionDocument) -> String {
        var json = "{\"format\":" + quote(formatName)
        json += ",\"formatVersion\":" + String(formatVersion)
        json += ",\"formatMinor\":" + String(formatMinor)
        json += ",\"writer\":{\"app\":" + quote(document.writer.app)
        json += ",\"appVersion\":" + quote(document.writer.appVersion)
        json += ",\"platform\":" + quote(document.writer.platform) + "}"
        if let created = document.created { json += ",\"created\":" + quote(formatDate(created)) }
        json += ",\"title\":" + quote(document.title)
        if let taskId = document.taskId { json += ",\"taskId\":" + quote(taskId) }
        if document.suggestedName != nil || document.namingTemplate != nil {
            json += ",\"naming\":{"
            var first = true
            if let name = document.suggestedName {
                json += "\"suggestedName\":" + quote(name)
                first = false
            }
            if let template = document.namingTemplate {
                json += (first ? "" : ",") + "\"template\":" + quote(template)
            }
            json += "}"
        }
        json += ",\"pages\":["
        for (index, page) in document.pages.enumerated() {
            if index > 0 { json += "," }
            json += "{\"image\":"
            json += imageJSON(page.image, file: imageEntryName(index + 1, format: page.image.format, original: false))
            json += ",\"rotationQuarterTurns\":" + String(page.rotationQuarterTurns)
            if let side = page.side { json += ",\"side\":" + quote(side == .back ? "back" : "front") }
            if let sheet = page.sheetIndex { json += ",\"sheetIndex\":" + String(sheet) }
            if let lines = page.ocrLines {
                json += ",\"ocrLines\":["
                for (k, line) in lines.enumerated() {
                    if k > 0 { json += "," }
                    let box = line.boundingBox
                    json += "{\"text\":" + quote(line.text)
                    json += ",\"x\":" + number(Double(box.origin.x))
                    json += ",\"y\":" + number(Double(box.origin.y))
                    json += ",\"width\":" + number(Double(box.size.width))
                    json += ",\"height\":" + number(Double(box.size.height))
                    json += ",\"confidence\":" + number(Double(line.confidence)) + "}"
                }
                json += "]"
            }
            if let capture = page.capture { json += captureJSON(capture) }
            if let original = page.original {
                json += ",\"original\":"
                json += imageJSON(original, file: imageEntryName(index + 1, format: original.format, original: true))
            }
            json += "}"
        }
        json += "]}\n"
        return json
    }

    /// "pages/0001.jpg", "pages/0001-original.png", "pages/0002.tif".
    public static func imageEntryName(_ pageNumber: Int, format: CompanionImageFormat, original: Bool) -> String {
        let digits = String(pageNumber)
        let padded = String(repeating: "0", count: max(0, 4 - digits.count)) + digits
        return "pages/" + padded + (original ? "-original" : "") + "." + imageExtension(format)
    }

    /// "jpg", "png", "tif".
    public static func imageExtension(_ format: CompanionImageFormat) -> String {
        switch format {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .tiff: return "tif"
        }
    }

    /// The manifest's name for `format`: "jpeg", "png", "tiff".
    public static func formatValue(_ format: CompanionImageFormat) -> String {
        format.rawValue
    }

    /// The format the bytes start like (JPEG SOI, PNG signature, TIFF "II*\0" or "MM\0*"); nil for anything else.
    public static func sniff(_ data: Data) -> CompanionImageFormat? {
        let b = [UInt8](data.prefix(8))
        if b.count >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF { return .jpeg }
        if b.count >= 8 && b == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] { return .png }
        if b.count >= 4 {
            let little = b[0] == 0x49 && b[1] == 0x49 && b[2] == 0x2A && b[3] == 0
            let big = b[0] == 0x4D && b[1] == 0x4D && b[2] == 0 && b[3] == 0x2A
            if little || big { return .tiff }
        }
        return nil
    }

    /// The SHA-256 of `data` as 64 lowercase hex digits.
    public static func sha256Hex(_ data: Data) -> String {
        let digits = Array("0123456789abcdef")
        var text = ""
        text.reserveCapacity(64)
        for byte in SHA256Digest.hash(data) {
            text.append(digits[Int(byte >> 4)])
            text.append(digits[Int(byte & 0x0F)])
        }
        return text
    }

    /// A number as the manifest writes it: rounded half away from zero to 6 decimals, no exponent,
    /// no trailing zeros.
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let scaled = (value * 1_000_000).rounded(.toNearestOrAwayFromZero)
        guard abs(scaled) < 9e15 else { return "0" }
        let units = Int64(scaled)
        let magnitude = units.magnitude
        var text = String(magnitude / 1_000_000)
        let fraction = magnitude % 1_000_000
        if fraction != 0 {
            var digits = String(fraction)
            digits = String(repeating: "0", count: 6 - digits.count) + digits
            while digits.hasSuffix("0") { digits.removeLast() }
            text += "." + digits
        }
        return units < 0 ? "-" + text : text
    }

    /// A string as a JSON literal: quote, backslash and control characters escaped (\n, \r, \t,
    /// \b, \f, else \u00xx), the rest as is.
    static func quote(_ text: String) -> String {
        var json = "\""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x22: json += "\\\""
            case 0x5C: json += "\\\\"
            case 0x0A: json += "\\n"
            case 0x0D: json += "\\r"
            case 0x09: json += "\\t"
            case 0x08: json += "\\b"
            case 0x0C: json += "\\f"
            case 0..<0x20:
                let hex = String(scalar.value, radix: 16)
                json += "\\u00" + (hex.count < 2 ? "0" : "") + hex
            default:
                json.unicodeScalars.append(scalar)
            }
        }
        return json + "\""
    }

    /// "2026-10-20T08:30:00Z": UTC, to the second.
    static func formatDate(_ date: Date) -> String {
        let whole = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
        let c = utcCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: whole)
        return pad(c.year ?? 0, 4) + "-" + pad(c.month ?? 0, 2) + "-" + pad(c.day ?? 0, 2) + "T"
            + pad(c.hour ?? 0, 2) + ":" + pad(c.minute ?? 0, 2) + ":" + pad(c.second ?? 0, 2) + "Z"
    }

    /// A date in exactly `formatDate`'s form; nil for anything else.
    static func parseDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let chars = Array(text.utf8)
        guard chars.count == 20, chars[4] == 0x2D, chars[7] == 0x2D, chars[10] == 0x54, chars[13] == 0x3A,
              chars[16] == 0x3A, chars[19] == 0x5A else { return nil }
        func field(_ start: Int, _ length: Int) -> Int? {
            var value = 0
            for i in start..<(start + length) {
                let c = chars[i]
                guard c >= 0x30 && c <= 0x39 else { return nil }
                value = value * 10 + Int(c - 0x30)
            }
            return value
        }
        guard let year = field(0, 4), let month = field(5, 2), let day = field(8, 2), let hour = field(11, 2),
              let minute = field(14, 2), let second = field(17, 2) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        guard let date = utcCalendar.date(from: components), formatDate(date) == text else { return nil }
        return date
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        return calendar
    }()

    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }

    private static func validate(_ document: CompanionDocument) throws {
        if document.pages.isEmpty { throw CompanionPackageError(.noPages, noPagesMessage) }
        if document.pages.count > maxPages { throw CompanionPackageError(.tooManyPages, tooManyPagesMessage) }
        for (index, page) in document.pages.enumerated() {
            try validateImage(page.image, pageNumber: index + 1, original: false)
            if let original = page.original { try validateImage(original, pageNumber: index + 1, original: true) }
            if page.rotationQuarterTurns < 0 || page.rotationQuarterTurns > 3 {
                throw CompanionPackageError(.invalidDocument, L10n.t("The rotation of page {0} must be {1} to {2} quarter turns.", index + 1, 0, 3))
            }
            if let sheet = page.sheetIndex, sheet < 0 {
                throw CompanionPackageError(.invalidDocument, L10n.t("The sheet number of page {0} cannot be negative.", index + 1))
            }
        }
    }

    private static func validateImage(_ image: CompanionImage, pageNumber: Int, original: Bool) throws {
        let subject = CompanionPackage.subject(pageNumber, original: original)
        if sniff(image.data) != image.format {
            throw CompanionPackageError(.invalidDocument, L10n.t("{0} is not in its declared image format ({1}).", subject, formatValue(image.format).uppercased()))
        }
        if image.format == .tiff && image.colorMode != .blackWhite {
            throw CompanionPackageError(.invalidDocument, L10n.t("{0} is a TIFF, which only black & white pages can be.", subject))
        }
        if image.pixelWidth <= 0 || image.pixelHeight <= 0 || image.dpi <= 0 {
            throw CompanionPackageError(.invalidDocument, L10n.t("{0} needs a size in pixels and a resolution.", subject))
        }
    }

    /// ,"capture":{"quad":[x, y of the four corners clockwise from the top-left],"sourceWidth",
    /// "sourceHeight","kind"[,"focalLength"][,"scale":{"basis"[,"size"],"dpi","pixelWidth",
    /// "pixelHeight","widthInches","heightInches"}]}.
    private static func captureJSON(_ capture: CaptureFacts) -> String {
        var json = ",\"capture\":{\"quad\":["
        for i in 0..<4 {
            if i > 0 { json += "," }
            let corner = capture.quad[i]
            json += number(Double(corner.x)) + "," + number(Double(corner.y))
        }
        json += "],\"sourceWidth\":" + String(capture.sourceWidth)
        json += ",\"sourceHeight\":" + String(capture.sourceHeight)
        json += ",\"kind\":" + quote(capture.kind.rawValue)
        if let focalLength = capture.focalLength { json += ",\"focalLength\":" + number(focalLength) }
        if let scale = capture.scale {
            json += ",\"scale\":{\"basis\":" + quote(scale.basis.rawValue)
            if let size = scale.size { json += ",\"size\":" + quote(size) }
            json += ",\"dpi\":" + String(scale.dpi)
            json += ",\"pixelWidth\":" + String(scale.pixelWidth)
            json += ",\"pixelHeight\":" + String(scale.pixelHeight)
            json += ",\"widthInches\":" + number(scale.widthInches)
            json += ",\"heightInches\":" + number(scale.heightInches) + "}"
        }
        json += "}"
        return json
    }

    private static func imageJSON(_ image: CompanionImage, file: String) -> String {
        var json = "{\"file\":" + quote(file)
        json += ",\"format\":" + quote(formatValue(image.format))
        json += ",\"byteCount\":" + String(image.data.count)
        json += ",\"sha256\":" + quote(sha256Hex(image.data))
        json += ",\"pixelWidth\":" + String(image.pixelWidth)
        json += ",\"pixelHeight\":" + String(image.pixelHeight)
        json += ",\"dpi\":" + String(image.dpi)
        json += ",\"colorMode\":" + quote(image.colorMode.rawValue) + "}"
        return json
    }

    // MARK: - Reading

    /// The document in the package `data`, every picture checked.
    public static func read(_ data: Data, limits: ZipReadLimits = .standard) throws -> CompanionDocument {
        try archive { try read(ZipStoreReader(data: data, limits: limits)) }
    }

    /// The document in the package file at `url`, read from the file a picture at a time.
    public static func read(contentsOf url: URL, limits: ZipReadLimits = .standard) throws -> CompanionDocument {
        try archive { () throws -> CompanionDocument in
            let reader = try ZipStoreReader(contentsOf: url, limits: limits)
            defer { reader.close() }
            return try read(reader)
        }
    }

    public static var notPackageMessage: String { L10n.t("This file is not a Lazy Scan document.") }
    public static var noPagesMessage: String { L10n.t("This document has no pages.") }
    public static var tooManyPagesMessage: String {
        L10n.plural(maxPages, one: "This document has more than {1} page.", other: "This document has more than {1} pages.", maxPages)
    }
    public static var damagedManifestMessage: String { L10n.t("This document cannot be opened: its list of pages is damaged.") }

    /// "This document was made by a newer version of Lazy Scan (package format 2). Update Lazy Scan to open it."
    public static func newerVersionMessage(_ version: Int) -> String {
        L10n.t("This document was made by a newer version of Lazy Scan (package format {0}). Update Lazy Scan to open it.", L10n.plain(version))
    }

    /// "The picture of page 3", "The original picture of page 3".
    public static func subject(_ pageNumber: Int, original: Bool) -> String {
        original ? L10n.t("The original picture of page {0}", pageNumber) : L10n.t("The picture of page {0}", pageNumber)
    }

    /// Runs `body`, turning an archive the zip reader refuses into `.invalidArchive`.
    private static func archive<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let error as ZipReadError {
            throw CompanionPackageError(.invalidArchive, L10n.t("This document cannot be opened: {0}", error.message))
        }
    }

    /// The number of pages in the package file at `url`, from its manifest alone: no picture is read.
    /// Refuses the packages `read` refuses for their manifest.
    public static func pageCount(contentsOf url: URL, limits: ZipReadLimits = .standard) throws -> Int {
        try archive { () throws -> Int in
            let reader = try ZipStoreReader(contentsOf: url, limits: limits)
            defer { reader.close() }
            return try readManifest(reader).pages.count
        }
    }

    private static func readManifest(_ reader: ZipStoreReader) throws -> ManifestDTO {
        guard let manifestEntry = reader.entry(named: manifestName) else {
            throw CompanionPackageError(.notPackage, notPackageMessage)
        }
        if manifestEntry.size > maxManifestBytes { throw CompanionPackageError(.invalidManifest, damagedManifestMessage) }
        let manifest = try decodeManifest(try reader.read(manifestEntry))
        if manifest.format != formatName || manifest.formatVersion < 1 {
            throw CompanionPackageError(.notPackage, notPackageMessage)
        }
        if manifest.formatVersion > Int32(formatVersion) {
            throw CompanionPackageError(.newerVersion, newerVersionMessage(Int(manifest.formatVersion)))
        }
        if manifest.pages.isEmpty { throw CompanionPackageError(.noPages, noPagesMessage) }
        if manifest.pages.count > maxPages { throw CompanionPackageError(.tooManyPages, tooManyPagesMessage) }
        return manifest
    }

    private static func read(_ reader: ZipStoreReader) throws -> CompanionDocument {
        let manifest = try readManifest(reader)
        var used = Set<[UInt8]>() // entry names as bytes, compared exactly as the C# twin does
        var pages: [CompanionPage] = []
        pages.reserveCapacity(manifest.pages.count)
        for (index, dto) in manifest.pages.enumerated() {
            let image = try readImage(reader, dto.image, pageNumber: index + 1, original: false, used: &used)
            var original: CompanionImage?
            if let originalDTO = dto.original {
                original = try readImage(reader, originalDTO, pageNumber: index + 1, original: true, used: &used)
            }
            let side: PageSide?
            switch dto.side {
            case "front"?: side = .front
            case "back"?: side = .back
            default: side = nil
            }
            var sheet: Int?
            if let value = dto.sheetIndex, value >= 0 { sheet = Int(value) }
            let lines = dto.ocrLines?.map { line in
                OCRLine(text: line.text,
                        boundingBox: CGRect(x: line.x, y: line.y, width: line.width, height: line.height),
                        confidence: Float(line.confidence))
            }
            let rotation = dto.rotationQuarterTurns >= 0 && dto.rotationQuarterTurns <= 3 ? Int(dto.rotationQuarterTurns) : 0
            pages.append(CompanionPage(image: image, rotationQuarterTurns: rotation, side: side, sheetIndex: sheet,
                                       ocrLines: lines, original: original, capture: readCapture(dto.capture)))
        }
        return CompanionDocument(
            title: manifest.title, pages: pages,
            writer: CompanionWriterInfo(app: manifest.writer.app, appVersion: manifest.writer.appVersion,
                                        platform: manifest.writer.platform),
            created: parseDate(manifest.created), taskId: manifest.taskId,
            suggestedName: manifest.naming.suggestedName, namingTemplate: manifest.naming.template)
    }

    /// The capture facts as a package records them; nil when missing or unusable (not four finite
    /// corners, no photo size), so a damaged record costs the page only them. An unknown kind reads as a
    /// document; an unusable scale (no resolution or size) is left out, an unknown basis reads as nominal.
    private static func readCapture(_ dto: CaptureDTO?) -> CaptureFacts? {
        guard let dto = dto, let q = dto.quad, q.count == 8, dto.sourceWidth > 0, dto.sourceHeight > 0 else { return nil }
        for value in q where !value.isFinite { return nil }
        let quad = Quad(topLeft: CGPoint(x: q[0], y: q[1]), topRight: CGPoint(x: q[2], y: q[3]),
                        bottomRight: CGPoint(x: q[4], y: q[5]), bottomLeft: CGPoint(x: q[6], y: q[7]))
        let kind: CaptureKind = dto.kind.flatMap { CaptureKind(rawValue: $0) } ?? .document
        var focalLength: Double?
        if let f = dto.focalLength, f > 0, f.isFinite { focalLength = f }
        var scale: CaptureScaleResult?
        if let s = dto.scale, s.dpi > 0, s.pixelWidth > 0, s.pixelHeight > 0,
           s.widthInches > 0, s.widthInches.isFinite, s.heightInches > 0, s.heightInches.isFinite {
            let basis: CaptureScaleBasis = s.basis.flatMap { CaptureScaleBasis(rawValue: $0) } ?? .nominal
            scale = CaptureScaleResult(basis: basis, size: s.size, dpi: Int(s.dpi), pixelWidth: Int(s.pixelWidth),
                                       pixelHeight: Int(s.pixelHeight), widthInches: s.widthInches,
                                       heightInches: s.heightInches)
        }
        return CaptureFacts(quad: quad, sourceWidth: Int(dto.sourceWidth), sourceHeight: Int(dto.sourceHeight),
                            kind: kind, focalLength: focalLength, scale: scale)
    }

    /// The manifest as the C# twin reads it (`StoreFiles.Decode`), through the same settings-file
    /// rules as `StoreFiles.utf8JSON`: UTF-8 with or without a byte-order mark, UTF-16 or UTF-32,
    /// text invalid in its encoding damaging the whole manifest whichever JSONDecoder runs, and no
    /// comma before a closing bracket or brace (System.Text.Json refuses one; JSONDecoder takes it).
    private static func decodeManifest(_ bytes: Data) throws -> ManifestDTO {
        do {
            return try JSONDecoder().decode(ManifestDTO.self, from: StoreFiles.utf8JSON(bytes))
        } catch {
            throw CompanionPackageError(.invalidManifest, damagedManifestMessage)
        }
    }

    private static func readImage(_ reader: ZipStoreReader, _ dto: ImageDTO?, pageNumber: Int, original: Bool,
                                  used: inout Set<[UInt8]>) throws -> CompanionImage {
        let subject = CompanionPackage.subject(pageNumber, original: original)
        let missing = CompanionPackageError(.missingImage, L10n.t("{0} is missing from the document.", subject))
        guard let dto, !dto.file.isEmpty, !dto.file.utf8.elementsEqual(manifestName.utf8) else { throw missing }
        if !used.insert(Array(dto.file.utf8)).inserted {
            throw CompanionPackageError(.invalidManifest, L10n.t("This document cannot be opened: {0} is listed twice.", subject))
        }
        guard let entry = reader.entry(named: dto.file) else { throw missing }
        let damaged = CompanionPackageError(.checksumMismatch, L10n.t("{0} is damaged: its checksum does not match.", subject))
        if let count = dto.byteCount, count != Int64(entry.size) { throw damaged }
        let data = try reader.read(entry)
        if dto.sha256.lowercased() != sha256Hex(data) { throw damaged }
        let unsupported = CompanionPackageError(
            .unsupportedImage, L10n.t("{0} is in a format this version of Lazy Scan cannot read.", subject))
        guard let format = sniff(data) else { throw unsupported }
        if let named = dto.format, CompanionImageFormat(rawValue: named) != format { throw unsupported }
        return CompanionImage(data: data, format: format, pixelWidth: max(Int(dto.pixelWidth), 0),
                              pixelHeight: max(Int(dto.pixelHeight), 0),
                              dpi: dto.dpi > 0 ? Int(dto.dpi) : defaultDpi, colorMode: dto.colorMode)
    }
}

// MARK: - The manifest as read

// Every property on its own and leniently (`decodeLenient`), the defaults below for anything
// missing, null, wrong-typed or unknown. Whole numbers are 32-bit like the C# twin's, so a value
// past Int32 falls back on both platforms; one written with a fraction or an exponent ("1.0",
// "3e2") reads when its value is whole and in range, as JSONDecoder does and the C# twin's
// WholeNumberConverter mirrors.

private struct ManifestDTO: Decodable {
    var format = ""
    var formatVersion: Int32 = 0
    var formatMinor: Int32 = 0
    var writer = WriterDTO()
    var created: String?
    var title = ""
    var taskId: String?
    var naming = NamingDTO()
    var pages: [PageDTO] = []

    enum CodingKeys: String, CodingKey {
        case format, formatVersion, formatMinor, writer, created, title, taskId, naming, pages
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = c.decodeLenient(forKey: .format, default: format)
        formatVersion = c.decodeLenient(forKey: .formatVersion, default: formatVersion)
        formatMinor = c.decodeLenient(forKey: .formatMinor, default: formatMinor)
        writer = c.decodeLenient(forKey: .writer, default: writer)
        created = c.decodeLenient(forKey: .created, default: created)
        title = c.decodeLenient(forKey: .title, default: title)
        taskId = c.decodeLenient(forKey: .taskId, default: taskId)
        naming = c.decodeLenient(forKey: .naming, default: naming)
        pages = c.decodeLenient(forKey: .pages, default: pages)
    }
}

private struct WriterDTO: Decodable {
    var app = ""
    var appVersion = ""
    var platform = ""

    enum CodingKeys: String, CodingKey { case app, appVersion, platform }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app = c.decodeLenient(forKey: .app, default: app)
        appVersion = c.decodeLenient(forKey: .appVersion, default: appVersion)
        platform = c.decodeLenient(forKey: .platform, default: platform)
    }
}

private struct NamingDTO: Decodable {
    var suggestedName: String?
    var template: String?

    enum CodingKeys: String, CodingKey { case suggestedName, template }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        suggestedName = c.decodeLenient(forKey: .suggestedName, default: suggestedName)
        template = c.decodeLenient(forKey: .template, default: template)
    }
}

private struct PageDTO: Decodable {
    var image: ImageDTO?
    var rotationQuarterTurns: Int32 = 0
    var side: String?
    var sheetIndex: Int32?
    var ocrLines: [OCRLineDTO]?
    var original: ImageDTO?
    var capture: CaptureDTO?

    enum CodingKeys: String, CodingKey { case image, rotationQuarterTurns, side, sheetIndex, ocrLines, original, capture }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        image = c.decodeLenient(forKey: .image, default: image)
        rotationQuarterTurns = c.decodeLenient(forKey: .rotationQuarterTurns, default: rotationQuarterTurns)
        side = c.decodeLenient(forKey: .side, default: side)
        sheetIndex = c.decodeLenient(forKey: .sheetIndex, default: sheetIndex)
        ocrLines = c.decodeLenient(forKey: .ocrLines, default: ocrLines)
        original = c.decodeLenient(forKey: .original, default: original)
        capture = c.decodeLenient(forKey: .capture, default: capture)
    }
}

private struct CaptureDTO: Decodable {
    var quad: [Double]?
    var sourceWidth: Int32 = 0
    var sourceHeight: Int32 = 0
    var kind: String?
    var focalLength: Double?
    var scale: ScaleDTO?

    enum CodingKeys: String, CodingKey { case quad, sourceWidth, sourceHeight, kind, focalLength, scale }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        quad = c.decodeLenient(forKey: .quad, default: quad)
        sourceWidth = c.decodeLenient(forKey: .sourceWidth, default: sourceWidth)
        sourceHeight = c.decodeLenient(forKey: .sourceHeight, default: sourceHeight)
        kind = c.decodeLenient(forKey: .kind, default: kind)
        focalLength = c.decodeLenient(forKey: .focalLength, default: focalLength)
        scale = c.decodeLenient(forKey: .scale, default: scale)
    }
}

private struct ScaleDTO: Decodable {
    var basis: String?
    var size: String?
    var dpi: Int32 = 0
    var pixelWidth: Int32 = 0
    var pixelHeight: Int32 = 0
    var widthInches = 0.0
    var heightInches = 0.0

    enum CodingKeys: String, CodingKey { case basis, size, dpi, pixelWidth, pixelHeight, widthInches, heightInches }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        basis = c.decodeLenient(forKey: .basis, default: basis)
        size = c.decodeLenient(forKey: .size, default: size)
        dpi = c.decodeLenient(forKey: .dpi, default: dpi)
        pixelWidth = c.decodeLenient(forKey: .pixelWidth, default: pixelWidth)
        pixelHeight = c.decodeLenient(forKey: .pixelHeight, default: pixelHeight)
        widthInches = c.decodeLenient(forKey: .widthInches, default: widthInches)
        heightInches = c.decodeLenient(forKey: .heightInches, default: heightInches)
    }
}

private struct ImageDTO: Decodable {
    var file = ""
    var format: String?
    var byteCount: Int64?
    var sha256 = ""
    var pixelWidth: Int32 = 0
    var pixelHeight: Int32 = 0
    var dpi: Int32 = 0
    var colorMode: ColorMode = .color

    enum CodingKeys: String, CodingKey { case file, format, byteCount, sha256, pixelWidth, pixelHeight, dpi, colorMode }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        file = c.decodeLenient(forKey: .file, default: file)
        format = c.decodeLenient(forKey: .format, default: format)
        byteCount = c.decodeLenient(forKey: .byteCount, default: byteCount)
        sha256 = c.decodeLenient(forKey: .sha256, default: sha256)
        pixelWidth = c.decodeLenient(forKey: .pixelWidth, default: pixelWidth)
        pixelHeight = c.decodeLenient(forKey: .pixelHeight, default: pixelHeight)
        dpi = c.decodeLenient(forKey: .dpi, default: dpi)
        colorMode = c.decodeLenient(forKey: .colorMode, default: colorMode)
    }
}

private struct OCRLineDTO: Decodable {
    var text = ""
    var x = 0.0
    var y = 0.0
    var width = 0.0
    var height = 0.0
    var confidence = 0.0

    enum CodingKeys: String, CodingKey { case text, x, y, width, height, confidence }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = c.decodeLenient(forKey: .text, default: text)
        x = c.decodeLenient(forKey: .x, default: x)
        y = c.decodeLenient(forKey: .y, default: y)
        width = c.decodeLenient(forKey: .width, default: width)
        height = c.decodeLenient(forKey: .height, default: height)
        confidence = c.decodeLenient(forKey: .confidence, default: confidence)
    }
}

// MARK: - SHA-256

/// SHA-256 over a whole buffer. Also used by the phone link (`SpkiFingerprint`, `PairedDeviceStore`).
enum SHA256Digest {
    static func hash(_ data: Data) -> [UInt8] {
        Array(SHA256.hash(data: data))
    }
}
