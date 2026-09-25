import Foundation

package struct VocabularyLexicalSupportSummary: Codable, Equatable, Sendable {
    package let partOfSpeech: VocabularyPartOfSpeech
    package let supportingOccurrenceCount: Int
    package let distinctContextCount: Int

    package init(
        partOfSpeech: VocabularyPartOfSpeech,
        supportingOccurrenceCount: Int,
        distinctContextCount: Int
    ) {
        self.partOfSpeech = partOfSpeech
        self.supportingOccurrenceCount = supportingOccurrenceCount
        self.distinctContextCount = distinctContextCount
    }
}

package struct VocabularyLexicalResolutionDiagnostics: Codable, Equatable, Sendable {
    package let anchor: VocabularyLexicalAnchorID
    package let state: VocabularyLexicalResolutionState
    package let occurrenceCount: Int
    package let childSupport: [VocabularyLexicalSupportSummary]
    package let residualOccurrenceCount: Int
    package let providers: [VocabularyLinguisticEvidenceSource]
    package let minimumRawScore: Double?
    package let maximumRawScore: Double?
    package let reconcilerVersion: String
}

package struct VocabularyResolvedLexicalGroup: Codable, Equatable, Sendable {
    package let lexicalItemID: VocabularyLexicalItemID
    package let assignedOccurrenceIDs: [VocabularyOccurrenceAnalysisID]
    package let residualOccurrenceIDs: [VocabularyOccurrenceAnalysisID]
    package let diagnostics: VocabularyLexicalResolutionDiagnostics
}

package struct VocabularyResolvedLexicalPartition: Codable, Equatable, Sendable {
    package let children: [VocabularyResolvedLexicalGroup]
    package let residualOccurrenceIDs: [VocabularyOccurrenceAnalysisID]
    package let diagnostics: VocabularyLexicalResolutionDiagnostics
}

package struct VocabularyAmbiguousLexicalGroup: Codable, Equatable, Sendable {
    package let occurrenceIDs: [VocabularyOccurrenceAnalysisID]
    package let diagnostics: VocabularyLexicalResolutionDiagnostics
}

package struct VocabularyUnresolvedLexicalGroup: Codable, Equatable, Sendable {
    package let occurrenceIDs: [VocabularyOccurrenceAnalysisID]
    package let diagnostics: VocabularyLexicalResolutionDiagnostics
}

package enum VocabularyLexicalResolution: Codable, Equatable, Sendable {
    case resolvedSingle(VocabularyResolvedLexicalGroup)
    case resolvedSplit(VocabularyResolvedLexicalPartition)
    case ambiguous(VocabularyAmbiguousLexicalGroup)
    case unresolved(VocabularyUnresolvedLexicalGroup)

    package var state: VocabularyLexicalResolutionState {
        switch self {
        case .resolvedSingle: .resolvedSingle
        case .resolvedSplit: .resolvedSplit
        case .ambiguous: .ambiguous
        case .unresolved: .unresolved
        }
    }

    package var diagnostics: VocabularyLexicalResolutionDiagnostics {
        switch self {
        case let .resolvedSingle(group): group.diagnostics
        case let .resolvedSplit(partition): partition.diagnostics
        case let .ambiguous(group): group.diagnostics
        case let .unresolved(group): group.diagnostics
        }
    }
}

