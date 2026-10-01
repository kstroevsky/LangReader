import Foundation

package struct VocabularyDefinitionRoutingIdentity: Equatable, Sendable {
    package let language: VocabularyLanguageID
    package let languageRevision: UInt64
    package let providerDescriptor: VocabularyProviderDescriptor?

    package init(
        language: VocabularyLanguageID,
        languageRevision: UInt64,
        providerDescriptor: VocabularyProviderDescriptor?
    ) {
        self.language = language
        self.languageRevision = languageRevision
        self.providerDescriptor = providerDescriptor
    }
}

package struct VocabularyDefinitionRequest: Sendable {
    package let language: VocabularyLanguageID
    package let lemma: String
    package let surfaceForm: String?
    package let context: String
    package let lexicalItemID: VocabularyLexicalItemID?

    package init(
        language: VocabularyLanguageID,
        lemma: String,
        surfaceForm: String? = nil,
        context: String,
        lexicalItemID: VocabularyLexicalItemID? = nil
    ) {
        self.language = language
        self.lemma = lemma
        self.surfaceForm = surfaceForm
        self.context = context
        self.lexicalItemID = lexicalItemID
    }
}

package struct VocabularyDefinition: Sendable {
    package let markdown: String
    package let resolvedLemma: String?
    package let tags: String?
    package let frequency: Int?
    package let provenance: VocabularyProviderDescriptor

    package init(
        markdown: String,
        resolvedLemma: String? = nil,
        tags: String? = nil,
        frequency: Int? = nil,
        provenance: VocabularyProviderDescriptor
    ) {
        self.markdown = markdown
        self.resolvedLemma = resolvedLemma
        self.tags = tags
        self.frequency = frequency
        self.provenance = provenance
    }
}

package enum VocabularyDefinitionProviderError: Error, Equatable, Sendable {
    case incompatibleLanguage(requested: VocabularyLanguageID, providerID: String)
}

package protocol VocabularyDefinitionProviding: Sendable {
    var descriptor: VocabularyProviderDescriptor { get }
    func definition(for request: VocabularyDefinitionRequest) async throws -> VocabularyDefinition?
    func cachedDefinition(for request: VocabularyDefinitionRequest) -> VocabularyDefinition?
}

package extension VocabularyDefinitionProviding {
    func cachedDefinition(for request: VocabularyDefinitionRequest) -> VocabularyDefinition? {
        nil
    }
}
