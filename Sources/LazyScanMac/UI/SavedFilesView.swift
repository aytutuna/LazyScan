#if os(macOS)
import AppKit
import LazyScanKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The "Saved" tab: everything in the destination folder, newest first, with open, open with,
/// show in Finder, share, email, copy (`AppState.runFileAction`), 90°-rotation for saved image
/// files and, for a PDF, adding the queued pages to its end (`AppState.appendToPDF(at:)`). Every
/// action is also in the card's More menu and context menu.
struct SavedFilesView: View {
    @EnvironmentObject var state: AppState

    @State private var files: [SavedFileItem] = []
    @State private var loadFailed = false
    /// Paths with a rotate in flight — their buttons are disabled so a double-click
    /// can't race two rewrites of the same file.
    @State private var rotatingPaths: Set<String> = []

    var body: some View {
        Group {
            if files.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 16)], spacing: 16) {
                        ForEach(files) { file in
                            SavedFileCard(file: file,
                                          rotating: rotatingPaths.contains(file.url.path),
                                          canAppend: state.canAppendPages,
                                          actions: state.offeredFileActions(for: [file.url]).filter { $0 != .addPages },
                                          onAction: { state.runFileAction($0, urls: [file.url]) },
                                          onRotate: { rotate(file) },
                                          onAppend: { state.appendToPDF(at: file.url) })
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
        // Refresh whenever something new is saved, and on every appearance.
        .task(id: state.lastSavedURLs) {
            state.removeStaleSaveTemps()
            await reload()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await reload() }
                } label: {
                    Label("Reload Folder", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Re-read the destination folder")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text(loadFailed ? String(localized: "The destination folder could not be read.")
                            : String(localized: "Nothing saved yet"))
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(destinationURL.path)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
            Button("Show in Finder") {
                try? FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
                state.revealInFinder(destinationURL)
            }
        }
        .padding(40)
    }

    private var destinationURL: URL {
        URL(fileURLWithPath: (state.settings.destinationPath as NSString).expandingTildeInPath,
            isDirectory: true)
    }

    private func reload() async {
        let dir = destinationURL
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let found: [URL]? = await Task.detached { try? NamingTemplate.filesUnder(dir, keys: keys) }.value
        guard let urls = found else {
            files = []
            loadFailed = FileManager.default.fileExists(atPath: dir.path)
            return
        }
        loadFailed = false
        let known: Set<String> = ["pdf", "jpg", "jpeg", "png", "tiff", "tif", "txt", "docx"]
        files = urls
            .filter { known.contains($0.pathExtension.lowercased()) }
            .compactMap { url -> SavedFileItem? in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return SavedFileItem(url: url,
                                     modified: values?.contentModificationDate ?? .distantPast,
                                     fileSize: values?.fileSize ?? 0)
            }
            .sorted { $0.modified > $1.modified }
    }

    /// "Turn after save": rewrite a saved image file rotated 90° clockwise, keeping its
    /// format and DPI metadata. (PDFs are not rotatable here — rotate pages before saving.)
    ///
    /// Safety: the rotated file is written beside the original and swapped in atomically,
    /// so a failed write never destroys the only copy; concurrent rotates of the same file
    /// are blocked via `rotatingPaths`; multi-page TIFFs are refused rather than silently
    /// truncated to their first page.
    private func rotate(_ file: SavedFileItem) {
        guard let format = file.imageFormat else { return }
        let url = file.url
        guard !rotatingPaths.contains(url.path) else { return }
        rotatingPaths.insert(url.path)
        Task {
            let failure: String? = await Task.detached(priority: .userInitiated) { () -> String? in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                    return String(localized: "The file could not be read.")
                }
                guard CGImageSourceGetCount(source) == 1 else {
                    return String(localized: "It has multiple pages — rotate it in Preview instead.")
                }
                // Full-size decode with the EXIF orientation baked in, so the pixels
                // match what the user sees before rotating them.
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 100_000,
                ]
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                    return String(localized: "The image could not be decoded.")
                }
                let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
                let dpi = (props?[kCGImagePropertyDPIWidth] as? NSNumber)?.intValue ?? 300
                // A black & white TIFF (1 bit per pixel; the app writes them as CCITT G4) stays G4.
                let depth = (props?[kCGImagePropertyDepth] as? NSNumber)?.intValue ?? 8
                let mode: ColorMode = format == .tiff && depth == 1 ? .blackWhite : .color
                let rotated = ImagePipeline.rotate(image, quarterTurns: 1)
                let tmp = url.deletingLastPathComponent()
                    .appendingPathComponent(".\(UUID().uuidString).\(url.pathExtension)")
                do {
                    // High quality to limit generation loss on repeated JPEG rotates.
                    try ImageExporter.write(rotated, to: tmp, format: format, dpi: dpi, jpegQuality: 0.95,
                                            colorMode: mode)
                    _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
                    return nil
                } catch {
                    try? FileManager.default.removeItem(at: tmp)
                    return String(localized: "The rotated copy could not be written.")
                }
            }.value
            rotatingPaths.remove(url.path)
            if let failure {
                state.errorMessage = String(localized: "Could not rotate \(url.lastPathComponent): \(failure)")
            } else {
                await reload()
            }
        }
    }
}

