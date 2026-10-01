import Foundation

package struct VocabularyExporter {
    package struct Record {
        package let word: String
        package let language: VocabularyLanguageID?
        package let lemma: String?
        package let lexicalKey: String?
        package let partOfSpeech: VocabularyPartOfSpeech?
        package let surfaceForm: String?
        package let answer: String
        package let location: String
        package let context: String
        package let source: String
        package let createdAt: Date

        package init(
            word: String,
            language: VocabularyLanguageID? = nil,
            lemma: String? = nil,
            lexicalKey: String? = nil,
            partOfSpeech: VocabularyPartOfSpeech? = nil,
            surfaceForm: String? = nil,
            answer: String,
            location: String,
            context: String,
            source: String,
            createdAt: Date
        ) {
            self.word = word
            self.language = language
            self.lemma = lemma
            self.lexicalKey = lexicalKey
            self.partOfSpeech = partOfSpeech
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
        package let language: String
        package let lexicalIdentity: String
        package let partOfSpeech: String
        package let location: String
        package let context: String

        package init(
            titleSuffix: String,
            exportedAt: String,
            wordCount: String,
            language: String = "Language",
            lexicalIdentity: String = "Lexical identity",
            partOfSpeech: String = "Part of speech",
            location: String,
            context: String
        ) {
            self.titleSuffix = titleSuffix
            self.exportedAt = exportedAt
            self.wordCount = wordCount
            self.language = language
            self.lexicalIdentity = lexicalIdentity
            self.partOfSpeech = partOfSpeech
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
            "- \(labels.wordCount)：\(Set(records.compactMap(identityGroupingKey)).count)",
            ""
        ]
        var order: [String] = []
        var grouped: [String: [Record]] = [:]
        for record in records {
            guard let key = identityGroupingKey(record) else { continue }
            if grouped[key] == nil {
                order.append(key)
            }
            grouped[key, default: []].append(record)
        }
        for key in order {
            guard let group = grouped[key], let first = group.first else { continue }
            lines.append("## \(first.word)")
            lines.append("")
            if let language = first.language {
                lines.append("- \(labels.language)：\(language.bcp47)")
            }
            if let lexicalKey = nonEmptyText(first.lexicalKey) {
                lines.append("- \(labels.lexicalIdentity)：\(lexicalKey)")
            }
            if let partOfSpeech = first.partOfSpeech?.displayName {
                lines.append("- \(labels.partOfSpeech)：\(partOfSpeech)")
            }
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
        var rows = ["Word,Language,Lexical Key,Part of Speech,Page,Context,Source,Created At,Answer"]
        let formatter = ISO8601DateFormatter()
        for record in records {
            rows.append([
                nonEmptyText(record.surfaceForm) ?? record.word,
                record.language?.bcp47 ?? "",
                record.lexicalKey ?? "",
                record.partOfSpeech?.rawValue ?? "",
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

    private static func identityGroupingKey(_ record: Record) -> String? {
        if let lexicalKey = nonEmptyText(record.lexicalKey) {
            return "lexical|\(lexicalKey)"
        }
        let lemmaKey = VocabularyTextPolicy.canonicalVocabularyKey(record.lemma ?? record.word)
        guard !lemmaKey.isEmpty else { return nil }
        if let language = record.language {
            return "language|\(language.bcp47)|\(lemmaKey)"
        }
        return "language-unknown|\(record.source)|\(lemmaKey)"
    }
}
