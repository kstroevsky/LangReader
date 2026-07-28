import Foundation
import LeafReaderCore

package struct VocabularyExporter {
    package struct Record {
        package let word: String
        package let lemma: String?
        package let surfaceForm: String?
        package let answer: String
        package let location: String
        package let context: String
        package let source: String
        package let createdAt: Date

        package init(
            word: String,
            lemma: String? = nil,
            surfaceForm: String? = nil,
            answer: String,
            location: String,
            context: String,
            source: String,
            createdAt: Date
        ) {
            self.word = word
            self.lemma = lemma
            self.surfaceForm = surfaceForm
            self.answer = answer
            self.location = location
            self.context = context
            self.source = source
            self.createdAt = createdAt
        }
    }

    package struct MarkdownLabels {
        package let titleSuffix: String
        package let exportedAt: String
        package let wordCount: String
        package let location: String
        package let context: String

        package init(
            titleSuffix: String,
            exportedAt: String,
            wordCount: String,
            location: String,
            context: String
        ) {
            self.titleSuffix = titleSuffix
            self.exportedAt = exportedAt
            self.wordCount = wordCount
            self.location = location
            self.context = context
        }
    }

    package static func exportableRecords(_ records: [Record]) -> [Record] {
        records.filter { hasTrimmedText($0.word) }
    }

    package static func markdown(
        records: [Record],
        documentTitle: String,
        labels: MarkdownLabels,
        exportedAt: Date = Date(),
        answerBody: (Record) -> String
    ) -> String {
        var lines: [String] = [
            "# \(documentTitle) \(labels.titleSuffix)",
            "",
            "- \(labels.exportedAt)：\(DateFormatter.localizedString(from: exportedAt, dateStyle: .medium, timeStyle: .short))",
            "- \(labels.wordCount)：\(Set(records.map { VocabularyTextPolicy.canonicalVocabularyKey($0.lemma ?? $0.word) }).count)",
            ""
        ]
        var order: [String] = []
        var grouped: [String: [Record]] = [:]
        for record in records {
            let key = VocabularyTextPolicy.canonicalVocabularyKey(record.lemma ?? record.word)
            if grouped[key] == nil {
                order.append(key)
            }
            grouped[key, default: []].append(record)
        }
        for key in order {
            guard let group = grouped[key], let first = group.first else { continue }
            lines.append("## \(first.word)")
            lines.append("")
            for record in group {
                let form = nonEmptyText(record.surfaceForm)
                let formSuffix = form.map {
                    VocabularyTextPolicy.canonicalVocabularyKey($0) == VocabularyTextPolicy.canonicalVocabularyKey(first.word)
                        ? ""
                        : " · **\($0)**"
                } ?? ""
                lines.append("- \(labels.location)：\(record.location)\(formSuffix)")
                if hasTrimmedText(record.context) {
                    lines.append("  - \(labels.context)：\(record.context)")
                }
            }
            if let answered = group.first(where: { hasTrimmedText($0.answer) }) {
                lines.append("")
                lines.append(answerBody(answered))
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    package static func csv(records: [Record], answerBody: (Record) -> String) -> String {
        var rows = ["Word,Page,Context,Source,Created At,Answer"]
        let formatter = ISO8601DateFormatter()
        for record in records {
            rows.append([
                nonEmptyText(record.surfaceForm) ?? record.word,
                record.location,
                record.context,
                record.source,
                formatter.string(from: record.createdAt),
                answerBody(record)
            ].map(csvEscaped).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    package static func csvEscaped(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    package static func safeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return name
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    package static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    package static func nonEmptyText(_ text: String?) -> String? {
        guard let value = text.map(trimmed), !value.isEmpty else { return nil }
        return value
    }

    package static func hasTrimmedText(_ text: String) -> Bool {
        !trimmed(text).isEmpty
    }
}
