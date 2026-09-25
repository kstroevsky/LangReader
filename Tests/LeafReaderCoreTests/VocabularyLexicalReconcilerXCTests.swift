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
