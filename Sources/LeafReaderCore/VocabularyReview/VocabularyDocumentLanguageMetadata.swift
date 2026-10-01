import Foundation

/// Durable document-level language evidence. This is intentionally separate
/// from vocabulary-row metadata: restoring a document language may guide new
/// work, but it does not silently rewrite unresolved legacy rows.
package struct VocabularyDocumentLanguageMetadata: Codable, Equatable, Sendable {
    package static let currentSchemaVersion = 1

    package let schemaVersion: Int
    package let resolution: VocabularyLanguageResolution
    package let normalizationVersion: String

    package init(
        resolution: VocabularyLanguageResolution,
        schemaVersion: Int = currentSchemaVersion,
        normalizationVersion: String = VocabularyNormalizationPolicy.currentVersion
    ) {
        self.schemaVersion = schemaVersion
        self.resolution = resolution
        self.normalizationVersion = normalizationVersion
    }

    package var isCompatible: Bool {
        schemaVersion == Self.currentSchemaVersion
            && resolution.languageID != nil
    }

    /// A restored automatic result is explicitly marked as persisted metadata.
    /// A manual choice keeps its provenance because it remains authoritative
    /// user evidence across launches.
    package var restoredResolution: VocabularyLanguageResolution? {
        guard isCompatible, let resolved = resolution.resolvedLanguage else { return nil }
        if resolved.provenance == .userSelected {
            return .resolved(resolved)
        }
        return .resolved(VocabularyResolvedLanguage(
            id: resolved.id,
            provenance: .persistedDocumentMetadata,
            evidence: resolved.evidence
        ))
    }
}
