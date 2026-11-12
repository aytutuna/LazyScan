#if os(iOS)
import LazyScanKit
import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// One page of the strip: its number and its picture; the side of a two-sided sheet ("1 · back") or the
/// page of a book's spread ("2 · left") it is; the title over it when it starts a document of a queue
/// saved as several ("Document 2"); the note on a page saving leaves out ("Separator", "Blank"); and the
/// Keep or Skip the page viewer offers.
struct PageStripCell: Identifiable {
    let id: UUID
    let number: Int
    let image: CGImage
    /// "1 · back", "2 · left"; nil for a page of neither.
    let badge: String?
    /// The badge spelled out for VoiceOver: "Sheet 1, back", "Spread 2, left page".
    let spokenBadge: String?
    /// "Document 2" over the first page of each document when the queue is saved as several; nil otherwise.
    let divider: String?
    /// "Separator", "Blank", "Skipped" for a page saving leaves out (or may); nil otherwise.
    let note: String?
    /// "Keep this page" for a page saving leaves out, "Skip this page" for one that looks blank or was kept;
    /// nil for other pages (`DocumentSplitter.toggleLabel`).
    let toggle: String?
    /// Saving leaves the page out: a separator, a blank page skipped, a page skipped by hand.
    let excluded: Bool
    /// "Start a new document here" or "Join with document 1" where the queue shows breaks and the page can take
    /// one (`DocumentSplitter.breakLabel`); nil otherwise.
    let breakAction: String?
    /// The page is in a document of a queue that shows breaks, so the document can be named.
    let canName: Bool
    /// The page starts a document after the first, in a queue saved as several.
    let startsDocument: Bool

    /// The Document menu has something to offer.
    var hasDocumentMenu: Bool {
        breakAction != nil || canName
    }

    /// The symbol beside `toggle`: a tick to keep the page, a slash to skip it.
    var toggleSymbol: String {
        excluded ? "checkmark.rectangle" : "rectangle.slash"
    }

    /// What VoiceOver reads: "Page 2, Sheet 1, back, Document 2, Separator".
    var accessibilityLabel: String {
        var parts: [String] = [String(localized: "Page \(number)")]
        if let spokenBadge { parts.append(spokenBadge) }
        if let divider { parts.append(divider) }
        if let note { parts.append(note) }
        return parts.joined(separator: ", ")
    }

    /// The queue's pages as cells, numbered from 1, under the document settings `options`.
    static func cells(_ pages: [ScannedPage], options: DocumentOptions = DocumentOptions()) -> [PageStripCell] {
        let plan: SplitPlan = DocumentSplitter.plan(pages, options: options)
        let book: [BookPageLabel?] = BookPages.labels(pages)
        let showsBreaks: Bool = DocumentSplitter.showsBreaks(plan, options: options)
        var cells: [PageStripCell] = []
        var index: Int = 0
        for page in pages {
            var badge: String? = DocumentSides.sideLabel(side: page.side, sheetIndex: page.sheetIndex)
            var spoken: String? = DocumentSides.sideName(side: page.side, sheetIndex: page.sheetIndex)
            if let bookLabel = book[index] {
                badge = bookLabel.label
                spoken = bookLabel.help
            }
            let divider: String? = DocumentSplitter.dividerTitle(plan, index)
            cells.append(PageStripCell(id: page.id, number: index + 1, image: page.image, badge: badge,
                                       spokenBadge: spoken, divider: divider,
                                       note: DocumentSplitter.badge(plan, index, page: page, options: options),
                                       toggle: DocumentSplitter.toggleLabel(plan, index, page: page, options: options),
                                       excluded: plan.pages[index].role != .content,
                                       breakAction: showsBreaks ? DocumentSplitter.breakLabel(plan, index) : nil,
                                       canName: showsBreaks && plan.pages[index].document != nil,
                                       startsDocument: divider != nil && plan.pages[index].document != 1))
            index += 1
        }
        return cells
    }
}

