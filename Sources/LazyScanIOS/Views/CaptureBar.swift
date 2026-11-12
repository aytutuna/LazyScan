#if os(iOS)
import LazyScanKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// What Photos (`ImportButtons`) brings in: the most photos picked at once, and each picked photo loaded
/// only when its turn comes (`load`), so one photo's bytes are in memory at a time. Imported photos go to
/// the corner editor one by one (`IOSImportSession`); the root view shows it.
enum CaptureBar {
    /// The most photos picked at once.
    static let maxPicked: Int = 50

    /// The picked photos in the order picked, each loaded only when its turn comes (`load`), so one
    /// photo's bytes are in memory at a time.
    static func sources(_ items: [PhotosPickerItem]) -> [IOSImportSource] {
        var sources: [IOSImportSource] = []
        for item in items {
            let source = IOSImportSource(name: PhotoImport.label, expectedKind: .image, asksOnlyWhenUnsure: true) { () async -> Result<IOSImportItem, IOSImportError> in
                await CaptureBar.load(item)
            }
            sources.append(source)
        }
        return sources
    }

    /// The picked photo's own bytes, named "Photo"; `photoNotLoadedMessage` when the library could not
    /// hand it over.
    static func load(_ item: PhotosPickerItem) async -> Result<IOSImportItem, IOSImportError> {
        do {
            let image: IOSPickedImage? = try await item.loadTransferable(type: IOSPickedImage.self)
            if let loaded = image {
                return .success(IOSImportItem(name: PhotoImport.label, data: loaded.data, kind: .image))
            }
        } catch {
            // Told below, as for a photo that did not come.
        }
        return .failure(IOSImportError(message: IOSImportText.photoNotLoadedMessage))
    }
}

/// An import's progress ("Importing photo 2 of 5…", a shot's "Reading the photo…") with Stop while more
/// photos or pages follow the one in hand, over the scanner tab's bars and over camera mode's viewfinder.
struct ImportProgressRow: View {
    @EnvironmentObject private var importer: IOSImportSession

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                ProgressView()
                Text(importer.progressText ?? "")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("import.progress")
            Spacer(minLength: 0)
            if importer.canStop {
                Button(role: .cancel) {
                    importer.stop()
                } label: {
                    Text(IOSImportText.stopLabel)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint(Text("Ends the import after this photo or page"))
                .accessibilityIdentifier("import.stop")
            }
        }
    }
}

/// Photos (the system's photo picker, several in the order picked) and Files (photos and PDFs, and a
/// Lazy Scan document, which goes to the scan screen's banner instead), as icons, or in grey circles
/// (`round`) as on the bottom bar, which rests the camera while one is open (`onPresenting`). Each picked
/// photo is loaded only when its turn comes.
struct ImportButtons: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var importer: IOSImportSession
    var round: Bool = false
    /// One above the other, for a side column.
    var stacked: Bool = false
    /// Photos or Files opened (true) or closed.
    var onPresenting: (@MainActor (Bool) -> Void)?

    @State private var picked: [PhotosPickerItem] = []
    @State private var showsPhotos: Bool = false
    @State private var showsFiles: Bool = false

    var body: some View {
        let layout: AnyLayout = stacked ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            Button {
                showsPhotos = true
            } label: {
                label(IOSImportText.photosLabel, symbol: "photo.on.rectangle")
            }
            .accessibilityLabel(Text(IOSImportText.photosLabel))
            .accessibilityIdentifier("import.photos")
            Button {
                showsFiles = true
            } label: {
                label(IOSImportText.filesLabel, symbol: "folder")
            }
            .accessibilityLabel(Text(IOSImportText.filesLabel))
            .accessibilityIdentifier("import.files")
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.4)
        .photosPicker(isPresented: $showsPhotos, selection: $picked, maxSelectionCount: CaptureBar.maxPicked,
                      selectionBehavior: .ordered, matching: .images, preferredItemEncoding: .current)
        .fileImporter(isPresented: $showsFiles,
                      allowedContentTypes: [UTType.image, UTType.pdf, IOSShell.packageType],
                      allowsMultipleSelection: true) { (result: Result<[URL], Error>) in
            switch result {
            case .success(let urls):
                let session: IOSImportSession = importer
                let appState: AppState = state
                var imports: [URL] = []
                for url in urls {
                    if IOSShell.isPackage(url) {
                        Task { @MainActor in
                            await IOSShell.openPackage(url, in: appState)
                        }
                    } else {
                        imports.append(url)
                    }
                }
                let files: [URL] = imports
                Task { @MainActor in
                    await session.importFiles(files)
                }
            case .failure(let error):
                state.errorMessage = error.localizedDescription
            }
        }
        .onChange(of: showsPhotos || showsFiles) { (_: Bool, shown: Bool) in
            onPresenting?(shown)
        }
        .onChange(of: picked) { (_: [PhotosPickerItem], items: [PhotosPickerItem]) in
            guard !items.isEmpty else { return }
            picked = []
            let session: IOSImportSession = importer
            let sources: [IOSImportSource] = CaptureBar.sources(items)
            Task { @MainActor in
                await session.importSources(sources)
            }
        }
    }

    /// Photos and Files are off while a page waits to be retaken: the camera's next photo is the one that replaces it.
    private var available: Bool {
        importer.canImport && state.retakingID == nil
    }

    private func label(_ title: String, symbol: String) -> some View {
        Image(systemName: symbol)
            .font(round ? Font.body : Font.title3)
            .foregroundStyle(round ? Color.primary : Color.accentColor)
            .frame(width: 44, height: 44)
            .background {
                if round {
                    Circle()
                        .fill(Color(uiColor: .tertiarySystemFill))
                }
            }
            .contentShape(Rectangle())
    }
}

/// The shutter shrinks while pressed; with Reduce Motion it only dims.
struct ShutterButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(reduceMotion ? Animation.easeInOut(duration: 0.2) : Animation.spring(duration: 0.2), value: configuration.isPressed)
    }
}
#endif
