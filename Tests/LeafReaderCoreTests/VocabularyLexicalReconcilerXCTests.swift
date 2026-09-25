import XCTest
import LeafReaderCore

final class VocabularyLexicalReconcilerXCTests: XCTestCase {
    func testCorroboratedNounVerbPopulationsResolveAsSplit() {
        let anchor = VocabularyLexicalAnchorID(language: "en", basis: .resolvedLemma("record"))
        let occurrences = [
            occurrence(0, anchor: anchor, part: .noun, context: "the record survived"),
            occurrence(1, anchor: anchor, part: .noun, context: "a record remains"),
            occurrence(2, anchor: anchor, part: .verb, context: "please record this"),
            occurrence(3, anchor: anchor, part: .verb, context: "we record results")
        ]

        guard case let .resolvedSplit(partition) = VocabularyLexicalReconciler().reconcile(
            anchor: anchor,
            occurrences: occurrences
        ) else {
            return XCTFail("expected a corroborated split")
        }

        XCTAssertEqual(Set(partition.children.map(\.lexicalItemID.partOfSpeech)), [.noun, .verb])
        XCTAssertEqual(partition.children.map(\.assignedOccurrenceIDs.count).sorted(), [2, 2])
        XCTAssertTrue(partition.residualOccurrenceIDs.isEmpty)
        XCTAssertEqual(partition.diagnostics.state, .resolvedSplit)
        XCTAssertEqual(partition.diagnostics.reconcilerVersion, "lexical-reconciliation-v3")
        XCTAssertEqual(
            partition.diagnostics.childSupport.map(\.supportingOccurrenceCount).sorted(),
            [2, 2]
        )
        XCTAssertTrue(partition.diagnostics.childSupport.allSatisfy {
            $0.strongContextualOccurrenceCount == 0 && $0.attestationSources.isEmpty
        })
    }

    func testOneSpuriousConflictingClassificationDoesNotCreateAChild() {
        let anchor = VocabularyLexicalAnchorID(language: "en", basis: .resolvedLemma("record"))
        let occurrences = [
            occurrence(0, anchor: anchor, part: .noun, context: "the record survived"),
            occurrence(1, anchor: anchor, part: .noun, context: "a record remains"),
            occurrence(2, anchor: anchor, part: .noun, context: "that record changed"),
            occurrence(3, anchor: anchor, part: .verb, context: "spurious verb")
        ]

        guard case let .resolvedSingle(group) = VocabularyLexicalReconciler().reconcile(
            anchor: anchor,
            occurrences: occurrences
        ) else {
            return XCTFail("expected the corroborated noun population to remain single")
        }

        XCTAssertEqual(group.lexicalItemID.partOfSpeech, .noun)
        XCTAssertEqual(group.assignedOccurrenceIDs.count, 3)
        XCTAssertEqual(group.residualOccurrenceIDs.count, 1)
    }

    func testStrongConflictingClassificationBlocksDominantSingleResolution() {
        let anchor = VocabularyLexicalAnchorID(language: "en", basis: .resolvedLemma("record"))
        let strongConflictRange = VocabularyDocumentSourceRange(
            unitIndex: 0,
            utf16Location: 30,
            utf16Length: 6
        )
        let occurrences = [
            occurrence(0, anchor: anchor, part: .noun, context: "the record survived"),
            occurrence(1, anchor: anchor, part: .noun, context: "a record remains"),
            VocabularyOccurrenceAnalysis(
                occurrenceID: VocabularyOccurrenceAnalysisID(
                    unitIndex: strongConflictRange.unitIndex,
                    utf16Location: strongConflictRange.utf16Location,
                    utf16Length: strongConflictRange.utf16Length
                ),
                sourceRange: strongConflictRange,
                surface: "record",
                anchor: anchor,
                analyses: [VocabularyMorphologicalAnalysis(
                    lemma: "record",
                    partOfSpeech: .verb,
                    source: .appleNaturalLanguage,
                    rawScore: 0.99,
                    confidence: .strong
                )],
                contextFingerprint: "please record this"
            )
        ]

        guard case let .ambiguous(group) = VocabularyLexicalReconciler().reconcile(
            anchor: anchor,
            occurrences: occurrences
        ) else {
            return XCTFail("strong conflicting evidence must block single-POS propagation")
        }

        XCTAssertEqual(Set(group.occurrenceIDs), Set(occurrences.map(\.occurrenceID)))
        XCTAssertEqual(group.diagnostics.residualOccurrenceCount, occurrences.count)
    }

    func testSingleUsableOccurrenceCannotCreateResolvedIdentity() {
        let anchor = VocabularyLexicalAnchorID(language: "en", basis: .resolvedLemma("record"))
        let occurrences = [
            occurrence(0, anchor: anchor, part: .noun, context: "the record survived")
        ]

        guard case let .unresolved(group) = VocabularyLexicalReconciler().reconcile(
            anchor: anchor,
            occurrences: occurrences
        ) else {
            return XCTFail("one POS observation must not become lexical identity")
        }

        XCTAssertEqual(group.occurrenceIDs, [occurrences[0].occurrenceID])
    }