/// The collected pages as a grid of whole pages, two across on an iPhone held upright and more on a wider
/// screen until a pinch changes it (one to six across an iPhone, up to ten on an iPad; kept in the defaults
/// under `columnsKey`), with the queue's summary: each page with its number, its side or book badge, the
/// title of the document it starts and its note (blank, separator) on a badge over it. A tap opens the page
/// (`onOpen`), where it is turned, kept or skipped (`PageStripCell.toggle`), split or joined and deleted; a
/// press and hold starts a new document at the page or joins it to the one before, and names its document. A
/// page pressed and dragged onto another, or into the gap beside it, takes its place, and one dropped past the
/// last goes to the end (`IOSPageDrop`); VoiceOver has Move page earlier and Move page later for the same.
/// While the sheet is selecting (`selection`), a tap picks or drops the page instead, and it is not dragged.
struct PageStripView: View {
    @EnvironmentObject private var state: AppState
    /// The pages picked; nil when the grid is not selecting.
    var selection: Binding<Set<UUID>>?
    let onOpen: @MainActor (UUID) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The pages across chosen with a pinch; 0 until one is.
    @AppStorage(PageStripView.columnsKey) private var chosenColumns: Int = 0
    /// The pinch under way has taken its step.
    @State private var pinched: Bool = false
    /// A pinch is under way; back to false when it ends or the system cancels it.
    @GestureState private var pinching: Bool = false
    /// The page whose document is being named.
    @State private var namingPage: UUID?

    static let columnsKey = "pages.columns"

    /// Under the UI tests (`-demoScanner`) each tile's accessibility value is its page's id, so a test can tell
    /// pages that look alike apart.
    private static let identifiesPages: Bool = ProcessInfo.processInfo.arguments.contains(IOSLaunchOptions.demoScannerArgument)

    /// As many pages across as fit at 150 pt each within the grid's margins: two on an iPhone held upright,
    /// more on an iPad or turned sideways.
    nonisolated static func defaultColumns(width: CGFloat) -> Int {
        max(1, Int((width - 32 + 14) / 164))
    }

    /// The most pages across a pinch gives: six on an iPhone, turned sideways too, up to ten on a wide iPad.
    nonisolated static func maxColumns(width: CGFloat, pad: Bool) -> Int {
        guard pad else { return 6 }
        return min(10, max(6, Int(width / 100)))
    }

    /// The pages across at `width`: the number chosen, as far as the width allows, or the default.
    nonisolated static func columnCount(chosen: Int, width: CGFloat, pad: Bool) -> Int {
        guard chosen > 0 else { return defaultColumns(width: width) }
        return min(chosen, maxColumns(width: width, pad: pad))
    }

    /// The gap between pages, tighter as they get smaller: 14 pt up to two across, 6 pt from five.
    nonisolated static func spacing(columns: Int) -> CGFloat {
        min(14, max(6, 28 / CGFloat(columns)))
    }

    var body: some View {
        GeometryReader { (geometry: GeometryProxy) in
            grid(width: geometry.size.width)
        }
        .modifier(DocumentNameAlert(state: state, page: $namingPage))
    }

