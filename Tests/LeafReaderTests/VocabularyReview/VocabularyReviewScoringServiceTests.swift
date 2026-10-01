import Foundation
import LeafReaderCore

struct StoredWebWordRecord {
    let id: String
    var srs: VocabularySRSState?
    let createdAt: Date
}

private func assert(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("VocabularyReviewScoringServiceTests failed: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct VocabularyReviewScoringServiceTestRunner {
    static func main() {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let ownerID = "legacy-shared-owner"
        var pdfRecords = [
            StoredPDFWordRecord(
                id: "occurrence-a",
                vocabularyID: ownerID,
                word: "lief",
                pageIndex: 0,
                bounds: StoredPDFWordRect(.zero),
                question: "",
                answer: "ran",
                createdAt: createdAt,
                srs: VocabularySRSState.initial(createdAt: createdAt)
            ),
            StoredPDFWordRecord(
                id: "occurrence-b",
                vocabularyID: ownerID,
                word: "lief",
                pageIndex: 1,
                bounds: StoredPDFWordRect(.zero),
                question: "",
                answer: "ran",
                createdAt: createdAt,
                srs: VocabularySRSState.initial(createdAt: createdAt)
            )
        ]
        var webRecords: [StoredWebWordRecord] = []
        var exportRecords = [VocabularyExportRecord(
            ids: ["occurrence-a", "occurrence-b"],
            learningOwnerIDs: [VocabularyLearningOwnerID(ownerID)],
            word: "lief",
            answer: "ran",
            dictionaryTags: nil,
            dictionaryFrequency: nil,
            location: "",
            context: "",
            createdAt: createdAt,
            srs: VocabularySRSState.initial(createdAt: createdAt)
        )]

        let snapshot = VocabularyReviewScoringService.snapshot(
            ids: ["occurrence-a"],
            documentKind: .pdf,
            pdfRecords: pdfRecords,
            webRecords: webRecords
        )
        assert(Set(snapshot.keys) == Set(["occurrence-a", "occurrence-b"]), "undo snapshots should close over the complete PDF learning owner")

        VocabularyReviewScoringService.update(
            ids: ["occurrence-a"],
            grade: 3,
            documentKind: .pdf,
            pdfRecords: &pdfRecords,
            webRecords: &webRecords,
            exportRecords: &exportRecords
        )
        assert(pdfRecords.allSatisfy { $0.srs?.reviewCount == 1 }, "one review action should score a shared PDF learning owner exactly once")

        VocabularyReviewScoringService.restore(
            snapshot: snapshot,
            documentKind: .pdf,
            pdfRecords: &pdfRecords,
            webRecords: &webRecords,
            exportRecords: &exportRecords
        )
        assert(pdfRecords.allSatisfy { $0.srs?.reviewCount == 0 }, "undo should restore every occurrence of the shared learning owner")
        print("VocabularyReviewScoringServiceTests passed")
    }
}
