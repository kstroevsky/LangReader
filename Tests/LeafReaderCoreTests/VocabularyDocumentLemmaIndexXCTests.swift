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
}
