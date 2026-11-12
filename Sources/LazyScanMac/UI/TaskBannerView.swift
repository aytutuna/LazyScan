#if os(macOS)
import LazyScanKit
import SwiftUI

/// The banner above the preview while a task is active or a stack is turned over by hand: the
/// task (with "Front · Back · Check" for a task of several steps, the current one stressed), what to
/// do now in one short line with the fuller guidance behind an info button (`TaskStep.help`), a way
/// back to the start screen (`onChangeTask`) and a button that
/// leaves the task, keeping its settings (without a task: that scans one side again). Fronts
/// scanned without moving on to the backs (the feeder stopped early) offer Done with fronts.
/// While the backs are due it offers keeping the fronts only and, before any back is scanned,
/// scanning more fronts; when the counts did not pair up, scanning the backs again or combining
/// the pages as they are. Twin of the Windows task banner (MainWindow.xaml).
struct TaskBannerView: View {
    @EnvironmentObject var state: AppState

    /// The active task; nil while a stack is turned over by hand without one.
    let definition: TaskDefinition?
    var onChangeTask: () -> Void

    /// Title of the banner that guides turning a stack over by hand without a task.
    static var turningOverTitle: String { String(localized: "Two-sided scanning") }

    /// The guidance behind the info button is showing.
    @State private var showHelp = false

    private var name: String { definition?.title ?? Self.turningOverTitle }

    /// The current step as the settings word it (`TaskCatalog.shownStep`).
    private var shownStep: TaskStep? {
        guard let step = state.taskFlow?.current else { return nil }
        return TaskCatalog.shownStep(step, settings: state.settings)
    }

    /// The step's short line.
    private var prompt: String { shownStep?.prompt ?? definition?.subtitle ?? DuplexMode.manual.hint }