// MARK: - File-private model

fileprivate struct SavedFileItem: Identifiable, Equatable {
    let url: URL
    let modified: Date
    let fileSize: Int

    /// Identity includes the modification date so a rotate-in-place refreshes the card.
    var id: String { "\(url.path)|\(modified.timeIntervalSince1970)" }

    var isPdf: Bool { url.pathExtension.lowercased() == "pdf" }

    /// A text file or Word document: no picture to show.
    var isTextDocument: Bool { ["txt", "docx"].contains(url.pathExtension.lowercased()) }

    var imageFormat: OutputFormat? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return .jpeg
        case "png": return .png
        case "tiff", "tif": return .tiff
        default: return nil
        }
    }
}

// MARK: - File-private card

fileprivate struct SavedFileCard: View {
    let file: SavedFileItem
    let rotating: Bool
    /// There are queued pages to add to a PDF (`AppState.canAppendPages`).
    let canAppend: Bool
    /// What the file's menus offer (`AppState.offeredFileActions`).
    let actions: [FileAction]
    let onAction: (FileAction) -> Void
    let onRotate: () -> Void
    let onAppend: () -> Void

    @State private var thumbnail: CGImage?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.12))
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                        .padding(6)
                } else {
                    Image(systemName: file.isTextDocument ? "doc.text" : file.isPdf ? "doc.richtext" : "photo")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 140)
            .onTapGesture(count: 2) { onAction(.open) }

            Text(file.url.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(file.url.lastPathComponent)

            Text("\(file.modified.formatted(date: .abbreviated, time: .shortened)) · \(sizeText)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button("Open") { onAction(.open) }
                Button {
                    onAction(.share)
                } label: {
                    Label(FileAction.share.label, systemImage: FileAction.share.systemImage)
                        .labelStyle(.iconOnly)
                }
                .help(FileAction.share.hint(fileCount: 1))
                Button {
                    onAction(.reveal)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help("Show in Finder")
                .accessibilityLabel("Show in Finder")
                if file.imageFormat != nil {
                    Button {
                        onRotate()
                    } label: {
                        if rotating {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "rotate.right")
                        }
                    }
                    .disabled(rotating)
                    .help("Rotate the saved file 90° clockwise")
                }
                Menu {
                    actionMenu
                } label: {
                    Label("More actions", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More: open with, email, copy and the other actions")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .contextMenu { actionMenu }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1))
        .task(id: file.id) {
            thumbnail = await loadThumbnail(for: file)
        }
    }

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(file.fileSize), countStyle: .file)
    }

    /// Every action on the file, then Rotate for image files and adding the queued pages for a PDF:
    /// the More menu and the context menu.
    @ViewBuilder
    private var actionMenu: some View {
        ForEach(actions) { action in
            Button {
                onAction(action)
            } label: {
                Label(action.label, systemImage: action.systemImage)
            }
        }
        if file.imageFormat != nil {
            Divider()
            Button {
                onRotate()
            } label: {
                Label("Rotate 90\u{00B0} Clockwise", systemImage: "rotate.right")
            }
            .disabled(rotating)
        }
        if file.isPdf {
            Divider()
            Button {
                onAppend()
            } label: {
                Label(PDFAppender.savedMenuLabel, systemImage: "doc.badge.plus")
            }
            .disabled(!canAppend)
            .help(PDFAppender.savedMenuHint)
        }
    }
}

// MARK: - File-private helpers

/// Lets a few thumbnails load at a time, so a folder of many files does not render them all at once.
fileprivate actor ThumbnailGate {
    static let shared = ThumbnailGate(limit: 4)

    private var free: Int
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { free = limit }

    func enter() async {
        if free > 0 {
            free -= 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func leave() {
        if waiting.isEmpty {
            free += 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}

/// Small preview of a saved file: CGImageSource thumbnailing for images, first-page
/// rendering through Core Graphics for PDFs; none for text files and Word documents, which show
/// their icon. Files not downloaded from iCloud and very large PDFs show their icon too.
fileprivate func loadThumbnail(for file: SavedFileItem) async -> CGImage? {
    if file.isTextDocument { return nil }
    let url = file.url
    let isPdf = file.isPdf
    let size = file.fileSize
    if let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus,
       status != .current {
        return nil
    }
    if isPdf && size > 200_000_000 { return nil }
    await ThumbnailGate.shared.enter()
    let image = await Task.detached(priority: .utility) { () -> CGImage? in
        if isPdf { return pdfThumbnail(url, maxSide: 400) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 400,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }.value
    await ThumbnailGate.shared.leave()
    return image
}

fileprivate func pdfThumbnail(_ url: URL, maxSide: Int) -> CGImage? {
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
#endif
