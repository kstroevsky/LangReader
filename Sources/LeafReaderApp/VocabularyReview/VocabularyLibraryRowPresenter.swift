import Foundation
import LeafReaderCore

/// The text on one row of the vocabulary library's word list.
///
/// These rules lived inside an `NSTableCellView`, so the answer sanitising in
/// particular — which decides whether a reader sees their definition or the
/// word's raw dictionary tags — could not be checked without building a table.
enum VocabularyLibraryRowPresenter {
    /// "108x · 1 file" — how often the word was met, and across how many
    /// documents.
    static func metadataText(occurrenceCount: Int, sourceCount: Int) -> String {
        let sourceText = sourceCount == 1
            ? AppText.localized("1 个文件", "1 file")
            : AppText.localized("\(sourceCount) 个文件", "\(sourceCount) files")
        return AppText.localized(
            "\(occurrenceCount) 处 · \(sourceText)",
            "\(occurrenceCount)x · \(sourceText)"
        )
    }

    /// The one-line definition preview.
    ///
    /// Answers arrive as multi-line markdown with dictionary tags appended, and
    /// a row is a single line — so tags are stripped and whitespace collapsed.
    /// A word with no usable answer says so rather than showing a blank row,
    /// which would look like a loading failure.
    static func answerPreview(_ answer: String) -> String {
        let cleaned = VocabularyAnswerSanitizer.removingTrailingTags(from: answer)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty
            ? AppText.localized("没有释义", "No definition yet")
            : cleaned
    }
}
