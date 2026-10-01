import Foundation

/// Semantic identity for a machine-derived vocabulary frequency value.
///
/// Legacy ranks decode with no provenance and therefore remain displayable but
/// are not considered compatible with a current provider until re-derived.
package struct VocabularyFrequencyProvenance: Codable, Equatable, Hashable, Sendable {
    package let language: VocabularyLanguageID
    package let languageProfileVersion: String
    package let provider: VocabularyProviderDescriptor

    package init(
        language: VocabularyLanguageID,
        languageProfileVersion: String,
        provider: VocabularyProviderDescriptor
    ) {
        self.language = language
        self.languageProfileVersion = languageProfileVersion
        self.provider = provider
    }
}

/// Exact work scope for one frequency backfill pass. Record coverage is part of
/// compatibility so newly-added eligible records invalidate an older marker.
package struct VocabularyFrequencyBackfillScope: Codable, Equatable, Hashable, Sendable {
    package static let currentSchemaVersion = 1

    package let schemaVersion: Int
    package let provenance: VocabularyFrequencyProvenance
    package let eligibleRecords: [VocabularyFrequencyBackfillRecordIdentity]

    package init(
        provenance: VocabularyFrequencyProvenance,
        eligibleRecords: some Sequence<VocabularyFrequencyBackfillRecordIdentity>,
        schemaVersion: Int = currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.provenance = provenance
        self.eligibleRecords = Array(Set(eligibleRecords)).sorted {
            if $0.id != $1.id { return $0.id < $1.id }
            if $0.lookupText != $1.lookupText { return $0.lookupText < $1.lookupText }
            return ($0.lexicalKey ?? "") < ($1.lexicalKey ?? "")
        }
    }

    package var eligibleRecordIDs: [String] { eligibleRecords.map(\.id) }
}

package struct VocabularyFrequencyBackfillRecordIdentity: Codable, Equatable, Hashable, Sendable {
    package let id: String
    package let lookupText: String
    package let language: VocabularyLanguageID
    package let lexicalKey: String?

    package init(id: String, lookupText: String, language: VocabularyLanguageID, lexicalKey: String?) {
        self.id = id
        self.lookupText = lookupText
        self.language = language
        self.lexicalKey = lexicalKey
    }
}

/// Persisted completion for an exact semantic scope. Terminal not-found records
/// are retained separately from successful derived values so they can be
/// distinguished from cancellation or unavailable capability.
package struct VocabularyFrequencyBackfillCompletion: Codable, Equatable, Hashable, Sendable {
    package let scope: VocabularyFrequencyBackfillScope
    package let terminalNotFoundRecordIDs: [String]

    package init(
        scope: VocabularyFrequencyBackfillScope,
        terminalNotFoundRecordIDs: some Sequence<String> = []
    ) {
        self.scope = scope
        self.terminalNotFoundRecordIDs = Array(Set(terminalNotFoundRecordIDs)).sorted()
    }
}
