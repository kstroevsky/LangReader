import NaturalLanguage
import XCTest
import LeafReaderCore

final class VocabularyDocumentLemmaIndexXCTests: XCTestCase {
    func testPartOfSpeechConfidencePolicyPreservesProductionThresholds() {
        XCTAssertEqual(
            VocabularyPartOfSpeechConfidencePolicy.classify(hypotheses: ["Noun": 0.80, "Verb": 0.20]),
            .noun
        )
        XCTAssertEqual(
            VocabularyPartOfSpeechConfidencePolicy.classify(hypotheses: ["Noun": 0.64, "Verb": 0.10]),
            .unknown
        )
        XCTAssertEqual(
            VocabularyPartOfSpeechConfidencePolicy.classify(hypotheses: ["Noun": 0.70, "Verb": 0.51]),
            .unknown
        )
        XCTAssertEqual(
            VocabularyPartOfSpeechConfidencePolicy.classify(hypotheses: ["OtherWord": 1.0]),
            .unknown,
            "Apple OtherWord means the lexical model supplied no supported POS evidence"
        )
        XCTAssertEqual(
            VocabularyPartOfSpeechConfidencePolicy.classify(hypotheses: ["Classifier": 1.0]),
            .other,
            "other explicitly unsupported lexical classes remain the .other bucket"
        )
    }

    func testUnknownPOSReconciliationRequiresExactlyOneConfidentClass() {
        let noun = VocabularyLexicalItemID(language: "en", lemma: "record", partOfSpeech: .noun)
        let verb = VocabularyLexicalItemID(language: "en", lemma: "record", partOfSpeech: .verb)
        let unknown = VocabularyLexicalItemID(language: "en", lemma: "record", partOfSpeech: .unknown)

        XCTAssertEqual(
            VocabularyPartOfSpeechReconciliationPolicy.soleConfidentPartByLemma([noun, unknown])["record"],
            .noun
        )
        XCTAssertEqual(
            VocabularyPartOfSpeechReconciliationPolicy.soleConfidentPartByLemma([verb, unknown])["record"],
            .verb
        )
        XCTAssertNil(
            VocabularyPartOfSpeechReconciliationPolicy.soleConfidentPartByLemma([noun, verb, unknown])["record"]
        )
        XCTAssertNil(
            VocabularyPartOfSpeechReconciliationPolicy.soleConfidentPartByLemma([unknown])["record"]
        )
    }
    func testPrioritySliceSeedsCompleteIndexWithoutChangingMatches() throws {
        let pages = [
            "Er ist gestern nach Hause gegangen. Wir gehen heute wieder.",
            "Sie ging langsam; ein gegan-\ngener Weg war lang.",
            "Für den Er-\nfolg folgen wir dem Plan. Das Gehen fällt leicht.",
            "Die E-Mail und die E-\nMail kamen an.",
            ""
        ]
        let priorityPageIndexes = VocabularyIndexPriorityPlanner.pageIndexes(
            pageCount: pages.count,
            currentPageIndex: 2,
            visiblePageIndexes: [2, 3, 3, -1, pages.count],
            neighborRadius: 1
        )
        XCTAssertEqual(priorityPageIndexes, [2, 3, 1, 4])

        let baseline = try XCTUnwrap(VocabularyDocumentLemmaIndex(texts: pages, language: .german))
        let priority = try XCTUnwrap(VocabularyDocumentLemmaIndex(
            texts: priorityPageIndexes.map { pages[$0] },
            language: .german
        ))
        let seeded = try XCTUnwrap(VocabularyDocumentLemmaIndex(
            texts: pages,
            language: .german,
            seed: VocabularyDocumentLemmaIndexSeed(
                pageIndexes: priorityPageIndexes,
                index: priority
            )
        ))

        XCTAssertEqual(seeded.reusedPageCount, priorityPageIndexes.count)
        for (lemma, selectedForm) in [
            ("gehen", "gegangen"),
            ("gehen", "ging"),
            ("E-Mail", "E-Mail")
        ] {
            XCTAssertEqual(
                seeded.matches(lemma: lemma, selectedForm: selectedForm),
                baseline.matches(lemma: lemma, selectedForm: selectedForm)
            )
        }
    }

