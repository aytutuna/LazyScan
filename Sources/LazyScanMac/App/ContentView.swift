#if os(macOS)
import LazyScanKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var state: AppState

    private enum DetailTab: Hashable {
        case start
        case scanner
        case scans
        case saved
    }

    @State private var detailTab: DetailTab = .scanner
    @State private var showInspector = true
    /// The first appearance picked the opening view: the start screen on a first run, the
    /// scanner view (with the task the user had last) afterwards.
    @State private var choseOpeningView = false
    /// Photo files are dragged over the scanner view: it says where they go.
    @State private var dropTargeted = false
    @State private var openedPhotos: [URL] = []

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            // The tab switcher lives in the content, not the toolbar: toolbar
            // `.principal` items merge the title bar on newer macOS and push the
            // sidebar under the traffic-light buttons.
            VStack(spacing: 0) {
                HStack {
                    Picker("View", selection: $detailTab) {
                        Text("Start").tag(DetailTab.start)
                        Text("Scanner").tag(DetailTab.scanner)
                        Text("Scans").tag(DetailTab.scans)
                        Text("Saved").tag(DetailTab.saved)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 360)
                    Spacer()
                    if detailTab == .scanner {
                        Button {
                            showInspector.toggle()
                        } label: {
                            Label("Scan Settings", systemImage: "sidebar.trailing")
                        }
                        .labelStyle(.iconOnly)
                        .help("Show or hide the scan settings")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
                // The corner editor of an imported photo whose page was not found clearly; closing it skips
                // the photo. On the tab bar, which every tab shows, so it opens whichever tab is selected
                // (the import waits for its answer).
                .sheet(item: Binding(get: { state.cornerReview },
                                     set: { if $0 == nil { state.answerCorners(.skip) } })) { request in
                    PhotoCornersEditorView(request: request)
                        .environmentObject(state)
                }
                Divider()
                // A `.lsdoc` opened by hand, on every tab (AppState+Package.swift).
                if let package = state.pendingPackage {
                    PackageBannerView(package: package)
                    Divider()
                }
                // A paired phone's document added to the queue, or waiting for it (AppState+CompanionHost.swift).
                if let message = state.phoneBarMessage {
                    PhoneBarView(message: message)
                    Divider()
                }
                switch detailTab {
                case .start:
                    startDetail
                case .scanner:
                    scannerDetail
                case .scans:
                    scansDetail
                case .saved:
                    savedDetail
                }
            }
            // The ID card's review, on the detail rather than next to the photo review's sheet.
            .sheet(isPresented: $state.showIdCardReview) {
                IdCardReviewView()
                    .environmentObject(state)
            }
            // Leaving the ID card task (or picking a task, preset or scanner) with a side scanned and not
            // saved asks first (`AppState.leaveIdCard`).
            .alert("Discard the ID card?",
                   isPresented: Binding(
                       get: { state.pendingIdCardLeave != nil },
                       set: { if !$0 { state.pendingIdCardLeave = nil } }),
                   presenting: state.pendingIdCardLeave) { leave in
                Button("Discard", role: .destructive) { state.discardIdCard(andThen: leave) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("The ID card has not been saved. Its scanned sides will be discarded.")
            }
        }
        .sheet(isPresented: $state.showPhotoReview) {
            PhotoReviewView()
                .environmentObject(state)
        }
        // The error alert, held back while a review sheet is up: the sheet shows it itself.
        .errorNoticeAlert(enabled: !state.showPhotoReview && !state.showIdCardReview)
        // Below this the layout cannot stay usable; the inspector adds its own
        // width requirement only while shown.
        .frame(minWidth: 700, minHeight: 560)
        // Pictures from File > Import from iPhone or iPad (Continuity Camera) become pages as dropped
        // photo files do.
        .importsItemProviders([.image]) { providers in
            state.importFromDevice(providers)
        }
        // A `.lsdoc` opened from the Finder is offered on the banner, in this window rather than a new one;
        // photos opened with Lazy Scan become pages. Files opened together arrive one call each, so they
        // are gathered for a moment and imported as one batch.
        .onOpenURL { url in
            guard url.isFileURL else { return }
            if url.pathExtension.lowercased() == CompanionPackage.fileExtension {
                Task { await state.openPackage(at: url) }
                return
            }
            openedPhotos.append(url)
            guard openedPhotos.count == 1 else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                let urls = openedPhotos
                openedPhotos = []
                state.importPhotos(urls)
            }
        }
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onAppear {
            guard !choseOpeningView else { return }
            choseOpeningView = true
            if state.isFirstRun { detailTab = .start }
        }
        .focusedSceneValue(\.scanSettingsShown, settingsBinding)
        .task { state.startWithLastScanner() }
    }

    /// Offered to View > Show Scan Settings only while the Scanner tab, which has the column, is up.
    private var settingsBinding: Binding<Bool>? {
        guard detailTab == .scanner else { return nil }
        return $showInspector
    }

    private var scannerDetail: some View {
        // The controls live in a native inspector panel: it manages its own width,
        // counts into the window's minimum size (so nothing gets clipped in small
        // windows), is user-resizable, and can be toggled to give the page preview
        // the whole window.
        VStack(spacing: 0) {
            if state.activeTaskDefinition != nil || state.isTurningOverByHand {
                TaskBannerView(definition: state.activeTaskDefinition, onChangeTask: { detailTab = .start })
                Divider()
            }
            PreviewCanvasView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !state.scannedPages.isEmpty || state.appendTarget != nil {
                Divider()
                PagesStripView()
            }
            ScanActionBar(showsScanButtons: true)
            Divider()
            StatusBarView()
        }
        // Photos of documents dropped on the scanner view become pages (AppState+Import.swift), a
        // `.lsdoc` is offered on the banner (photos dropped with it are imported as well, so such a drop
        // is refused while photos cannot be taken); other drops are refused.
        .dropDestination(for: URL.self) { urls, _ in
            let hasPhotos = !PhotoImport.photoFiles(urls.map(\.path)).isEmpty
            if let package = urls.first(where: { $0.pathExtension.lowercased() == CompanionPackage.fileExtension }) {
                guard !hasPhotos || state.canImportPhotos else { return false }
                Task { await state.openPackage(at: package) }
                if hasPhotos { state.importPhotos(urls) }
                return true
            }
            // Photos dropped where the settings do not import them are taken too, so importPhotos can say why.
            let takes: Bool = state.canImportPhotos || (!state.isBusy && !PhotoImport.isOffered(state.settings))
            guard hasPhotos, takes else { return false }
            state.importPhotos(urls)
            return true
        } isTargeted: { targeted in
            dropTargeted = targeted
        }
        .overlay {
            if dropTargeted && state.canImportPhotos {
                Text(PhotoImport.dropOverlay)
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .allowsHitTesting(false)
            }
        }
        .inspector(isPresented: $showInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 280, ideal: 330, max: 430)
        }
    }

    /// A scan started on the Scanner tab goes on when another tab is up: its progress and Cancel stay in reach.
    @ViewBuilder
    private var runningScanBar: some View {
        if state.isBusy {
            ScanActionBar(showsScanButtons: false)
        }
    }

    private var startDetail: some View {
        VStack(spacing: 0) {
            TaskStartView(onOpenScanner: { detailTab = .scanner })
            runningScanBar
            Divider()
            StatusBarView()
        }
    }

    private var scansDetail: some View {
        VStack(spacing: 0) {
            ScanHistoryView()
            runningScanBar
            Divider()
            StatusBarView()
        }
    }

    private var savedDetail: some View {
        VStack(spacing: 0) {
            SavedFilesView()
            runningScanBar
            Divider()
            StatusBarView()
        }
    }
}
#endif