/// The sole Core owner of the decision that occurrence evidence is strong
/// enough to instantiate one or more POS-bound lexical identities.
package struct VocabularyLexicalReconciler: Sendable {
    package struct Configuration: Codable, Equatable, Sendable {
        package let minimumSingleOccurrenceSupport: Int
        package let minimumSingleDistinctContextSupport: Int
        package let minimumSplitOccurrenceSupport: Int
        package let minimumSplitDistinctContextSupport: Int
        package let validatedDeterministicSingleRuleLanguages: Set<String>

        package init(
            minimumSingleOccurrenceSupport: Int = 2,
            minimumSingleDistinctContextSupport: Int = 2,
            minimumSplitOccurrenceSupport: Int = 2,
            minimumSplitDistinctContextSupport: Int = 2,
            validatedDeterministicSingleRuleLanguages: Set<String> = []
        ) {
            self.minimumSingleOccurrenceSupport = max(1, minimumSingleOccurrenceSupport)
            self.minimumSingleDistinctContextSupport = max(1, minimumSingleDistinctContextSupport)
            self.minimumSplitOccurrenceSupport = max(2, minimumSplitOccurrenceSupport)
            self.minimumSplitDistinctContextSupport = max(2, minimumSplitDistinctContextSupport)
            self.validatedDeterministicSingleRuleLanguages = Set(
                validatedDeterministicSingleRuleLanguages.map { $0.lowercased() }
            )
        }

        package static let production = Configuration()
    }

    package static let policyVersion = "lexical-reconciliation-v1"

    private let configuration: Configuration

    package init(configuration: Configuration = .production) {
        self.configuration = configuration
    }

    package func reconcile(
        anchor: VocabularyLexicalAnchorID,
        occurrences: [VocabularyOccurrenceAnalysis]
    ) -> VocabularyLexicalResolution {
        let matching = occurrences.filter { $0.anchor == anchor }
        guard !matching.isEmpty else {
            return .unresolved(VocabularyUnresolvedLexicalGroup(
                occurrenceIDs: [],
                diagnostics: diagnostics(
                    anchor: anchor,
                    state: .unresolved,
                    occurrences: [],
                    support: [:],
                    residualCount: 0
                )
            ))
        }

        // An exact-surface anchor deliberately records that a trustworthy lemma
        // is unavailable. POS evidence may still be diagnostically useful, but
        // it cannot authorize a resolved lemma+POS identity.
        guard let lemma = anchor.resolvedLemma else {
            return .unresolved(VocabularyUnresolvedLexicalGroup(
                occurrenceIDs: matching.map(\.occurrenceID),
                diagnostics: diagnostics(
                    anchor: anchor,
                    state: .unresolved,
                    occurrences: matching,
                    support: supportByPart(
                        ofSpeechByOccurrence(in: matching),
                        occurrences: matching
                    ),
                    residualCount: matching.count
                )
            ))
        }

        let partByOccurrence = ofSpeechByOccurrence(in: matching)
        let support = supportByPart(partByOccurrence, occurrences: matching)
        let supportedParts = support.keys.sorted { $0.rawValue < $1.rawValue }
        guard !supportedParts.isEmpty else {
            return .unresolved(VocabularyUnresolvedLexicalGroup(
                occurrenceIDs: matching.map(\.occurrenceID),
                diagnostics: diagnostics(
                    anchor: anchor,
                    state: .unresolved,
                    occurrences: matching,
                    support: support,
                    residualCount: matching.count
                )
            ))
        }

        if supportedParts.count == 1, let part = supportedParts.first {
            guard hasSingleResolutionSupport(part, language: anchor.language, support: support) else {
                return .unresolved(VocabularyUnresolvedLexicalGroup(
                    occurrenceIDs: matching.map(\.occurrenceID),
                    diagnostics: diagnostics(
                        anchor: anchor,
                        state: .unresolved,
                        occurrences: matching,
                        support: support,
                        residualCount: matching.count
                    )
                ))
            }
            return resolvedSingle(
                anchor: anchor,
                lemma: lemma,
                selectedPart: part,
                occurrences: matching,
                partByOccurrence: partByOccurrence,
                support: support
            )
        }

        let splitParts = supportedParts.filter { part in
            guard let evidence = support[part] else { return false }
            return evidence.occurrenceIDs.count >= configuration.minimumSplitOccurrenceSupport
                && evidence.contexts.count >= configuration.minimumSplitDistinctContextSupport
        }

        if splitParts.count >= 2 {
            let splitSet = Set(splitParts)
            let residual = matching.filter {
                guard let part = partByOccurrence[$0.occurrenceID] else { return true }
                return !splitSet.contains(part)
            }.map(\.occurrenceID)
            let stateDiagnostics = diagnostics(
                anchor: anchor,
                state: .resolvedSplit,
                occurrences: matching,
                support: support,
                residualCount: residual.count
            )
            let children = splitParts.sorted { $0.rawValue < $1.rawValue }.map { part in
                VocabularyResolvedLexicalGroup(
                    lexicalItemID: VocabularyLexicalItemID(
                        language: anchor.language,
                        lemma: lemma,
                        partOfSpeech: part
                    ),
                    assignedOccurrenceIDs: matching.compactMap {
                        partByOccurrence[$0.occurrenceID] == part ? $0.occurrenceID : nil
                    },
                    residualOccurrenceIDs: [],
                    diagnostics: stateDiagnostics
                )
            }
            return .resolvedSplit(VocabularyResolvedLexicalPartition(
                children: children,
                residualOccurrenceIDs: residual,
                diagnostics: stateDiagnostics
            ))
        }

        if splitParts.count == 1, let dominant = splitParts.first {
            return resolvedSingle(
                anchor: anchor,
                lemma: lemma,
                selectedPart: dominant,
                occurrences: matching,
                partByOccurrence: partByOccurrence,
                support: support
            )
        }

        return .ambiguous(VocabularyAmbiguousLexicalGroup(
            occurrenceIDs: matching.map(\.occurrenceID),
            diagnostics: diagnostics(
                anchor: anchor,
                state: .ambiguous,
                occurrences: matching,
                support: support,
                residualCount: matching.count
            )
        ))
    }

    private func hasSingleResolutionSupport(
        _ part: VocabularyPartOfSpeech,
        language: String,
        support: [VocabularyPartOfSpeech: PartSupport]
    ) -> Bool {
        guard let evidence = support[part] else { return false }
        let independentContextSupport = evidence.occurrenceIDs.count >= configuration.minimumSingleOccurrenceSupport
            && evidence.contexts.count >= configuration.minimumSingleDistinctContextSupport
        let independentlyAttestedStrongContext = !evidence.strongContextualOccurrenceIDs.isEmpty
            && !evidence.attestationSources.isEmpty
        let validatedDeterministicRule = configuration.validatedDeterministicSingleRuleLanguages
            .contains(language.lowercased())
            && evidence.sources.contains(.deterministicMorphology)
        return independentContextSupport
            || independentlyAttestedStrongContext
            || validatedDeterministicRule
    }

    private struct PartSupport {
        var occurrenceIDs = Set<VocabularyOccurrenceAnalysisID>()
        var contexts = Set<String>()
        var sources = Set<VocabularyLinguisticEvidenceSource>()
        var strongContextualOccurrenceIDs = Set<VocabularyOccurrenceAnalysisID>()
        var attestationSources = Set<VocabularyLinguisticEvidenceSource>()
    }

    private func ofSpeechByOccurrence(
        in occurrences: [VocabularyOccurrenceAnalysis]
    ) -> [VocabularyOccurrenceAnalysisID: VocabularyPartOfSpeech] {
        var result: [VocabularyOccurrenceAnalysisID: VocabularyPartOfSpeech] = [:]
        for occurrence in occurrences {
            let usable = occurrence.analyses.filter {
                $0.confidence.isUsable && $0.partOfSpeech != .unknown
            }
            let parts = Set(usable.map(\.partOfSpeech))
            guard parts.count == 1, let part = parts.first else { continue }
            result[occurrence.occurrenceID] = part
        }
        return result
    }

    private func supportByPart(
        _ partByOccurrence: [VocabularyOccurrenceAnalysisID: VocabularyPartOfSpeech],
        occurrences: [VocabularyOccurrenceAnalysis]
    ) -> [VocabularyPartOfSpeech: PartSupport] {
        var support: [VocabularyPartOfSpeech: PartSupport] = [:]
        for occurrence in occurrences {
            guard let part = partByOccurrence[occurrence.occurrenceID] else { continue }
            var partSupport = support[part, default: PartSupport()]
            partSupport.occurrenceIDs.insert(occurrence.occurrenceID)
            partSupport.contexts.insert(occurrence.contextFingerprint)
            for analysis in occurrence.analyses
            where analysis.confidence.isUsable && analysis.partOfSpeech == part {
                partSupport.sources.insert(analysis.source)
                if analysis.confidence == .strong,
                   analysis.source == .appleNaturalLanguage {
                    partSupport.strongContextualOccurrenceIDs.insert(occurrence.occurrenceID)
                }
                if analysis.source == .lexicalAttestation
                    || analysis.source == .deterministicMorphology {
                    partSupport.attestationSources.insert(analysis.source)
                }
            }
            support[part] = partSupport
        }
        return support
    }

    private func resolvedSingle(
        anchor: VocabularyLexicalAnchorID,
        lemma: String,
        selectedPart: VocabularyPartOfSpeech,
        occurrences: [VocabularyOccurrenceAnalysis],
        partByOccurrence: [VocabularyOccurrenceAnalysisID: VocabularyPartOfSpeech],
        support: [VocabularyPartOfSpeech: PartSupport]
    ) -> VocabularyLexicalResolution {
        let support = supportByPart(partByOccurrence, occurrences: occurrences)
        let assigned = occurrences.compactMap { occurrence -> VocabularyOccurrenceAnalysisID? in
            guard let supported = partByOccurrence[occurrence.occurrenceID] else {
                // With a single resolved child and no conflicting positive
                // evidence, unavailable/insufficient occurrences may inherit the
                // document-level resolution. This preserves line-wrap coverage.
                return occurrence.occurrenceID
            }
            return supported == selectedPart ? occurrence.occurrenceID : nil
        }
        let assignedSet = Set(assigned)
        let residual = occurrences.map(\.occurrenceID).filter { !assignedSet.contains($0) }
        let stateDiagnostics = diagnostics(
            anchor: anchor,
            state: .resolvedSingle,
            occurrences: occurrences,
            support: support,
            residualCount: residual.count
        )
        return .resolvedSingle(VocabularyResolvedLexicalGroup(
            lexicalItemID: VocabularyLexicalItemID(
                language: anchor.language,
                lemma: lemma,
                partOfSpeech: selectedPart
            ),
            assignedOccurrenceIDs: assigned,
            residualOccurrenceIDs: residual,
            diagnostics: stateDiagnostics
        ))
    }

    private func diagnostics(
        anchor: VocabularyLexicalAnchorID,
        state: VocabularyLexicalResolutionState,
        occurrences: [VocabularyOccurrenceAnalysis],
        support: [VocabularyPartOfSpeech: PartSupport],
        residualCount: Int
    ) -> VocabularyLexicalResolutionDiagnostics {
        let scores = occurrences
            .flatMap(\.analyses)
            .compactMap(\.rawScore)
            .filter(\.isFinite)
        return VocabularyLexicalResolutionDiagnostics(
            anchor: anchor,
            state: state,
            occurrenceCount: occurrences.count,
            childSupport: support.map { part, evidence in
                VocabularyLexicalSupportSummary(
                    partOfSpeech: part,
                    supportingOccurrenceCount: evidence.occurrenceIDs.count,
                    distinctContextCount: evidence.contexts.count
                )
            }.sorted { $0.partOfSpeech.rawValue < $1.partOfSpeech.rawValue },
            residualOccurrenceCount: residualCount,
            providers: Array(Set(occurrences.flatMap(\.analyses).map(\.source)))
                .sorted { $0.rawValue < $1.rawValue },
            minimumRawScore: scores.min(),
            maximumRawScore: scores.max(),
            reconcilerVersion: Self.policyVersion
        )
    }
}