    private func grid(width: CGFloat) -> some View {
        let cells: [PageStripCell] = PageStripCell.cells(state.scannedPages, options: state.settings.document)
        let summary: String = DocumentSplitter.queueSummary(state.scannedPages, options: state.settings.document)
        let pad: Bool = UIDevice.current.userInterfaceIdiom == .pad
        let count: Int = Self.columnCount(chosen: chosenColumns, width: width, pad: pad)
        let spacing: CGFloat = Self.spacing(columns: count)
        // The gaps belong to the tiles, so a page dropped between two lands on one of them.
        let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 0, alignment: .top), count: count)
        let compact: Bool = count >= 4
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // The sheet's title already gives the count; the line stays for what it adds (documents, separators).
                if cells.isEmpty || summary != IOSCameraText.pageCount(state.scannedPages.count) {
                    Text(cells.isEmpty ? String(localized: "No pages yet") : summary)
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .accessibilityIdentifier("pages.summary")
                }
                if selection == nil && cells.count > 1 {
                    Text("Press and hold a page, then drag it to move it.")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                        .accessibilityIdentifier("pages.dragHint")
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
                    ForEach(cells) { (cell: PageStripCell) in
                        if let selection {
                            selectTile(cell, selection: selection, compact: compact, spacing: spacing)
                        } else {
                            tile(cell, compact: compact, spacing: spacing)
                        }
                    }
                }
                .dropDestination(for: String.self) { (items: [String], _: CGPoint) -> Bool in
                    dropPageAtEnd(items)
                }
            }
            .padding(16)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("pages.strip")
        }
        .simultaneousGesture(pinch(columns: count, most: Self.maxColumns(width: width, pad: pad)))
        .onChange(of: pinching) { (_: Bool, now: Bool) in
            if !now {
                pinched = false
            }
        }
    }

    /// Pinching out shows fewer, larger pages and pinching in more, smaller ones, a step a pinch.
    private func pinch(columns: Int, most: Int) -> some Gesture {
        MagnifyGesture()
            .updating($pinching) { (_: MagnifyGesture.Value, active: inout Bool, _: inout Transaction) in
                active = true
            }
            .onChanged { (value: MagnifyGesture.Value) in
                guard !pinched else { return }
                if value.magnification > 1.15 && columns > 1 {
                    pinched = true
                    show(columns: columns - 1)
                } else if value.magnification < 0.87 && columns < most {
                    pinched = true
                    show(columns: columns + 1)
                }
            }
    }

    private func show(columns: Int) {
        if reduceMotion {
            chosenColumns = columns
        } else {
            withAnimation(Animation.snappy) {
                chosenColumns = columns
            }
        }
    }

    private func tile(_ cell: PageStripCell, compact: Bool, spacing: CGFloat) -> some View {
        let pageID: UUID = cell.id
        // The tile is not a Button: a button's own press competes with the lift of a drag.
        return PageTile(cell: cell, working: state.recuttingPages.contains(pageID), compact: compact, selected: false)
            .onTapGesture {
                onOpen(pageID)
            }
            .draggable(pageID.uuidString)
            .contextMenu {
                DocumentMenuItems(state: state, cell: cell, onName: { namingPage = pageID })
            }
            .padding(.horizontal, spacing / 2)
            .padding(.vertical, (spacing + 4) / 2)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { (items: [String], _: CGPoint) -> Bool in
                dropPage(items, onto: pageID)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(cell.accessibilityLabel))
            .accessibilityValue(Text(Self.identifiesPages ? pageID.uuidString : ""))
            .accessibilityHint(Text(PageViewerText.openHint))
            .accessibilityAction { onOpen(pageID) }
            .accessibilityAction(named: Text("Move page earlier")) {
                state.movePage(id: pageID, by: -1)
            }
            .accessibilityAction(named: Text("Move page later")) {
                state.movePage(id: pageID, by: 1)
            }
            .accessibilityActions {
                if let breakAction = cell.breakAction {
                    Button(breakAction) {
                        state.toggleDocumentBreak(id: pageID)
                    }
                }
                if cell.canName {
                    Button(PageViewerText.nameDocumentLabel) {
                        namingPage = pageID
                    }
                }
            }
            .accessibilityIdentifier("page.\(cell.number)")
    }

    private func selectTile(_ cell: PageStripCell, selection: Binding<Set<UUID>>, compact: Bool,
                            spacing: CGFloat) -> some View {
        let pageID: UUID = cell.id
        let picked: Bool = selection.wrappedValue.contains(pageID)
        return Button {
            if picked {
                selection.wrappedValue.remove(pageID)
            } else {
                selection.wrappedValue.insert(pageID)
            }
        } label: {
            PageTile(cell: cell, working: state.recuttingPages.contains(pageID), compact: compact, selected: picked)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, spacing / 2)
        .padding(.vertical, (spacing + 4) / 2)
        .accessibilityLabel(Text(cell.accessibilityLabel))
        .accessibilityAddTraits(picked ? AccessibilityTraits.isSelected : [])
        .accessibilityIdentifier("page.\(cell.number)")
    }

    /// A page of the grid dropped here: it takes this page's place.
    private func dropPage(_ items: [String], onto target: UUID) -> Bool {
        guard let text = items.first, let moving = IOSPageDrop.pageID(text) else { return false }
        return IOSPageDrop.move(moving, onto: target, in: state)
    }

    /// A page of the grid dropped past the last one: it goes to the end.
    private func dropPageAtEnd(_ items: [String]) -> Bool {
        guard let text = items.first, let moving = IOSPageDrop.pageID(text), !state.isBusy else { return false }
        IOSPageSelection.move([moving], toStart: false, in: state)
        return true
    }
}

