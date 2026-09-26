import Foundation
import LeafReaderCore

struct VocabularyPreparationDocumentIdentity: Equatable, Sendable {
    let documentID: String
    let loadGeneration: Int
    let webPlainTextGeneration: Int?
    let languageRevision: UInt64
}

struct VocabularyPreparationSourceSnapshot: Sendable {
    let identity: VocabularyPreparationDocumentIdentity
    let kind: ReaderDocumentKind
    let languageResolution: VocabularyLanguageResolution
    let runtime: VocabularyLanguageRuntime
    let texts: [String]
    let index: VocabularyDocumentLemmaIndex

    var language: VocabularyLanguageID { runtime.language }
}

enum VocabularyPreparationSourceError: LocalizedError {
    case noDocument
    case textNotReady
    case undeterminedLanguage
    case unsupportedLanguage(VocabularyLanguageID)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noDocument:
            return AppText.localized("没有打开的文档。", "No document is open.")
        case .textNotReady:
            return AppText.localized("文档文本仍在载入。请稍后重试。", "Document text is still loading. Please retry shortly.")
        case .undeterminedLanguage:
            return AppText.localized(
                "无法确定文档语言。请选择一种语言后再准备词汇。",
                "The document language could not be determined. Choose a language to prepare vocabulary."
            )
        case .unsupportedLanguage(let language):
            let name = Locale.current.localizedString(forLanguageCode: language.primaryLanguage) ?? language.bcp47
            return AppText.localized(
                "已检测到\(name)，但当前不能为该语言准备词汇。",
                "Detected \(name). Vocabulary preparation is not available for this language yet."
            )
        case .cancelled:
            return AppText.localized("词汇准备已取消。", "Vocabulary preparation was cancelled.")
        }
    }
}

enum VocabularyPreparationDefinitionError: LocalizedError {
    case noCompatibleProvider
    case notFound

    var errorDescription: String? {
        switch self {
        case .noCompatibleProvider:
            AppText.localized("当前语言没有可用的词典。", "No compatible dictionary is available for this language.")
        case .notFound:
            AppText.localized("没有找到可用释义。", "No definition is available for this word.")
        }
    }
}

@MainActor
protocol VocabularyPreparationDocumentSource: AnyObject {
    var vocabularyPreparationIdentity: VocabularyPreparationDocumentIdentity? { get }
    func vocabularyPreparationSnapshot(selection: VocabularyLanguageSelection) async throws -> VocabularyPreparationSourceSnapshot
    func acceptsVocabularyPreparationIdentity(_ identity: VocabularyPreparationDocumentIdentity) -> Bool
}

typealias VocabularyPreparedDefinition = VocabularyDefinition

struct EnglishECDICTVocabularyDefinitionProvider: VocabularyDefinitionProviding {
    let descriptor = VocabularyProviderDescriptor(
        id: "dictionary.ecdict",
        version: "ecdict-v1",
        supportedLanguageRanges: [VocabularyLanguageRange(language: .english, includesDescendants: true)]
    )

    func definition(for request: VocabularyDefinitionRequest) async throws -> VocabularyDefinition? {
        guard descriptor.supports(request.language) else {
            throw VocabularyDefinitionProviderError.incompatibleLanguage(
                requested: request.language,
                providerID: descriptor.id
            )
        }
        return await Task.detached(priority: .userInitiated) {
            guard let lookup = LocalDictionaryLookupService.shared.dictionaryAnswer(
                for: request.lemma,
                context: request.context
            ) else {
                return nil
            }
            return VocabularyDefinition(
                markdown: lookup.markdown,
                resolvedLemma: request.lemma,
                tags: lookup.metadata.tags,
                frequency: lookup.metadata.frequency,
                provenance: descriptor
            )
        }.value
    }
}

struct GermanWiktionaryVocabularyDefinitionProvider: VocabularyDefinitionProviding {
    let descriptor = VocabularyProviderDescriptor(
        id: "dictionary.de-wiktionary",
        version: "wiktionary-api-v1",
        supportedLanguageRanges: [VocabularyLanguageRange(language: .german, includesDescendants: true)]
    )

    func definition(for request: VocabularyDefinitionRequest) async throws -> VocabularyDefinition? {
        guard descriptor.supports(request.language) else {
            throw VocabularyDefinitionProviderError.incompatibleLanguage(
                requested: request.language,
                providerID: descriptor.id
            )
        }
        do {
            let entry = try await GermanWiktionaryDictionary.shared.lookup(request.lemma)
            return VocabularyDefinition(
                markdown: entry.markdown,
                resolvedLemma: entry.lemma,
                tags: entry.metadata.tags,
                frequency: entry.metadata.frequency,
                provenance: descriptor
            )
        } catch GermanWiktionaryDictionary.LookupError.noEntry {
            return nil
        }
    }
}

/// Used only by the opt-in GUI performance/smoke harness. It keeps German
/// preparation deterministic and guarantees that automation never contacts
/// Wiktionary.
struct FixtureVocabularyPreparationDefinitionProvider: VocabularyDefinitionProviding {
    let descriptor = VocabularyProviderDescriptor(
        id: "dictionary.fixture",
        version: "1",
        supportedLanguageRanges: [
            VocabularyLanguageRange(language: .english, includesDescendants: true),
            VocabularyLanguageRange(language: .german, includesDescendants: true)
        ]
    )

    func definition(for request: VocabularyDefinitionRequest) async throws -> VocabularyDefinition? {
        guard descriptor.supports(request.language) else {
            throw VocabularyDefinitionProviderError.incompatibleLanguage(
                requested: request.language,
                providerID: descriptor.id
            )
        }
        return VocabularyDefinition(
            markdown: "Fixture definition for **\(request.lemma)**.",
            resolvedLemma: request.lemma,
            tags: "fixture,\(request.language.bcp47)",
            provenance: descriptor
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
    func vocabularyPreparationExistingKeys(language: VocabularyLanguageID, kind: ReaderDocumentKind) -> Set<String>
    func persistVocabularyPreparationBatch(
        _ batch: VocabularyPreparationImportBatch,
        documentID: String
    ) async -> Bool
    func finishVocabularyPreparationImport(_ batch: VocabularyPreparationImportBatch)
}