    func testCancelledPriorityIndexDoesNotReturnPartialState() {
        XCTAssertNil(VocabularyDocumentLemmaIndex(
            texts: ["gehen", "ging"],
            language: .german,
            isCancelled: { true }
        ))
    }

    func testGroupedLookupIgnoresLargeIrrelevantVocabularyWithoutLosingAliases() throws {
        let index = try XCTUnwrap(VocabularyDocumentLemmaIndex(
            texts: ["Wir gehen heute. Sie gehen morgen."],
            language: .german
        ))
        var groups = Dictionary(uniqueKeysWithValues: (0..<2_000).map {
            ("missing-\($0)", "missing-\($0)")
        })
        groups["gehen"] = "gehen"
        groups["alias"] = "gehen"

        let result = try XCTUnwrap(index.matches(lemmasByKey: groups).first)
        XCTAssertEqual(result["gehen"]?.count, 2)
        XCTAssertEqual(result["alias"]?.count, 2)
        XCTAssertEqual(result.keys.sorted(), ["alias", "gehen"])
    }

    func testSingleTokenPostingsPreserveLegacyScannerResults() throws {
        let pages = [
            "Er ist gegangen. Wir gehen heute. Das Gehen fällt leicht.",
            "Sie ging langsam; ein gegan-\ngener Weg war lang.",
            "Die E-Mail und die E-\nMail kamen an."
        ]
        let index = try XCTUnwrap(VocabularyDocumentLemmaIndex(texts: pages, language: .german))

        for (lemma, selectedForm) in [
            ("gehen", "gegangen"),
            ("gehen", "ging"),
            ("E-Mail", "E-Mail")
        ] {
            XCTAssertEqual(
                index.matches(lemma: lemma, selectedForm: selectedForm),
                GermanLemmaOccurrenceMatcher.matches(
                    lemma: lemma,
                    selectedForm: selectedForm,
                    inTexts: pages,
                    language: .german
                )
            )
        }
    }

    func testGroupedLookupReturnsNoPartialResultAfterCancellation() throws {
        let index = try XCTUnwrap(VocabularyDocumentLemmaIndex(
            texts: Array(repeating: "Wir gehen heute.", count: 20),
            language: .german
        ))
        var checks = 0
        let result = index.matches(lemmasByKey: ["gehen": "gehen"]) {
            checks += 1
            return checks > 3
        }

        XCTAssertNil(result)
        XCTAssertLessThanOrEqual(checks, 4)
    }

