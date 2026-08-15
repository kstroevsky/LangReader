import NaturalLanguage
import XCTest
import LeafReaderCore

final class VocabularyDocumentLemmaIndexXCTests: XCTestCase {
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
        let develop = try XCTUnwrap(summaries.first { $0.canonicalKey == "develop" })
        XCTAssertEqual(develop.occurrenceCount, 3)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: develop.observedForms.map { ($0.surface.lowercased(), $0.occurrenceCount) }), [
            "develop": 1,
            "developed": 1,
            "developing": 1
        ])
        XCTAssertEqual(summaries.first { $0.canonicalKey == "development" }?.occurrenceCount, 1)
    }

    func testOrdinaryEnglishWordsAreNotClassifiedAsConfidentNames() throws {
        let index = try XCTUnwrap(VocabularyDocumentLemmaIndex(
            texts: ["They develop tools while readers learn vocabulary."],
            language: .english
        ))

        let summaries = index.lemmaSummaries()
        XCTAssertFalse(try XCTUnwrap(summaries.first { $0.canonicalKey == "develop" }).isConfidentName)
        XCTAssertFalse(try XCTUnwrap(summaries.first { $0.canonicalKey == "tool" }).isConfidentName)
        XCTAssertFalse(try XCTUnwrap(summaries.first { $0.canonicalKey == "vocabulary" }).isConfidentName)
    }

    func testInventorySummariesAggregateAcrossUnitsAndRepairPDFLineWraps() throws {
        let index = try XCTUnwrap(VocabularyDocumentLemmaIndex(
            texts: ["A remark was develop-\ned here.", "Later they developed it again."],
            language: .english
        ))

        let develop = try XCTUnwrap(index.lemmaSummaries().first { $0.canonicalKey == "develop" })
        XCTAssertEqual(develop.occurrenceCount, 2)
        XCTAssertEqual(develop.representativeRange.unitIndex, 0)
        XCTAssertTrue(develop.observedForms.contains { $0.surface == "developed" && $0.occurrenceCount == 2 })
    }

    func testGermanCompoundsRemainSeparateLemmas() throws {
        let index = try XCTUnwrap(VocabularyDocumentLemmaIndex(
            texts: ["Das Haus steht neben dem Krankenhaus. Die Häuser sind alt."],
            language: .german
        ))
        let keys = Set(index.lemmaSummaries().map(\.canonicalKey))

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
        let keys = Set(index.lemmaSummaries().map(\.canonicalKey))

        for excluded in ["https", "example", "com", "readerpath", "www", "org", "reader", "span", "nbsp", "aaaaaa", "foo", "bar"] {
            XCTAssertFalse(keys.contains(excluded), "unexpected noise lemma: \(excluded)")
        }
        XCTAssertTrue(keys.contains("read"))
        XCTAssertTrue(keys.contains("the"))
        XCTAssertTrue(keys.contains("book"))
        XCTAssertTrue(keys.contains("visible"))
        XCTAssertTrue(keys.contains("prose"))
    }
}