    /// The step's fuller guidance; empty when the prompt says it all.
    private var guidance: String {
        let help: String = shownStep?.help ?? ""
        let note: String = state.taskChoicesNote
        if help.isEmpty { return note }
        return note.isEmpty ? help : help + "\n\n" + note
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: TaskSymbols.systemImage(definition?.iconKey ?? "twoSided"))
                .font(.system(size: 15))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.12)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(name)
                        .font(.headline)
                        .lineLimit(1)
                    if let flow = state.taskFlow, flow.stepCount > 1 {
                        stepIndicator(flow)
                    }
                    if let line = bookLine {
                        Text(line)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(prompt)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(Text(shownStep?.fullPrompt ?? prompt))
                    if !guidance.isEmpty {
                        Button {
                            showHelp.toggle()
                        } label: {
                            Image(systemName: "info.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("More about \(name)")
                        .accessibilityLabel(Text("More about \(name)"))
                        .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                            Text(guidance)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(14)
                                .frame(width: 300, alignment: .leading)
                        }
                    }
                }
                if state.awaitingBacks || state.canFinishFronts {
                    sidesActions
                        .padding(.top, 4)
                }
                // The back of a card with nothing printed on it may be left out. (The backs of a stack
                // turned over by hand are left out with Keep Fronts Only.)
                if state.canSkipStep, let step = state.taskFlow?.current {
                    Button(step.id == IdCardSteps.backStepID ? IdCardSteps.skipBackLabel : String(localized: "Skip \(step.title.localizedLowercase)")) {
                        state.skipStep()
                    }
                        .controlSize(.small)
                        .disabled(state.isBusy)
                        .help("Nothing is printed on the back: save the front only")
                        .padding(.top, 4)
                }
            }
            Spacer(minLength: 8)
            Button {
                onChangeTask()
            } label: {
                Label("Change Task", systemImage: "square.grid.2x2")
            }
            .help("Pick another task")
            Button {
                if definition != nil {
                    // Leaving the ID card task with a side scanned asks first.
                    let appState = state
                    appState.leaveIdCard { appState.exitTask() }
                } else {
                    state.scanOneSideOnly()
                }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            // Not while a scan runs: its result belongs to the task's steps.
            .disabled(state.isBusy)
            .help(exitHelp)
            .accessibilityLabel(exitLabel)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(bannerLabel)
    }

    /// With sides by hand the task takes them along (`exitTask()`), so not every setting stays.
    private var exitHelp: String {
        if definition == nil { return String(localized: "Scan one side of each sheet") }
        return state.isTurningOverByHand ? String(localized: "Leave the task") : String(localized: "Leave the task (settings stay)")
    }

    private var exitLabel: String {
        definition != nil ? String(localized: "Leave the task") : String(localized: "Scan one side only")
    }

    private var bannerLabel: String {
        guard definition != nil else { return name }
        let task: String = String(localized: "Task: \(name)")
        guard bookLine != nil else { return task }
        let order: String = BookPages.readingOrderLine(rightToLeft: state.settings.taskOptions.bookRightToLeft)
        return String(localized: "Task: \(name), \(order)")
    }

    /// The Book task's reading order, and its rotation when it turns the pages: "Reads right to left ·
    /// Rotated 90° clockwise". Nothing while the facing pages are not split.
    private var bookLine: String? {
        let split: Bool = state.settings.document.splitFacingPages && BookPages.scansOneSide(state.settings)
        guard definition?.task == .book, split else { return nil }
        var line: String = BookPages.readingOrderLine(rightToLeft: state.settings.taskOptions.bookRightToLeft)
        let turns: Int = BookSplitter.normalizedTurns(state.settings.taskOptions.bookRotationQuarterTurns)
        if let rotated = Self.rotatedPhrase(turns) {
            line += " \u{00B7} " + rotated
        }
        return line
    }

    private static func rotatedPhrase(_ turns: Int) -> String? {
        switch turns {
        case 1: return String(localized: "Rotated 90° clockwise")
        case 2: return String(localized: "Rotated 180°")
        case 3: return String(localized: "Rotated 90° counterclockwise")
        default: return nil
        }
    }

    /// "Front · Back · Check": each step in a word, the current one bold in the accent color; VoiceOver
    /// reads "ID card, step 1 of 3: front side".
    private func stepIndicator(_ flow: TaskFlow) -> some View {
        var line: Text = Text("")
        for (index, step) in flow.steps.enumerated() {
            if index > 0 {
                let separator: Text = Text(" \u{00B7} ").foregroundStyle(Color.secondary)
                line = line + separator
            }
            let word: Text = Text(step.word)
            if index == flow.stepIndex {
                let stressed: Text = word.bold().foregroundStyle(Color.accentColor)
                line = line + stressed
            } else {
                let plain: Text = word.foregroundStyle(Color.secondary)
                line = line + plain
            }
        }
        let current: String = flow.current?.title.localizedLowercase ?? ""
        return line
            .font(.callout)
            .lineLimit(1)
            .accessibilityLabel(Text("\(name), step \(flow.stepIndex + 1) of \(flow.stepCount): \(current)"))
    }

    /// Moving on from the fronts, the backs' choices, and the count mismatch ("3 fronts but 2
    /// backs") when there is one.
    private var sidesActions: some View {
        VStack(alignment: .leading, spacing: 4) {
            if state.awaitingBacks, let mismatch = state.sidesMismatch {
                Label("\(mismatch). Scan the rest of the back sides, scan them again, or combine the pages as they are.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if state.canFinishFronts {
                    Button("Done with fronts") { state.finishFronts() }
                        .help("Every front side is scanned: turn the stack over and scan the back sides")
                }
                if state.awaitingBacks && state.sidesMismatch != nil {
                    Button("Combine Anyway") { state.combineSidesAnyway() }
                        .help("Put the pages in order as they are; the extra pages go at the end")
                    Button("Scan Back Sides Again") { state.scanBacksAgain() }
                        .help("Remove the back sides scanned so far and scan them again")
                }
                if state.canScanMoreFronts {
                    Button("Scan More Fronts") { state.scanMoreFronts() }
                        .help("The stack did not fit in the feeder: scan the fronts of the other sheets before turning it over")
                }
                if state.awaitingBacks {
                    Button("Keep Fronts Only") { state.keepFrontsOnly() }
                        .help("Leave out the back sides: the fronts stay as they are")
                }
            }
            .controlSize(.small)
            .disabled(state.isBusy)
        }
    }
}
#endif
