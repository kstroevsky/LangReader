import CoreGraphics
import Foundation
import XCTest
@testable import LeafReaderCore

final class VocabularyOccurrenceSavePlannerXCTests: XCTestCase {
    func testSemanticOccurrenceKeyIgnoresCachedGeometry() throws {
        let source = "alpha beta gamma"
        let range = (source as NSString).range(of: "beta")
        let anchor = try XCTUnwrap(TextQuoteAnchor(
            unitOrdinal: 2,
            sourceRange: range,
            sourceText: source
        ))
        let first = record(id: "first", pageIndex: 2, rect: CGRect(x: 1, y: 2, width: 3, height: 4), anchor: anchor)
        let relaidOut = record(id: "second", pageIndex: 2, rect: CGRect(x: 90, y: 80, width: 70, height: 60), anchor: anchor)

        XCTAssertEqual(first.occurrenceKey, relaidOut.occurrenceKey)
        XCTAssertEqual(first.occurrenceKey, "text:2:\(range.location):\(range.length)")
    }

    func testPlanCountsFoundOccurrencesAndInsertsOnlyNewStableKeys() throws {
        let source = "alpha beta gamma delta"
        let selected = try semanticRecord(id: "selected", text: "beta", pageIndex: 0, source: source)
        let selectedDuplicate = try semanticRecord(id: "selected-duplicate", text: "beta", pageIndex: 0, source: source)
        let newA = try semanticRecord(id: "new-a", text: "gamma", pageIndex: 0, source: source)
        let newADuplicate = try semanticRecord(id: "new-a-duplicate", text: "gamma", pageIndex: 0, source: source)
        let newB = record(id: "new-b", pageIndex: 3, rect: CGRect(x: 10.2, y: 20.2, width: 30.2, height: 40.2))

        let plan = VocabularyOccurrenceSavePlanner.plan(
            selectedRecord: selected,
            discoveredRecords: [selectedDuplicate, newA, newADuplicate, newB],
            existingRecordKeys: [selected.occurrenceKey]
        )

        XCTAssertEqual(plan.foundCount, 3)
        XCTAssertEqual(plan.recordsToInsert.map(\.id), ["new-a", "new-b"])
    }

    private func semanticRecord(
        id: String,
        text: String,
        pageIndex: Int,
        source: String
    ) throws -> StoredPDFWordRecord {
        let range = (source as NSString).range(of: text)
        let anchor = try XCTUnwrap(TextQuoteAnchor(
            unitOrdinal: pageIndex,
            sourceRange: range,
            sourceText: source
        ))
        return record(id: id, pageIndex: pageIndex, rect: .zero, anchor: anchor)
    }

    private func record(
        id: String,
        pageIndex: Int,
        rect: CGRect,
        anchor: TextQuoteAnchor? = nil
    ) -> StoredPDFWordRecord {
        StoredPDFWordRecord(
            id: id,
            vocabularyID: "vocabulary",
            word: "beta",
            lemma: "beta",
            surfaceForm: "beta",
            pageIndex: pageIndex,
            bounds: StoredPDFWordRect(rect),
            textAnchor: anchor,
            context: nil,
            question: "",
            answer: "",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            srs: VocabularySRSState.initial(createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        )
    }
}