/// One page of the grid: the whole page fitted in a card of a sheet's shape, nothing of it cut off, its note
/// on a badge over its corner, a spinner while it is cut out again, and its number and badge under it. A page
/// picked in the grid's selection is dimmed a little and ticked in the other corner. Four or more across
/// (`compact`), the margins, corners and words shrink with the card.
private struct PageTile: View {
    let cell: PageStripCell
    let working: Bool
    let compact: Bool
    let selected: Bool

    private var radius: CGFloat { compact ? 6 : 10 }
    private var gap: CGFloat { compact ? 3 : 6 }

    var body: some View {
        VStack(alignment: .leading, spacing: gap) {
            if let divider = cell.divider {
                HStack(spacing: gap) {
                    if cell.startsDocument {
                        Image(systemName: "scissors")
                    }
                    Text(divider)
                        .lineLimit(1)
                }
                .font(compact ? Font.caption2.weight(.semibold) : Font.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            }
            card
            HStack(spacing: gap) {
                Text("\(cell.number)")
                    .font(compact ? Font.caption2.weight(.semibold) : Font.footnote.weight(.semibold))
                    .lineLimit(1)
                    .layoutPriority(1)
                if let badge = cell.badge {
                    Text(badge)
                        .font(compact ? Font.caption2 : Font.caption)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Color(uiColor: .secondarySystemBackground))
            .aspectRatio(PageViewerText.cardAspect, contentMode: .fit)
            .overlay {
                page
                    .padding(compact ? 3 : 8)
            }
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(Color.black.opacity(0.15))
                }
            }
            .overlay(alignment: .leading) {
                if cell.startsDocument {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.accentColor)
                        .frame(width: 3)
                        .padding(.vertical, radius / 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(compact ? Font.body : Font.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color.accentColor)
                        .padding(gap)
                }
            }
    }

    private var page: some View {
        // The previews are about 1600 px tall; drawn this small they alias without a better filter.
        Image(decorative: cell.image, scale: 1)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .background(Color.white)
            .shadow(color: Color.black.opacity(0.2), radius: 2, y: 1)
            .overlay(alignment: .topLeading) {
                if let note = cell.note {
                    Text(note)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .padding(.horizontal, compact ? 3 : 6)
                        .padding(.vertical, compact ? 1 : 3)
                        .background(Capsule().fill(Color.black.opacity(0.65)))
                        .padding(compact ? 2 : 4)
                }
            }
            .overlay {
                if working {
                    ProgressView()
                }
            }
    }
}

/// Start a new document at the page or join it to the one before, and name its document: the items of the
/// page viewer's Document menu and of a grid tile's menu. Off while the app is busy.
struct DocumentMenuItems: View {
    let state: AppState
    let cell: PageStripCell
    let onName: () -> Void