    func testSingleUsableOccurrenceCannotAssignUnavailableOccurrences() {
        let anchor = VocabularyLexicalAnchorID(language: "en", basis: .resolvedLemma("record"))
        let occurrences = [
            occurrence(0, anchor: anchor, part: .noun, context: "the record survived"),
            occurrence(1, anchor: anchor, part: nil, context: "record one"),
            occurrence(2, anchor: anchor, part: nil, context: "record two"),
            occurrence(3, anchor: anchor, part: nil, context: "record three"),
            occurrence(4, anchor: anchor, part: nil, context: "record four")
        ]

        guard case let .unresolved(group) = VocabularyLexicalReconciler().reconcile(
            anchor: anchor,
            occurrences: occurrences
        ) else {
            return XCTFail("uncorroborated POS evidence must not propagate to unavailable occurrences")
        }

        XCTAssertEqual(Set(group.occurrenceIDs), Set(occurrences.map(\.occurrenceID)))
    }

    func testCorroboratedSinglePopulationMayAssignUnavailableOccurrences() {
        let anchor = VocabularyLexicalAnchorID(language: "en", basis: .resolvedLemma("record"))
        let occurrences = [
            occurrence(0, anchor: anchor, part: .noun, context: "the record survived"),
            occurrence(1, anchor: anchor, part: .noun, context: "a record remains"),
            occurrence(2, anchor: anchor, part: nil, context: "record")
        ]

        guard case let .resolvedSingle(group) = VocabularyLexicalReconciler().reconcile(
            anchor: anchor,
            occurrences: occurrences
        ) else {
            return XCTFail("independent corroboration should authorize a single lexical identity")
        }

        XCTAssertEqual(group.lexicalItemID.partOfSpeech, .noun)
        XCTAssertEqual(Set(group.assignedOccurrenceIDs), Set(occurrences.map(\.occurrenceID)))
        XCTAssertTrue(group.residualOccurrenceIDs.isEmpty)
    }

    func testDuplicateContextCannotCorroborateSinglePopulation() {
        let anchor = VocabularyLexicalAnchorID(language: "en", basis: .resolvedLemma("record"))
        let occurrences = [
            occurrence(0, anchor: anchor, part: .noun, context: "same repeated template"),
            occurrence(1, anchor: anchor, part: .noun, context: "same repeated template")
        ]

        XCTAssertEqual(
            VocabularyLexicalReconciler().reconcile(anchor: anchor, occurrences: occurrences).state,
            .unresolved
        )
    }

    func testStrongContextPlusIndependentAttestationCanResolveSinglePopulation() {
        let anchor = VocabularyLexicalAnchorID(language: "en", basis: .resolvedLemma("record"))
        let sourceRange = VocabularyDocumentSourceRange(unitIndex: 0, utf16Location: 0, utf16Length: 6)
        let occurrence = VocabularyOccurrenceAnalysis(
            occurrenceID: VocabularyOccurrenceAnalysisID(
                unitIndex: sourceRange.unitIndex,
                utf16Location: sourceRange.utf16Location,
                utf16Length: sourceRange.utf16Length
            ),
            sourceRange: sourceRange,
            surface: "record",
            anchor: anchor,
            analyses: [
                VocabularyMorphologicalAnalysis(
                    lemma: "record",
                    partOfSpeech: .noun,
                    source: .appleNaturalLanguage,
                    rawScore: 0.99,
                    confidence: .strong
                ),
                VocabularyMorphologicalAnalysis(
                    lemma: "record",
                    partOfSpeech: .noun,
                    source: .lexicalAttestation,
                    confidence: .usable
                )
            ],
            contextFingerprint: "the record survived"
        )

        guard case let .resolvedSingle(group) = VocabularyLexicalReconciler().reconcile(
            anchor: anchor,
            occurrences: [occurrence]
        ) else {
            return XCTFail("strong contextual evidence plus attestation should resolve")
        }
        XCTAssertEqual(group.lexicalItemID.partOfSpeech, .noun)
        let support = group.diagnostics.childSupport
        XCTAssertEqual(support.count, 1)
        XCTAssertEqual(support[0].strongContextualOccurrenceCount, 1)
        XCTAssertEqual(support[0].attestationSources, [.lexicalAttestation])
    }

    func testDeterministicSingleRuleRequiresExplicitLanguageValidation() {
        let anchor = VocabularyLexicalAnchorID(language: "de", basis: .resolvedLemma("folge"))
        let sourceRange = VocabularyDocumentSourceRange(unitIndex: 0, utf16Location: 0, utf16Length: 5)
        let occurrence = VocabularyOccurrenceAnalysis(
            occurrenceID: VocabularyOccurrenceAnalysisID(
                unitIndex: sourceRange.unitIndex,
                utf16Location: sourceRange.utf16Location,
                utf16Length: sourceRange.utf16Length
            ),
            sourceRange: sourceRange,
            surface: "Folge",
            anchor: anchor,
            analyses: [VocabularyMorphologicalAnalysis(
                lemma: "folge",
                partOfSpeech: .noun,
                source: .deterministicMorphology,
                confidence: .usable
            )],
            contextFingerprint: "die Folge"
        )

        XCTAssertEqual(
            VocabularyLexicalReconciler().reconcile(anchor: anchor, occurrences: [occurrence]).state,
            .unresolved
        )
        let validated = VocabularyLexicalReconciler(configuration: .init(
            validatedDeterministicSingleRuleLanguages: ["de"]
        ))
        XCTAssertEqual(
            validated.reconcile(anchor: anchor, occurrences: [occurrence]).state,
            .resolvedSingle
        )
    }

