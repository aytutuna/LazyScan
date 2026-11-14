#if os(iOS)
import LazyScanKit
import SwiftUI

/// Which pages of a long PDF to import (`IOSImportSession.pageRangeRequest`): From and To fields start on
/// the whole file, and Import is off while the range is not one the file has, with the reason under the
/// fields. Cancel, or dragging the sheet away, leaves the PDF out.
struct PageRangeSheet: View {
    let request: IOSPageRangeRequest
    let onAnswer: @MainActor (ClosedRange<Int>?) -> Void

    @State private var from: String = "1"
    @State private var to: String
    @FocusState private var focus: Field?
    @Environment(\.dynamicTypeSize) private var typeSize

    private enum Field {
        case from
        case to
    }

    init(request: IOSPageRangeRequest, onAnswer: @escaping @MainActor (ClosedRange<Int>?) -> Void) {
        self.request = request
        self.onAnswer = onAnswer
        _to = State(initialValue: String(request.pageCount))
    }

    private var range: ClosedRange<Int>? {
        IOSPageRange.parse(from: from, to: to, count: request.pageCount)
    }

    private var summary: String {
        guard let range else { return IOSImportText.rangeInvalid(count: request.pageCount) }
        return IOSImportText.rangeSummary(range)
    }

    private var summaryColor: Color {
        range == nil ? Color.red : Color.secondary
    }

    private var detents: Set<PresentationDetent> {
        typeSize.isAccessibilitySize ? [.large] : [.height(300), .medium]
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(IOSImportText.pagesToImportTitle)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(IOSImportText.pagesToImportSubtitle(request.name, count: request.pageCount))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    fromField
                    toField
                }
                VStack(spacing: 8) {
                    fromField
                    toField
                }
            }
            Text(summary)
                .font(.footnote)
                .foregroundStyle(summaryColor)
                .accessibilityIdentifier("import.range.summary")
            HStack {
                Button("Cancel", role: .cancel) {
                    onAnswer(nil)
                }
                .accessibilityIdentifier("import.range.cancel")
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button(IOSImportText.importRangeLabel) {
                    confirm()
                }
                .buttonStyle(.borderedProminent)
                .disabled(range == nil)
                .accessibilityIdentifier("import.range.confirm")
            }
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .onAppear {
            focus = .from
        }
    }

    private var fromField: some View {
        HStack {
            Text(IOSImportText.fromLabel)
            TextField("", text: digits($from))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .from)
                .submitLabel(.next)
                .onSubmit {
                    focus = .to
                }
                .accessibilityLabel(Text(IOSImportText.fromAccessibilityLabel))
                .accessibilityHint(Text(IOSImportText.fromHint))
                .accessibilityIdentifier("import.range.from")
        }
    }

    private var toField: some View {
        HStack {
            Text(IOSImportText.toLabel)
            TextField("", text: digits($to))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 60)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .to)
                .submitLabel(.done)
                .onSubmit {
                    confirm()
                }
                .accessibilityLabel(Text(IOSImportText.toAccessibilityLabel))
                .accessibilityHint(Text(IOSImportText.toHint))
                .accessibilityIdentifier("import.range.to")
        }
    }

    /// `text` with anything but digits dropped as it is typed.
    private func digits(_ text: Binding<String>) -> Binding<String> {
        Binding<String>(
            get: { text.wrappedValue },
            set: { (typed: String) in
                text.wrappedValue = typed.filter { (character: Character) -> Bool in character.isASCII && character.isNumber }
            })
    }

    private func confirm() {
        guard let range else { return }
        onAnswer(range)
    }
}
#endif
