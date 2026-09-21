import Foundation
import NaturalLanguage
import LeafReaderCore

struct VocabularyPreparationDocumentIdentity: Equatable, Sendable {
    let documentID: String
    let loadGeneration: Int
    let webPlainTextGeneration: Int?
}

struct VocabularyPreparationSourceSnapshot: Sendable {
    let identity: VocabularyPreparationDocumentIdentity
    let kind: ReaderDocumentKind
    let language: NLLanguage
    let texts: [String]
    let index: VocabularyDocumentLemmaIndex
}

enum VocabularyPreparationSourceError: LocalizedError {
    case noDocument
    case textNotReady
    case unsupportedLanguage
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noDocument:
            AppText.localized("没有打开的文档。", "No document is open.")
        case .textNotReady:
            AppText.localized("文档文本仍在载入。请稍后重试。", "Document text is still loading. Please retry shortly.")
        case .unsupportedLanguage:
            AppText.localized("此版本只支持英语和德语文档。", "This version supports English and German documents only.")
        case .cancelled:
            AppText.localized("词汇准备已取消。", "Vocabulary preparation was cancelled.")
        }
    }
}

@MainActor
protocol VocabularyPreparationDocumentSource: AnyObject {
    var vocabularyPreparationIdentity: VocabularyPreparationDocumentIdentity? { get }
    func vocabularyPreparationSnapshot(requestedLanguage: NLLanguage?) async throws -> VocabularyPreparationSourceSnapshot
    func acceptsVocabularyPreparationIdentity(_ identity: VocabularyPreparationDocumentIdentity) -> Bool
}

struct VocabularyPreparedDefinition: Sendable {
    let markdown: String
    let tags: String?
    let frequency: Int?
}

protocol VocabularyPreparationDefinitionProviding: Sendable {
    func definition(
        for candidate: DocumentVocabularyCandidate,
        languageCode: String,
        context: String
    ) async throws -> VocabularyPreparedDefinition
}

struct LiveVocabularyPreparationDefinitionProvider: VocabularyPreparationDefinitionProviding {
    func definition(
        for candidate: DocumentVocabularyCandidate,
        languageCode: String,
        context: String
    ) async throws -> VocabularyPreparedDefinition {
        if languageCode == NLLanguage.german.rawValue {
            let entry = try await GermanWiktionaryDictionary.shared.lookup(candidate.displayLemma)
            return VocabularyPreparedDefinition(
                markdown: entry.markdown,
                tags: entry.metadata.tags,
                frequency: candidate.generalFrequencyRank
            )
        }
        return await Task.detached(priority: .userInitiated) {
            let lookup = LocalDictionaryLookupService.shared.dictionaryAnswer(
                for: candidate.displayLemma,
                context: context
            )
            return VocabularyPreparedDefinition(
                markdown: lookup?.markdown
                    ?? AppText.localized("本地词典中没有释义。", "No local definition is available."),
                tags: lookup?.metadata.tags,
                frequency: candidate.generalFrequencyRank ?? lookup?.metadata.frequency
            )
        }.value
    }
}

/// Used only by the opt-in GUI performance/smoke harness. It keeps German
/// preparation deterministic and guarantees that automation never contacts
/// Wiktionary.
struct FixtureVocabularyPreparationDefinitionProvider: VocabularyPreparationDefinitionProviding {
    func definition(
        for candidate: DocumentVocabularyCandidate,
        languageCode: String,
        context: String
    ) async throws -> VocabularyPreparedDefinition {
        VocabularyPreparedDefinition(
            markdown: "Fixture definition for **\(candidate.displayLemma)**.",
            tags: "fixture,\(languageCode)",
            frequency: candidate.generalFrequencyRank
        )
    }
}

enum VocabularyPreparationImportBatch: Sendable {
    case pdf([StoredPDFWordRecord])
    case web([StoredWebWordRecord])

    var count: Int {
        switch self {
        case .pdf(let records): records.count
        case .web(let records): records.count
        }
    }

    var unresolvedDefinitions: [(vocabularyID: String, word: String)] {
        switch self {
        case .pdf(let records):
            records.compactMap { record in
                guard record.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let vocabularyID = record.vocabularyID else { return nil }
                return (vocabularyID, record.word)
            }
        case .web(let records):
            records.compactMap { record in
                guard record.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let vocabularyID = record.vocabularyID else { return nil }
                return (vocabularyID, record.word)
            }
        }
    }
}

@MainActor
protocol VocabularyPreparationLibraryAccess: AnyObject {
    func vocabularyPreparationExistingKeys(language: NLLanguage, kind: ReaderDocumentKind) -> Set<String>
    func persistVocabularyPreparationBatch(
        _ batch: VocabularyPreparationImportBatch,
        documentID: String
    ) async -> Bool
    func finishVocabularyPreparationImport(_ batch: VocabularyPreparationImportBatch)
}
