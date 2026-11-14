#if os(iOS)
import LazyScanKit
import SwiftUI

/// Everything in the save folder, newest first, under Today, This week and Earlier (`IOSSavedFiles`): each
/// file with its picture, name, pages, size and date, the files of the last save marked New; Share on each, and its
/// other actions (Show in Files, open, email, copy, Lazy Print while it is installed, and Rotate for a picture) in its menu, through
/// `AppState.runFileAction` as on the desktop, and for a PDF, adding the queued pages to its end (`AppState.appendToPDF(at:)`), whose progress and result show under
/// the list. Read again whenever something is saved and when pulled down.
struct SavedFilesScreen: View {
    @EnvironmentObject private var state: AppState
    @State private var folder: IOSSavedFolder = IOSSavedFolder(files: [], failed: false)
    /// The PDF the queued pages are being added to from this screen: the status under the list is about it.
    @State private var appending: URL?
    /// Counts the reads started, so a listing that arrives after a newer read began is dropped.
    @State private var reads: Int = 0
    /// Paths being turned, so a second tap cannot start another rewrite of the same file.
    @State private var rotating: Set<String> = []
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let place: URL = IOSSavedFiles.shownFolder(state.settings)
        let lazyPrint: Bool = state.lazyPrintInstalled
        let groups: [IOSSavedGroup] = IOSSavedFiles.groups(folder.files)
        List {
            if folder.files.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(folder.failed ? IOSSavedFiles.failedLine : IOSSavedFiles.emptyTitle)
                        .font(.headline)
                    if !folder.failed {
                        Text(IOSSavedFiles.emptyLine)
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("saved.empty")
            }
            ForEach(groups) { (group: IOSSavedGroup) in
                Section {
                    ForEach(group.files) { (file: IOSSavedFile) in
                        let canLazyPrint: Bool = lazyPrint && SaveActions.canPrintWithLazyPrint([file.url])
                        SavedFileRow(file: file, canAppend: state.canAppendPages,
                                     canLazyPrint: canLazyPrint,
                                     isRotating: rotating.contains(file.url.path),
                                     onAction: run, onAppend: append, onRotate: rotate)
                    }
                } header: {
                    Text(group.section.title)
                } footer: {
                    if group.id == groups.last?.id {
                        appendStatus
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(IOSSavedFiles.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    state.revealInFinder(place)
                } label: {
                    Label(IOSSavedFiles.revealLabel, systemImage: "folder")
                }
                .accessibilityIdentifier("saved.folder")
            }
        }
        .refreshable {
            await reload()
        }
        .task(id: state.lastSavedURLs) {
            state.removeStaleSaveTemps()
            await reload()
        }
        .onChange(of: scenePhase) { (_: ScenePhase, phase: ScenePhase) in
            if phase == .active {
                Task { await reload() }
            }
        }
        .onDisappear {
            appending = nil
        }
    }

    @ViewBuilder
    private var appendStatus: some View {
        if appending != nil {
            HStack(spacing: 8) {
                if state.isBusy {
                    ProgressView()
                }
                Text(state.statusMessage)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("saved.appendStatus")
        }
    }

    /// Lists the folder off the main actor; the rows shown stay until the new list is in.
    private func reload() async {
        let place: URL = IOSSavedFiles.shownFolder(state.settings)
        let justSaved: [URL] = state.lastSavedURLs
        reads += 1
        let mine: Int = reads
        let task: Task<IOSSavedFolder, Never> = Task.detached(priority: .userInitiated) { () -> IOSSavedFolder in
            IOSSavedFiles.list(in: place, justSaved: justSaved)
        }
        let listed: IOSSavedFolder = await task.value
        if mine == reads {
            folder = listed
        }
    }

    private func run(_ action: FileAction, _ file: IOSSavedFile) {
        if !state.runFileAction(action, urls: [file.url]) {
            Task { await reload() }
        }
    }

    private func append(_ file: IOSSavedFile) {
        appending = file.url
        state.appendToPDF(at: file.url)
    }

    private func rotate(_ file: IOSSavedFile) {
        let url: URL = file.url
        guard !rotating.contains(url.path) else { return }
        rotating.insert(url.path)
        Task {
            let task: Task<String?, Never> = Task.detached(priority: .userInitiated) { () -> String? in
                ImageExporter.rotateClockwise(url)
            }
            let failure: String? = await task.value
            rotating.remove(url.path)
            if let failure {
                state.errorMessage = L10n.t("Could not rotate {0}: {1}", url.lastPathComponent, failure)
            } else {
                await reload()
            }
        }
    }
}

/// One saved file: its picture (or icon), name, "New" for the last save's, pages, size and date, then Share
/// and More (Show in Files first in it).
private struct SavedFileRow: View {
    let file: IOSSavedFile
    /// There are queued pages to add to a PDF (`AppState.canAppendPages`).
    let canAppend: Bool
    /// Lazy Print is installed and can take this file.
    let canLazyPrint: Bool
    let isRotating: Bool
    let onAction: (FileAction, IOSSavedFile) -> Void
    let onAppend: (IOSSavedFile) -> Void
    let onRotate: (IOSSavedFile) -> Void
    @State private var thumbnail: CGImage?
    @State private var pages: Int?

    var body: some View {
        HStack(spacing: 12) {
            preview
                .frame(width: 44, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .lineLimit(2)
                    .truncationMode(.middle)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if file.isNew {
                        Text(IOSSavedFiles.newBadge)
                            .font(.caption2)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor))
                    }
                    Text(file.detail(pages: pages))
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button {
                onAction(FileAction.share, file)
            } label: {
                Image(systemName: IOSSavedFiles.symbol(FileAction.share))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Share"))
            .accessibilityIdentifier("saved.share")
            Menu {
                Button {
                    onAction(FileAction.reveal, file)
                } label: {
                    Label(IOSSavedFiles.label(FileAction.reveal), systemImage: IOSSavedFiles.symbol(FileAction.reveal))
                }
                .accessibilityIdentifier("saved.reveal")
                actionMenu
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel(Text(IOSSavedFiles.moreLabel))
            .accessibilityIdentifier("saved.more")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onAction(FileAction.open, file)
        }
        .contextMenu {
            Button {
                onAction(FileAction.share, file)
            } label: {
                Label(IOSSavedFiles.label(FileAction.share), systemImage: IOSSavedFiles.symbol(FileAction.share))
            }
            Button {
                onAction(FileAction.reveal, file)
            } label: {
                Label(IOSSavedFiles.label(FileAction.reveal), systemImage: IOSSavedFiles.symbol(FileAction.reveal))
            }
            actionMenu
        }
        .accessibilityIdentifier("saved.file")
        .task(id: file.id) {
            thumbnail = await SavedFileRow.loadThumbnail(file.url)
            if file.isPDF {
                pages = await SavedFileRow.loadPageCount(file.url)
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let thumbnail {
            Image(decorative: thumbnail, scale: 1)
                .resizable()
                .scaledToFit()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Image(systemName: file.symbol)
                .font(.title2)
                .foregroundStyle(Color.secondary)
        }
    }

    @ViewBuilder
    private var actionMenu: some View {
        ForEach(IOSSavedFiles.moreActions(lazyPrint: canLazyPrint)) { (action: FileAction) in
            Button {
                onAction(action, file)
            } label: {
                Label(IOSSavedFiles.label(action), systemImage: IOSSavedFiles.symbol(action))
            }
        }
        if file.isImage {
            Button {
                onRotate(file)
            } label: {
                Label(IOSSavedFiles.rotateLabel, systemImage: "rotate.right")
            }
            .disabled(isRotating)
            .accessibilityIdentifier("saved.rotate")
        }
        if file.isPDF {
            Button {
                onAppend(file)
            } label: {
                Label(PDFAppender.savedMenuLabel, systemImage: "doc.badge.plus")
            }
            .disabled(!canAppend)
            .accessibilityHint(Text(PDFAppender.savedMenuHint))
        }
    }

    private static func loadThumbnail(_ url: URL) async -> CGImage? {
        let task: Task<CGImage?, Never> = Task.detached(priority: .utility) { () -> CGImage? in
            IOSSavedFiles.thumbnail(of: url, maxSide: 160)
        }
        return await task.value
    }

    private static func loadPageCount(_ url: URL) async -> Int? {
        let task: Task<Int?, Never> = Task.detached(priority: .utility) { () -> Int? in
            IOSSavedFiles.pageCount(of: url)
        }
        return await task.value
    }
}
#endif