    var body: some View {
        if let breakAction = cell.breakAction {
            Button {
                state.toggleDocumentBreak(id: cell.id)
            } label: {
                Label(breakAction, systemImage: "scissors")
            }
            .disabled(state.isBusy)
            .accessibilityIdentifier("tile.document.break")
        }
        if cell.canName {
            Button(action: onName) {
                Label(PageViewerText.nameDocumentLabel, systemImage: "textformat")
            }
            .disabled(state.isBusy)
            .accessibilityIdentifier("tile.document.name")
        }
    }
}

/// The alert that names the document of the page in `page` (`AppState.setDocumentLabel`); the field starts with
/// the name it has, and an empty name removes it.
struct DocumentNameAlert: ViewModifier {
    @ObservedObject var state: AppState
    @Binding var page: UUID?
    @State private var draft: String = ""

    private var asking: Binding<Bool> {
        Binding<Bool>(get: { page != nil }, set: { (shown: Bool) in
            if !shown { page = nil }
        })
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: page) { (_: UUID?, id: UUID?) in
                if let id {
                    draft = state.documentLabel(of: id)
                }
            }
            .alert(PageViewerText.nameDocumentTitle, isPresented: asking) {
                TextField("Name", text: $draft)
                    .keyboardType(.default)
                    .textInputAutocapitalization(.sentences)
                Button("Save") {
                    if let id = page {
                        state.setDocumentLabel(id: id, label: draft)
                    }
                    page = nil
                }
                Button(PageViewerText.cancelLabel, role: .cancel) {
                    page = nil
                }
            } message: {
                Text("Goes into the file name.")
            }
    }
}

/// What is said of the pages taken out of the queue ("Page removed", "Cleared 12 pages") with the button that
/// puts them back; on the Pages sheet and on the camera's cards.
struct RemovedPagesRow: View {
    @EnvironmentObject private var state: AppState
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(state.removedTitle)
                .font(.footnote)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button(action: onUndo) {
                ViewThatFits(in: .horizontal) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .labelStyle(.titleAndIcon)
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .labelStyle(.iconOnly)
                }
                .font(.subheadline)
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(state.isBusy || state.readsQueue)
            .accessibilityLabel(Text("Undo"))
            .accessibilityHint(Text("Puts the removed pages back where they were."))
            .accessibilityIdentifier("remove.undo")
        }
        .accessibilityElement(children: .contain)
    }
}

/// The page grid in a sheet that opens at full height and can be pulled down to half (`detents`: not in
/// camera mode, whose camera rests under the sheet), opened from the scan screen's pages button
/// (`capture.pages`), with Done; a page tapped opens in the page viewer over it. Select
/// picks pages as the Photos app does: "2 Selected" as the title, Select All or Deselect All, and Cancel in
/// place of Done, with a bottom bar that turns the pages picked, shares them as pictures, moves them to the
/// start or the end, and deletes them once asked. Outside Select a bottom bar has Delete All, which empties the
/// queue once asked; the sheet then closes, as it does whenever the pages run out, unless the pages just taken
/// out can still be put back (`RemovedPagesRow` under the grid). The deletes are off while
/// a share or a send reads the pages (`AppState.readsQueue`).
struct PageStripSheet: View {
    @EnvironmentObject private var state: AppState
    var onEditSpread: (@MainActor (UUID) -> Void)?
    /// Shows the camera to take a page again once this sheet and the viewer are closed; nil in the scanner's mode.
    var onRetake: (@MainActor (UUID) -> Void)?
    let onClose: () -> Void
    var detents: Set<PresentationDetent> = [.medium, .large]
    @State private var detent: PresentationDetent = .large
    @State private var viewing: PageViewerStart?
    @State private var selecting: Bool = false
    @State private var selected: Set<UUID> = []
    @State private var asksDelete: Bool = false
    @State private var asksDeleteAll: Bool = false
    @State private var sharing: Bool = false
    @State private var share: ShareRequest?