    func testInventorySummariesCollapseInflectionsButKeepDerivationsSeparate() throws {
        let index = try XCTUnwrap(VocabularyDocumentLemmaIndex(
            texts: ["They develop tools. She developed one while developing another. Development continues."],
            language: .english
        ))

        let summaries = index.lemmaSummaries()
        let develop = try XCTUnwrap(summaries.first { $0.lemmaKey == "develop" })
        XCTAssertEqual(develop.occurrenceCount, 3)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: develop.observedForms.map { ($0.surface.lowercased(), $0.occurrenceCount) }), [
            "develop": 1,
            "developed": 1,
            "developing": 1
        ])
        XCTAssertEqual(summaries.first { $0.lemmaKey == "development" }?.occurrenceCount, 1)
    }

    func testReconciledSummariesCreateSplitOnlyFromCorroboratedContexts() throws {
        let index = try XCTUnwrap(VocabularyDocumentLemmaIndex(
            texts: [
                "noun-one record remains",
                "noun-two record survives",
                "verb-one record this",
                "verb-two record that"
            ],
            language: .english,
            maximumWorkerCount: 1,
            resolutionProvider: { surface, _, _ in
                surface == "record"
                    ? .resolved(lemma: "record", source: .naturalLanguage)
                    : .unresolved(surface: surface)
            },
            analysisProvider: { request in
                guard request.surface == "record" else { return [] }
                let part: VocabularyPartOfSpeech = request.context.contains("noun-") ? .noun : .verb
                return [VocabularyMorphologicalAnalysis(
                    lemma: "record",
                    partOfSpeech: part,
                    source: .validationFixture,
                    rawScore: 1,
                    confidence: .usable
                )]
            }
        ))

        let record = index.lexicalSummaries().filter { $0.lemmaKey == "record" }
        XCTAssertEqual(record.count, 2)
        XCTAssertEqual(Set(record.map(\.partOfSpeech)), [.noun, .verb])
        XCTAssertTrue(record.allSatisfy { $0.resolutionState == .resolvedSplit })
        XCTAssertTrue(record.allSatisfy { $0.assessmentPolicy == .fullInference })
        XCTAssertEqual(record.map(\.occurrenceCount).sorted(), [2, 2])
    }

    func testReconciledSummariesKeepOneOffConflictAsDirectEvidenceResidual() throws {
        let index = try XCTUnwrap(VocabularyDocumentLemmaIndex(
            texts: [
                "noun-one record remains",
                "noun-two record survives",
                "noun-three record persists",
                "verb-one record this"
            ],
            language: .english,
            maximumWorkerCount: 1,
            resolutionProvider: { surface, _, _ in
                surface == "record"
                    ? .resolved(lemma: "record", source: .naturalLanguage)
                    : .unresolved(surface: surface)
            },
            analysisProvider: { request in
                guard request.surface == "record" else { return [] }
                let part: VocabularyPartOfSpeech = request.context.contains("verb-") ? .verb : .noun
                return [VocabularyMorphologicalAnalysis(
                    lemma: "record",
                    partOfSpeech: part,
                    source: .validationFixture,
                    rawScore: 1,
                    confidence: .usable
                )]
            }
        ))

        let record = index.lexicalSummaries().filter { $0.lemmaKey == "record" }
        let noun = try XCTUnwrap(record.first { $0.partOfSpeech == .noun })
        let residual = try XCTUnwrap(record.first { $0.assessmentPolicy == .directEvidenceOnly })
        XCTAssertEqual(noun.occurrenceCount, 3)
        XCTAssertEqual(noun.resolutionState, .resolvedSingle)
        XCTAssertEqual(residual.occurrenceCount, 1)
        XCTAssertEqual(residual.partOfSpeech, .unknown)
        XCTAssertTrue(residual.canonicalKey.hasSuffix("|residual"))
    }

    func testOrdinaryEnglishWordsAreNotClassifiedAsConfidentNames() throws {
        let index = try XCTUnwrap(VocabularyDocumentLemmaIndex(
            texts: ["They develop tools while readers learn vocabulary."],
            language: .english
        ))

        let summaries = index.lemmaSummaries()
        XCTAssertFalse(try XCTUnwrap(summaries.first { $0.lemmaKey == "develop" }).isConfidentName)
        XCTAssertFalse(try XCTUnwrap(summaries.first { $0.lemmaKey == "tool" }).isConfidentName)
        XCTAssertFalse(try XCTUnwrap(summaries.first { $0.lemmaKey == "vocabulary" }).isConfidentName)
    }

    func testInventorySummariesAggregateAcrossUnitsAndRepairPDFLineWraps() throws {
        let index = try XCTUnwrap(VocabularyDocumentLemmaIndex(
            texts: ["A remark was develop-\ned here.", "Later they developed it again."],
            language: .english
        ))

        let develop = try XCTUnwrap(index.lemmaSummaries().first { $0.lemmaKey == "develop" })
        XCTAssertEqual(develop.occurrenceCount, 2)
        XCTAssertEqual(develop.representativeRange.unitIndex, 0)
        XCTAssertTrue(develop.observedForms.contains { $0.surface == "developed" && $0.occurrenceCount == 2 })
    }

    func testRendererWhitespaceDoesNotChangeLemmasPOSOrSourceRanges() throws {
        let inline = "The careful curator opened the archive and recorded each record."
        let wrapped = "The careful\ncurator opened\t the archive and recorded each record."
        let inlineIndex = try XCTUnwrap(VocabularyDocumentLemmaIndex(texts: [inline], language: .english))
        let wrappedIndex = try XCTUnwrap(VocabularyDocumentLemmaIndex(texts: [wrapped], language: .english))

        let projection: (VocabularyDocumentLemmaSummary) -> String = {
            "\($0.canonicalKey)#\($0.occurrenceCount)"
        }
        XCTAssertEqual(wrappedIndex.lemmaSummaries().map(projection), inlineIndex.lemmaSummaries().map(projection))

        let match = try XCTUnwrap(wrappedIndex.matches(lemma: "curator", selectedForm: "curator").first?.first)
        XCTAssertEqual(match.range, (wrapped as NSString).range(of: "curator"))
        XCTAssertEqual(match.matchedText, "curator")
    }

    func testGermanCompoundsRemainSeparateLemmas() throws {
        let index = try XCTUnwrap(VocabularyDocumentLemmaIndex(
            texts: ["Das Haus steht neben dem Krankenhaus. Die Häuser sind alt."],
            language: .german
        ))
        let keys = Set(index.lemmaSummaries().map(\.lemmaKey))

        XCTAssertTrue(keys.contains("haus"))
        XCTAssertTrue(keys.contains("krankenhaus"))
        XCTAssertNotEqual("haus", "krankenhaus")
    }

    func testInventoryExcludesConfidentNamesAndNoiseButKeepsFunctionWords() {
        let summaries = [
            VocabularyDocumentLemmaSummary(
                canonicalKey: "anna",
                displayLemma: "Anna",
                observedForms: [VocabularyDocumentObservedForm(surface: "Anna", occurrenceCount: 2)],
                occurrenceCount: 2,
                representativeRange: VocabularyDocumentSourceRange(unitIndex: 0, utf16Location: 0, utf16Length: 4),
                isConfidentName: true
            ),
            VocabularyDocumentLemmaSummary(
                canonicalKey: "the",
                displayLemma: "the",
                observedForms: [VocabularyDocumentObservedForm(surface: "the", occurrenceCount: 5)],
                occurrenceCount: 5,
                representativeRange: VocabularyDocumentSourceRange(unitIndex: 0, utf16Location: 5, utf16Length: 3)
            ),
            VocabularyDocumentLemmaSummary(
                canonicalKey: "12345",
                displayLemma: "12345",
                observedForms: [VocabularyDocumentObservedForm(surface: "12345", occurrenceCount: 1)],
                occurrenceCount: 1,
                representativeRange: VocabularyDocumentSourceRange(unitIndex: 0, utf16Location: 9, utf16Length: 5)
            )
        ]
        let inventory = DocumentVocabularyInventory(
            summaries: summaries,
            languageCode: "en",
            maximumFrequencyRank: 10_000,
            rank: { _ in nil }
        )

        XCTAssertEqual(inventory.candidates.map(\.canonicalKey), ["the"])
        XCTAssertEqual(inventory.excludedCount, 2)
    }

    func testInventoryExcludesLinkEmailMarkupAndObviousOCRArtifacts() throws {
        let text = """
        Read the book at https://example.com/ReaderPath or www.example.org.
        Mail reader@example.com. <span>Visible prose</span> &nbsp; aaaaaa foo--bar.
        """
        let index = try XCTUnwrap(VocabularyDocumentLemmaIndex(texts: [text], language: .english))
        let keys = Set(index.lemmaSummaries().map(\.lemmaKey))

        for excluded in ["https", "example", "com", "readerpath", "www", "org", "reader", "span", "nbsp", "aaaaaa", "foo", "bar"] {
            XCTAssertFalse(keys.contains(excluded), "unexpected noise lemma: \(excluded)")
        }
        XCTAssertTrue(keys.contains("read"))
        XCTAssertTrue(keys.contains("the"))
        XCTAssertTrue(keys.contains("book"))
        XCTAssertTrue(keys.contains("visible"))
        XCTAssertTrue(keys.contains("prose"))
    }

    func testLexicalIdentitySeparatesPartOfSpeechAndReservesSenseKey() {
        let noun = VocabularyLexicalItemID(language: "en", lemma: "book", partOfSpeech: .noun)
        let verb = VocabularyLexicalItemID(language: "en", lemma: "book", partOfSpeech: .verb)
        let futureSense = VocabularyLexicalItemID(
            language: "en",
            lemma: "bank",
            partOfSpeech: .noun,
            senseKey: "river"
        )

        XCTAssertNotEqual(noun, verb)
        XCTAssertNotEqual(noun.canonicalKey, verb.canonicalKey)
        XCTAssertNil(noun.senseKey)
        XCTAssertTrue(futureSense.canonicalKey.hasSuffix("|river"))
    }
}
