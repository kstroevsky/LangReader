import Foundation
import LeafReaderCore

enum VocabularyReviewScoringService {
    // One exported vocabulary card may aggregate several saved word records. Keep the
    // exported card's SRS state pinned to the earliest due underlying record.
    static func snapshot(
        ids: [String],
        documentKind: ReaderDocumentKind,
        pdfRecords: [StoredPDFWordRecord],
        webRecords: [StoredWebWordRecord]
    ) -> [String: VocabularySRSState] {
        let idSet = Set(ids)
        switch documentKind {
        case .pdf:
            let ownerIDs = pdfLearningOwnerIDs(for: idSet, records: pdfRecords)
            return Dictionary(
                uniqueKeysWithValues: pdfRecords
                    .filter { ownerIDs.contains(pdfLearningOwnerID(for: $0)) }
                    .map { ($0.id, $0.srs ?? VocabularySRSState.initial(createdAt: $0.createdAt)) }
            )
        default:
            return Dictionary(
                uniqueKeysWithValues: webRecords
                    .filter { idSet.contains($0.id) }
                    .map { ($0.id, $0.srs ?? VocabularySRSState.initial(createdAt: $0.createdAt)) }
            )
        }
    }

    static func restore(
        snapshot: [String: VocabularySRSState],
        documentKind: ReaderDocumentKind,
        pdfRecords: inout [StoredPDFWordRecord],
        webRecords: inout [StoredWebWordRecord],
        exportRecords: inout [VocabularyExportRecord]
    ) {
        let idSet = Set(snapshot.keys)
        switch documentKind {
        case .pdf:
            let ownerIDs = pdfLearningOwnerIDs(for: idSet, records: pdfRecords)
            for ownerID in ownerIDs {
                let ownerRecords = pdfRecords.indices.filter {
                    pdfLearningOwnerID(for: pdfRecords[$0]) == ownerID
                }
                guard let restored = ownerRecords.compactMap({ snapshot[pdfRecords[$0].id] }).min(by: {
                    $0.dueDate < $1.dueDate
                }) else { continue }
                for index in ownerRecords {
                    pdfRecords[index].srs = restored
                }
            }
        default:
            for index in webRecords.indices where idSet.contains(webRecords[index].id) {
                webRecords[index].srs = snapshot[webRecords[index].id]
            }
        }

        refreshExportRecords(&exportRecords, ids: idSet) { old in
            old.ids.compactMap { snapshot[$0] }.min { $0.dueDate < $1.dueDate } ?? old.srs
        }
    }

    static func update(
        ids: [String],
        grade: Int,
        documentKind: ReaderDocumentKind,
        pdfRecords: inout [StoredPDFWordRecord],
        webRecords: inout [StoredWebWordRecord],
        exportRecords: inout [VocabularyExportRecord]
    ) {
        let idSet = Set(ids)
        switch documentKind {
        case .pdf:
            let ownerIDs = pdfLearningOwnerIDs(for: idSet, records: pdfRecords)
            for ownerID in ownerIDs {
                let ownerRecords = pdfRecords.indices.filter {
                    pdfLearningOwnerID(for: pdfRecords[$0]) == ownerID
                }
                guard let firstIndex = ownerRecords.first else { continue }
                let current = ownerRecords
                    .map { pdfRecords[$0].srs ?? VocabularySRSState.initial(createdAt: pdfRecords[$0].createdAt) }
                    .min { $0.dueDate < $1.dueDate }
                    ?? VocabularySRSState.initial(createdAt: pdfRecords[firstIndex].createdAt)
                let reviewed = current.reviewed(grade: grade)
                for index in ownerRecords {
                    pdfRecords[index].srs = reviewed
                }
            }
        default:
            for index in webRecords.indices where idSet.contains(webRecords[index].id) {
                let current = webRecords[index].srs ?? VocabularySRSState.initial(createdAt: webRecords[index].createdAt)
                webRecords[index].srs = current.reviewed(grade: grade)
            }
        }

        refreshExportRecords(&exportRecords, ids: idSet) { old in
            state(
                ids: old.ids,
                fallback: old.srs,
                documentKind: documentKind,
                pdfRecords: pdfRecords,
                webRecords: webRecords
            )
        }
    }

    static func state(
        ids: [String],
        fallback: VocabularySRSState,
        documentKind: ReaderDocumentKind,
        pdfRecords: [StoredPDFWordRecord],
        webRecords: [StoredWebWordRecord]
    ) -> VocabularySRSState {
        let idSet = Set(ids)
        let states: [VocabularySRSState]
        switch documentKind {
        case .pdf:
            let ownerIDs = pdfLearningOwnerIDs(for: idSet, records: pdfRecords)
            states = pdfRecords
                .filter { ownerIDs.contains(pdfLearningOwnerID(for: $0)) }
                .map { $0.srs ?? VocabularySRSState.initial(createdAt: $0.createdAt) }
        default:
            states = webRecords
                .filter { idSet.contains($0.id) }
                .map { $0.srs ?? VocabularySRSState.initial(createdAt: $0.createdAt) }
        }
        return states.min { $0.dueDate < $1.dueDate } ?? fallback
    }

    private static func refreshExportRecords(
        _ exportRecords: inout [VocabularyExportRecord],
        ids: Set<String>,
        stateForRecord: (VocabularyExportRecord) -> VocabularySRSState
    ) {
        for index in exportRecords.indices where !Set(exportRecords[index].ids).isDisjoint(with: ids) {
            let old = exportRecords[index]
            exportRecords[index] = VocabularyExportRecord(
                ids: old.ids,
                learningOwnerIDs: old.learningOwnerIDs,
                word: old.word,
                language: old.language,
                lemma: old.lemma,
                lexicalKey: old.lexicalKey,
                partOfSpeech: old.partOfSpeech,
                forms: old.forms,
                answer: old.answer,
                dictionaryTags: old.dictionaryTags,
                dictionaryFrequency: old.dictionaryFrequency,
                location: old.location,
                context: old.context,
                createdAt: old.createdAt,
                srs: stateForRecord(old),
                occurrences: old.occurrences
            )
        }
    }

    private static func pdfLearningOwnerID(for record: StoredPDFWordRecord) -> VocabularyLearningOwnerID {
        VocabularyLearningOwnerID(record.vocabularyID ?? record.id)
    }

    private static func pdfLearningOwnerIDs(
        for occurrenceIDs: Set<String>,
        records: [StoredPDFWordRecord]
    ) -> Set<VocabularyLearningOwnerID> {
        Set(records.lazy.filter { occurrenceIDs.contains($0.id) }.map(pdfLearningOwnerID))
    }
}