    func testValidSplitLeavesUnavailableOccurrenceResidual() {
        let anchor = VocabularyLexicalAnchorID(language: "en", basis: .resolvedLemma("record"))
        let occurrences = [
            occurrence(0, anchor: anchor, part: .noun, context: "the record survived"),
            occurrence(1, anchor: anchor, part: .noun, context: "a record remains"),
            occurrence(2, anchor: anchor, part: .verb, context: "please record this"),
            occurrence(3, anchor: anchor, part: .verb, context: "we record results"),
            occurrence(4, anchor: anchor, part: nil, context: "record")
        ]

        guard case let .resolvedSplit(partition) = VocabularyLexicalReconciler().reconcile(
            anchor: anchor,
            occurrences: occurrences
        ) else {
            return XCTFail("expected a split")
        }

        XCTAssertEqual(partition.residualOccurrenceIDs, [occurrences[4].occurrenceID])
        XCTAssertEqual(partition.diagnostics.residualOccurrenceCount, 1)
    }

    func testRepeatedIdenticalContextCannotManufactureSplitEvidence() {
        let anchor = VocabularyLexicalAnchorID(language: "en", basis: .resolvedLemma("record"))
        let occurrences = [
            occurrence(0, anchor: anchor, part: .noun, context: "the record survived"),
            occurrence(1, anchor: anchor, part: .noun, context: "a record remains"),
            occurrence(2, anchor: anchor, part: .verb, context: "same repeated template"),
            occurrence(3, anchor: anchor, part: .verb, context: "same repeated template"),
            occurrence(4, anchor: anchor, part: .verb, context: "same repeated template")
        ]

        guard case let .resolvedSingle(group) = VocabularyLexicalReconciler().reconcile(
            anchor: anchor,
            occurrences: occurrences
        ) else {
            return XCTFail("duplicate contexts must not authorize a second child")
        }

        XCTAssertEqual(group.lexicalItemID.partOfSpeech, .noun)
        XCTAssertEqual(group.residualOccurrenceIDs.count, 3)
    }

    func testUnavailableEvidenceCannotCreateResolvedIdentity() {
        let anchor = VocabularyLexicalAnchorID(language: "en", basis: .resolvedLemma("record"))
        let values = [
            occurrence(0, anchor: anchor, part: nil, context: "one"),
            occurrence(1, anchor: anchor, part: nil, context: "two")
        ]

        XCTAssertEqual(
            VocabularyLexicalReconciler().reconcile(anchor: anchor, occurrences: values).state,
            .unresolved
        )
    }

    func testExactSurfaceFallbackRemainsCaseSensitiveAndUnresolved() {
        let upper = VocabularyLexicalAnchorID(language: "de", basis: .exactSurface("Folgen"))
        let lower = VocabularyLexicalAnchorID(language: "de", basis: .exactSurface("folgen"))
        XCTAssertNotEqual(upper, lower)
        XCTAssertNotEqual(upper.canonicalKey, lower.canonicalKey)

        let result = VocabularyLexicalReconciler().reconcile(
            anchor: upper,
            occurrences: [occurrence(0, anchor: upper, part: .noun, context: "die Folgen")]
        )
        XCTAssertEqual(result.state, .unresolved)
    }

    private func occurrence(
        _ index: Int,
        anchor: VocabularyLexicalAnchorID,
        part: VocabularyPartOfSpeech?,
        context: String
    ) -> VocabularyOccurrenceAnalysis {
        let sourceRange = VocabularyDocumentSourceRange(
            unitIndex: 0,
            utf16Location: index * 10,
            utf16Length: 6
        )
        let analyses: [VocabularyMorphologicalAnalysis]
        if let part {
            analyses = [VocabularyMorphologicalAnalysis(
                lemma: anchor.resolvedLemma ?? anchor.displayValue,
                partOfSpeech: part,
                source: .validationFixture,
                rawScore: 0.9,
                confidence: .usable
            )]
        } else {
            analyses = [VocabularyMorphologicalAnalysis(
                lemma: anchor.resolvedLemma ?? anchor.displayValue,
                partOfSpeech: .unknown,
                source: .validationFixture,
                confidence: .unavailable
            )]
        }
        return VocabularyOccurrenceAnalysis(
            occurrenceID: VocabularyOccurrenceAnalysisID(
                unitIndex: sourceRange.unitIndex,
                utf16Location: sourceRange.utf16Location,
                utf16Length: sourceRange.utf16Length
            ),
            sourceRange: sourceRange,
            surface: "record",
            anchor: anchor,
            analyses: analyses,
            contextFingerprint: context
        )
    }
}
