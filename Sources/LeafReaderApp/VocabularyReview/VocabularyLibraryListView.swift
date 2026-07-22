import SwiftUI
import Observation

/// State behind the vocabulary library's word list.
///
/// Holds only what the list shows and which row is selected. Filtering and
/// sorting stay in `VocabularyLibraryFilter`; the detail pane stays AppKit and
/// is driven by `onSelect`.
@Observable
final class VocabularyLibraryListModel {
    private(set) var records: [VocabularyLibraryRecord] = []
    var theme: ReaderTheme = ReaderTheme.selected
    /// The selected record's id. Setting it is what the detail pane reacts to.
    var selectedID: String? {
        didSet {
            guard selectedID != oldValue else { return }
            onSelect?(selectedID)
        }
    }

    @ObservationIgnored var onSelect: ((String?) -> Void)?

    /// Replaces the visible rows and the selection together.
    ///
    /// Selection is set without notifying: the caller already knows which row it
    /// chose, and re-entering `onSelect` here would rebuild the detail pane a
    /// second time on every keystroke in the search field.
    func apply(records: [VocabularyLibraryRecord], selectedID: String?) {
        self.records = records
        if self.selectedID != selectedID {
            let handler = onSelect
            onSelect = nil
            self.selectedID = selectedID
            onSelect = handler
        }
    }

    var selectedRecord: VocabularyLibraryRecord? {
        guard let selectedID else { return nil }
        return records.first { $0.id == selectedID }
    }
}

/// The library's word list.
///
/// Replaces an `NSTableView` whose cells were rebuilt by hand on every reload.
/// The detail pane beside it is still AppKit — this migrates the list only, so
/// the two halves can move independently.
struct VocabularyLibraryListView: View {
    @Bindable var model: VocabularyLibraryListModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(model.records, id: \.id) { record in
                        row(for: record)
                            .id(record.id)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollContentBackground(.hidden)
            .onChange(of: model.selectedID) { _, id in
                // The library can be opened focused on a specific word, which
                // may be far down the list.
                guard let id else { return }
                withAnimation(.none) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func row(for record: VocabularyLibraryRecord) -> some View {
        let isSelected = record.id == model.selectedID
        return Button {
            model.selectedID = record.id
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(record.word)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(nsColor: model.theme.vocabularyPrimaryTextColor))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(VocabularyLibraryRowPresenter.metadataText(
                        occurrenceCount: record.occurrences.count,
                        sourceCount: record.sourceCount
                    ))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(nsColor: model.theme.vocabularySecondaryTextColor))
                    .lineLimit(1)
                    .frame(maxWidth: 128, alignment: .trailing)
                }
                Text(VocabularyLibraryRowPresenter.answerPreview(record.answer))
                    .font(.system(size: 12))
                    .foregroundStyle(Color(nsColor: model.theme.vocabularySecondaryTextColor))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? Color(nsColor: model.theme.accentColor).opacity(0.16)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(VocabularyLibraryAccessibility.row)
        .accessibilityLabel(record.word)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
