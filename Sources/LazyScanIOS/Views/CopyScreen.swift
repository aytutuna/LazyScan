#if os(iOS)
import LazyScanKit
import CoreGraphics
import SwiftUI
import UIKit

/// The photocopy's screen, full screen once its pages are in (`AppState.copyPages`, I16): the first page
/// large, paged through with "Page 2 of 5" under it when several, then Copies, Fit to page (on and
/// fixed, with why, when a page has no known size), Also save a PDF, the printer the copy goes to and the status while it prints;
/// Print shows AirPrint's printer picker, Copy again prints on the printer picked last without it, and
/// Add page closes the screen to shoot another page into the copy, which comes back with it; Discard asks, then lets
/// the pages go and closes the screen (Close, for the queue's pages printed from Options, which stay in
/// the queue; the screen is then Print, with Print again, and no Add page). It stays open after printing,
/// for another copy, with Done instead of Discard and no Add page. It shows the error alert itself, since the root's cannot show over it.
struct CopyScreen: View {
    @ObservedObject var model: IOSCopyModel
    @EnvironmentObject private var state: AppState
    @State private var asksDiscard: Bool = false
    @State private var shown: Int = 0
    /// Closes the screen with the pages kept, so the camera can take another.
    let onAddPage: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                pagesArea
                Divider()
                footer
            }
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if state.copyIsOfQueue {
                        Button(IOSCopyText.closeLabel) {
                            model.discard()
                        }
                        .disabled(!model.canAct)
                        .accessibilityIdentifier("copy.discard")
                    } else if model.exitIsDone {
                        Button(IOSCopyText.doneLabel) {
                            model.discard()
                        }
                        .disabled(!model.canAct)
                        .accessibilityIdentifier("copy.discard")
                    } else {
                        Button(IOSCopyText.discardLabel, role: .destructive) {
                            asksDiscard = true
                        }
                        .disabled(!model.canAct)
                        .accessibilityHint(Text(IOSCopyText.discardHint))
                        .accessibilityIdentifier("copy.discard")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    if state.isBusy {
                        ProgressView()
                    }
                }
            }
        }
        .alert(IOSCopyText.discardTitle, isPresented: $asksDiscard) {
            Button(IOSCopyText.discardLabel, role: .destructive) {
                model.discard()
            }
            .accessibilityIdentifier("copy.confirmDiscard")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(IOSCopyText.discardLine)
        }
        .modifier(ErrorAlert(state: state))
    }

    /// The page on show, kept inside the pages held (Add page brings the screen back with more).
    private var shownIndex: Int {
        min(shown, max(state.copyPages.count - 1, 0))
    }

    private var pagesArea: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            if state.copyPages.count > 1 {
                VStack(spacing: 8) {
                    pager
                    if let caption = model.pageCaption(shownIndex) {
                        Text(caption)
                            .font(.footnote)
                            .foregroundStyle(Color.secondary)
                            .accessibilityIdentifier("copy.pageCaption")
                    }
                }
                .padding(.bottom, 8)
            } else if let page = state.copyPages.first {
                SharpPageImage(page: page)
                    .padding(12)
                    .accessibilityLabel(Text(model.pageName))
                    .accessibilityIdentifier("copy.image")
            }
        }
    }

    private var pager: some View {
        let count: Int = state.copyPages.count
        return TabView(selection: shownBinding) {
            ForEach(state.copyPages.indices, id: \.self) { (index: Int) in
                SharpPageImage(page: state.copyPages[index])
                    .padding(12)
                    .accessibilityLabel(Text(model.pageName))
                    .accessibilityValue(Text(IOSCopyText.positionOfCount(index + 1, count)))
                    .accessibilityIdentifier("copy.image")
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .accessibilityAdjustableAction { (direction: AccessibilityAdjustmentDirection) in
            let next: Int = direction == .increment ? shownIndex + 1 : shownIndex - 1
            shown = min(max(next, 0), count - 1)
        }
    }

    private var shownBinding: Binding<Int> {
        Binding<Int>(get: { shownIndex }, set: { (index: Int) in shown = index })
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Stepper(value: copies, in: 1...PrintCopies.maxCount) {
                Text(IOSCopyText.copiesTitle(model.copies))
            }
            .disabled(state.isBusy)
            .accessibilityIdentifier("copy.copies")
            Toggle(IOSCopyText.fitLabel, isOn: fit)
                .disabled(model.fitIsForced || state.isBusy)
                .accessibilityHint(Text(IOSCopyText.fitHint))
                .accessibilityIdentifier("copy.fit")
            if model.fitIsForced {
                Label(PrintText.realSizeUnavailable, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("copy.fitReason")
            }
            // The queue's pages are saved by its own Save (After saving's Print saves them once this closes).
            if !state.copyIsOfQueue {
                Toggle(IOSCopyText.pdfLabel, isOn: alsoPDF)
                    .disabled(state.isBusy)
                    .accessibilityHint(Text(IOSCopyText.pdfHint))
                    .accessibilityIdentifier("copy.pdf")
            }
            Label(model.printerLine, systemImage: "printer")
                .font(.footnote)
                .foregroundStyle(Color.secondary)
                .accessibilityIdentifier("copy.printer")
            Text(state.statusMessage)
                .font(.footnote)
                .foregroundStyle(Color.secondary)
                .lineLimit(2)
                .accessibilityIdentifier("copy.status")
            if model.offersAddPage {
                Button {
                    onAddPage()
                } label: {
                    Label(IOSCopyText.addPageLabel, systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!model.canAct)
                .accessibilityHint(Text(IOSCopyText.addPageHint))
                .accessibilityIdentifier("copy.addPage")
            }
            HStack(spacing: 12) {
                if let printer = model.printerName {
                    Button {
                        model.printAgain()
                    } label: {
                        Label(model.againLabel, systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!model.canAct)
                    .accessibilityHint(Text(IOSCopyText.againHint(printer)))
                    .accessibilityIdentifier("copy.again")
                }
                Button {
                    model.print()
                } label: {
                    Label(IOSCopyText.printLabel, systemImage: "printer")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canAct)
                .accessibilityHint(Text(IOSCopyText.printHint))
                .accessibilityIdentifier("copy.print")
            }
        }
        .padding(16)
    }

    private var copies: Binding<Int> {
        let copyModel: IOSCopyModel = model
        return Binding<Int>(get: { copyModel.copies },
                            set: { (count: Int) in copyModel.setCopies(count) })
    }

    private var fit: Binding<Bool> {
        let copyModel: IOSCopyModel = model
        return Binding<Bool>(get: { copyModel.fitsToPage },
                             set: { (on: Bool) in copyModel.setFitsToPage(on) })
    }

    private var alsoPDF: Binding<Bool> {
        let copyModel: IOSCopyModel = model
        return Binding<Bool>(get: { copyModel.alsoSavesPDF },
                             set: { (on: Bool) in copyModel.setAlsoSavesPDF(on) })
    }
}
#endif
