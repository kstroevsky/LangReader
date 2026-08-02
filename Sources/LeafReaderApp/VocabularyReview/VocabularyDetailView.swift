import SwiftUI
import Observation
import LeafReaderCore

/// State behind the vocabulary library's detail pane.
///
/// Holds the selected record and the two things that narrow what it shows — the
/// source-document filter (from the list's popup) and the inflected-form tab —
/// plus the actions the pane fires. The grouping and filtering rules come from
/// `VocabularyOccurrenceGrouping`, already extracted and tested; this only wires
/// them to the view.
///
/// The two runs of rich text — the dictionary answer and each occurrence's
/// context with its surface form emphasised — are produced by the existing
/// AppKit renderers (injected as closures) and bridged to SwiftUI, so the pane
/// reads identically to the one it replaces without re-implementing markdown.
@Observable
final class VocabularyDetailModel {
    var record: VocabularyLibraryRecord? {
        didSet {
            // A form tab belongs to one word; carrying it to the next would
            // hide occurrences of a word that has no such form.
            if record?.id != oldValue?.id { formFilter = nil }
        }
    }
    /// The document the list is filtered to, or nil for all documents.
    var sourcePath: String?
    var theme: ReaderTheme = ReaderTheme.selected
    /// Canonical key of the form tab in effect, or nil for "All".
    var formFilter: String?

    @ObservationIgnored var onCopy: (() -> Void)?
    @ObservationIgnored var onRemove: (() -> Void)?
    @ObservationIgnored var onOpenSource: ((VocabularyLibraryOccurrence) -> Void)?
    /// Renders the dictionary answer markdown. Injected because it lives in the
    /// AppKit renderer; the view bridges the result to SwiftUI.
    @ObservationIgnored var makeAnswer: ((String) -> NSAttributedString)?
    /// Renders one occurrence's context with the surface form emphasised.
    @ObservationIgnored var makeContext: ((String, String) -> NSAttributedString)?

    /// Occurrences after the source-document filter.
    var occurrences: [VocabularyLibraryOccurrence] {
        guard let record else { return [] }
        guard let sourcePath else { return record.occurrences }
        return record.occurrences.filter { $0.documentURL.standardizedFileURL.path == sourcePath }
    }

    var formGroups: [OccurrenceFormGroup] {
        guard let record else { return [] }
        return VocabularyOccurrenceGrouping.formGroups(record: record, occurrences: occurrences)
    }

    /// The form filter, ignored if it names a form this word (in this source) no
    /// longer has — so a stale tab shows everything rather than nothing.
    var effectiveFormFilter: String? {
        guard let filter = formFilter, formGroups.contains(where: { $0.key == filter }) else { return nil }
        return filter
    }

    var visibleOccurrences: [VocabularyLibraryOccurrence] {
        guard let record, let filter = effectiveFormFilter else { return occurrences }
        return occurrences.filter {
            VocabularyTextPolicy.canonicalVocabularyKey($0.surfaceForm ?? record.word) == filter
        }
    }

    var metadataText: String {
        guard let record else { return "" }
        return [
            record.dictionaryTags,
            record.dictionaryFrequency.map { AppText.localized("词频 #\($0)", "Frequency #\($0)") },
            record.forms.count > 1
                ? AppText.localized("\(record.forms.count) 个词形", "\(record.forms.count) forms")
                : nil,
            AppText.localized("\(occurrences.count) 个出处", "\(occurrences.count) occurrences")
        ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "  ·  ")
    }

    var formsLine: String? {
        guard let record else { return nil }
        let hasInformativeLabel = record.forms.contains { $0.label?.isInformative == true }
        guard record.forms.count > 1 || hasInformativeLabel else { return nil }
        let formsText = record.forms.map(\.displayText).joined(separator: "  ·  ")
        return AppText.localized("词形：\(formsText)", "Forms: \(formsText)")
    }

    var answer: AttributedString? {
        guard let record, let makeAnswer,
              !record.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return AttributedString(makeAnswer(String(record.answer.prefix(2400))))
    }

    func context(for occurrence: VocabularyLibraryOccurrence) -> AttributedString {
        let text = occurrence.context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return AttributedString(AppText.localized("没有可用的上下文", "No context available"))
        }
        let word = occurrence.surfaceForm ?? record?.word ?? ""
        guard let makeContext else { return AttributedString(text) }
        return AttributedString(makeContext(text, word))
    }
}

/// The vocabulary library's detail pane — the last AppKit view in this screen,
/// now declarative SwiftUI. The list beside it is already SwiftUI, so the whole
/// window is state-driven.
struct VocabularyDetailView: View {
    @Bindable var model: VocabularyDetailModel

    private var primary: Color { Color(nsColor: model.theme.vocabularyPrimaryTextColor) }
    private var secondary: Color { Color(nsColor: model.theme.vocabularySecondaryTextColor) }
    private var accent: Color { Color(nsColor: model.theme.vocabularyAccentColor) }

    var body: some View {
        ScrollView {
            if model.record == nil {
                Text(AppText.localized("从左侧选择一个单词查看详情。", "Select a word on the left to see its details."))
                    .font(.system(size: 15))
                    .foregroundStyle(secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 40)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    Text(model.metadataText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(secondary)
                    if let forms = model.formsLine {
                        Text(forms)
                            .font(.system(size: 12))
                            .foregroundStyle(secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let answer = model.answer {
                        Text(answer)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Divider()
                    formTabs
                    Text(AppText.localized("出处与上下文", "Occurrences & context"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(primary)
                    occurrences
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
                .padding(.top, 4)
                .padding(.bottom, 18)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(model.record?.word ?? "")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(AppText.localized("复制", "Copy")) { model.onCopy?() }
                .accessibilityIdentifier(VocabularyLibraryAccessibility.copyButton)
            Button(AppText.localized("删除", "Remove")) { model.onRemove?() }
                .tint(.red)
                .accessibilityIdentifier(VocabularyLibraryAccessibility.removeButton)
        }
    }

    @ViewBuilder
    private var formTabs: some View {
        let groups = model.formGroups
        if groups.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    tab(title: AppText.localized("全部（\(model.occurrences.count)）", "All (\(model.occurrences.count))"),
                        isSelected: model.effectiveFormFilter == nil) {
                        model.formFilter = nil
                    }
                    ForEach(groups, id: \.key) { group in
                        tab(title: "\(group.surface) (\(group.count))",
                            isSelected: model.effectiveFormFilter == group.key) {
                            model.formFilter = group.key
                        }
                        .help(group.label?.displayName ?? group.surface)
                    }
                }
            }
        }
    }

    private func tab(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isSelected ? accent.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .foregroundStyle(isSelected ? accent : secondary)
        }
        .buttonStyle(.plain)
    }

    private var occurrences: some View {
        ForEach(Array(model.visibleOccurrences.enumerated()), id: \.offset) { _, occurrence in
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Button {
                        model.onOpenSource?(occurrence)
                    } label: {
                        Label(occurrence.documentTitle, systemImage: "doc.text")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(accent)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(VocabularyLibraryAccessibility.sourceButton)
                    .help(AppText.localized(
                        "打开 \(occurrence.documentURL.path) · \(occurrence.location)",
                        "Open \(occurrence.documentURL.path) · \(occurrence.location)"
                    ))
                    Spacer(minLength: 8)
                    Text(occurrence.location)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                }
                Text(model.context(for: occurrence))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: model.theme.vocabularyCardBackgroundColor),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(nsColor: model.theme.vocabularyCardBorderColor), lineWidth: 1)
            )
        }
    }
}