    var body: some View {
        NavigationStack {
            PageStripView(selection: selecting ? $selected : nil, onOpen: openPage)
                .safeAreaInset(edge: .bottom) {
                    removedCard
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if selecting {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(allSelected ? PageViewerText.deselectAllLabel : PageViewerText.selectAllLabel,
                                   action: toggleAll)
                                .accessibilityIdentifier("pages.selectAll")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(PageViewerText.cancelLabel, action: stopSelecting)
                                .accessibilityIdentifier("pages.cancel")
                        }
                        ToolbarItemGroup(placement: .bottomBar) {
                            selectionActions
                        }
                    } else {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(PageViewerText.selectLabel, action: startSelecting)
                                .accessibilityIdentifier("pages.select")
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                onClose()
                            }
                            .accessibilityIdentifier("pages.done")
                        }
                        // In the bottom bar: beside Select or Done it would crowd the title on an iPhone.
                        if !state.scannedPages.isEmpty {
                            ToolbarItemGroup(placement: .bottomBar) {
                                Spacer()
                                Button(PageViewerText.deleteAllLabel, role: .destructive, action: askDeleteAll)
                                    .tint(Color.red)
                                    .disabled(state.isBusy || state.readsQueue)
                                    .accessibilityIdentifier("pages.deleteAll")
                            }
                        }
                    }
                }
        }
        .presentationDetents(detents, selection: $detent)
        // A save or a send that ends while picking takes its pages out of the queue, and out of the pick.
        .onChange(of: state.scannedPages.map { (page: ScannedPage) -> UUID in page.id }) { (_: [UUID], ids: [UUID]) in
            selected.formIntersection(ids)
        }
        .confirmationDialog(PageViewerText.deletePagesQuestion(selected.count), isPresented: $asksDelete,
                            titleVisibility: .visible) {
            Button(PageViewerText.deleteLabel, role: .destructive) {
                deleteSelected()
            }
            .accessibilityIdentifier("pages.confirmDelete")
        }
        .confirmationDialog(PageViewerText.deleteAllQuestion(state.scannedPages.count), isPresented: $asksDeleteAll,
                            titleVisibility: .visible) {
            Button(PageViewerText.deleteAllLabel, role: .destructive) {
                state.clearPages()
            }
            .accessibilityIdentifier("pages.confirmDeleteAll")
        }
        .sheet(item: $share) { (request: ShareRequest) in
            ActivityView(items: request.urls, onDone: closeShare)
        }
        .fullScreenCover(item: $viewing) { (start: PageViewerStart) in
            PageViewer(startID: start.id, onEditSpread: editSpread, onRetake: retakeAction, onClose: closeViewer)
                .environmentObject(state)
        }
        // The root's alert cannot show over a sheet.
        .modifier(ErrorAlert(state: state))
    }

    /// The pages taken out of the queue, with Undo, until the next scan or save.
    @ViewBuilder
    private var removedCard: some View {
        if state.filterPagesLeft > 0 {
            Text(PageViewerText.applyingLeft(state.filterPagesLeft))
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .accessibilityIdentifier("pages.applying")
        } else if state.canUndoRemove {
            RemovedPagesRow(onUndo: undoRemoved)
                .padding(12)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }

    private func undoRemoved() {
        state.undoRemove()
    }

    private var title: String {
        guard selecting else { return IOSCameraText.pageCount(state.scannedPages.count) }
        return PageViewerText.selectedTitle(selected.count)
    }

    private var allSelected: Bool {
        !state.scannedPages.isEmpty && state.scannedPages.allSatisfy { (page: ScannedPage) -> Bool in selected.contains(page.id) }
    }

    private func startSelecting() {
        selecting = true
        detent = .large
    }

    private func stopSelecting() {
        selecting = false
        selected = []
    }

    private func toggleAll() {
        if allSelected {
            selected = []
        } else {
            selected = Set(state.scannedPages.map { (page: ScannedPage) -> UUID in page.id })
        }
    }

    @ViewBuilder
    private var selectionActions: some View {
        let none: Bool = selected.isEmpty
        // The queue's edits do nothing while an import, a scan or a save runs.
        let blocked: Bool = none || state.isBusy
        Button(action: rotateSelected) {
            Label(PageViewerText.rotateLabel, systemImage: "rotate.right")
        }
        .disabled(blocked)
        .accessibilityIdentifier("pages.rotateSelected")
        Spacer()
        Menu {
            ForEach(CaptureFilter.displayOrder, id: \.self) { (filter: CaptureFilter) in
                Button(filter.label) {
                    state.setPagesFilter(ids: IOSPageSelection.ordered(selected, in: state.scannedPages), filter)
                }
            }
        } label: {
            Label(PageViewerText.filterLabel, systemImage: "camera.filters")
        }
        .disabled(blocked || state.readsQueue || state.filterPagesLeft > 0 || !state.recuttingPages.isEmpty || !recuttable)
        .accessibilityIdentifier("pages.filterSelected")
        Spacer()
        Button(action: shareSelected) {
            Label(PageViewerText.shareLabel, systemImage: "square.and.arrow.up")
        }
        .disabled(none || sharing)
        .accessibilityIdentifier("pages.shareSelected")
        Spacer()
        Menu {
            Button {
                IOSPageSelection.move(selected, toStart: true, in: state)
            } label: {
                Label(PageViewerText.moveToStartLabel, systemImage: "arrow.up.to.line")
            }
            Button {
                IOSPageSelection.move(selected, toStart: false, in: state)
            } label: {
                Label(PageViewerText.moveToEndLabel, systemImage: "arrow.down.to.line")
            }
        } label: {
            Label(PageViewerText.moveLabel, systemImage: "arrow.up.arrow.down")
        }
        .disabled(blocked)
        .accessibilityIdentifier("pages.moveSelected")
        Spacer()
        Button(role: .destructive, action: askDelete) {
            Label(PageViewerText.deleteLabel, systemImage: "trash")
        }
        .disabled(blocked || state.readsQueue)
        .accessibilityIdentifier("pages.deleteSelected")
    }

    private func rotateSelected() {
        for id in IOSPageSelection.ordered(selected, in: state.scannedPages) {
            state.rotatePage(id: id)
        }
    }

    private func shareSelected() {
        let ids: Set<UUID> = selected
        let format: OutputFormat = state.settings.format.imageFormatOrJPEG
        let quality: Double = state.settings.jpegQuality
        let appState: AppState = state
        sharing = true
        Task { @MainActor in
            // Turns queued behind a page swap land before the pages are read, as for a save.
            await appState.pageEditChain?.value
            let pages: [ScannedPage] = appState.scannedPages
            do {
                let urls: [URL] = try await IOSPageSelection.writeImages(ids, of: pages, format: format, jpegQuality: quality)
                share = ShareRequest(urls: urls, title: SaveActions.shareTitle(urls))
            } catch {
                appState.errorMessage = error.localizedDescription
            }
            sharing = false
        }
    }

    private func closeShare() {
        share = nil
        IOSPageSelection.clearShareFolders()
    }

    private func askDelete() {
        asksDelete = true
    }

    private func askDeleteAll() {
        asksDeleteAll = true
    }

    private func deleteSelected() {
        guard !state.isBusy, !state.readsQueue else { return }
        for id in IOSPageSelection.ordered(selected, in: state.scannedPages) {
            state.removePage(id: id)
        }
        stopSelecting()
    }

    private func openPage(_ id: UUID) {
        viewing = PageViewerStart(id: id)
    }

    private func closeViewer() {
        viewing = nil
    }

    /// Retake as the viewer is to offer it: closes the viewer, then hands the page on; nil where the sheet's
    /// owner takes no retake.
    private var retakeAction: (@MainActor (UUID) -> Void)? {
        guard onRetake != nil else { return nil }
        return { (id: UUID) -> Void in
            viewing = nil
            onRetake?(id)
        }
    }

    private func editSpread(_ id: UUID) {
        viewing = nil
        onEditSpread?(id)
    }
}
#endif
