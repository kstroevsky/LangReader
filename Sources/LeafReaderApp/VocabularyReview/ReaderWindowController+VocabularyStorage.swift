import Foundation
import LeafReaderCore

struct VocabularyRecordMutationResult {
    let didUpdatePDF: Bool
    let didUpdateWeb: Bool

    var didUpdate: Bool {
        didUpdatePDF || didUpdateWeb
    }
}

extension ReaderWindowController {
    func loadStoredWordRecords() -> [StoredPDFWordRecord] {
        guard let store = pdfWordRecordStore else { return [] }
        let records = ReaderPerformance.measure(.vocabularyRecordLoad) {
            store.load()
        }
        updatePDFVocabularyDocumentLanguage(from: records)
        return records
    }

    func saveStoredWordRecords() {
        scheduleStoredWordRecordsSave()
    }

    func saveStoredWordRecord(_ record: StoredPDFWordRecord) {
        let didSave = ReaderPerformance.measure(.vocabularyDatabaseWrite) {
            pdfWordRecordStore?.upsert(record) == true
        }
        if !didSave {
            saveStoredWordRecords()
        }
    }

    func loadStoredWebWordRecords() -> [StoredWebWordRecord] {
        guard let store = webWordRecordStore else { return [] }
        return ReaderPerformance.measure(.vocabularyRecordLoad) {
            store.load()
        }
    }

    func saveStoredWebWordRecords() {
        scheduleStoredWebWordRecordsSave()
    }

    func saveStoredWebWordRecord(_ record: StoredWebWordRecord) {
        let didSave = ReaderPerformance.measure(.vocabularyDatabaseWrite) {
            webWordRecordStore?.upsert(record) == true
        }
        if !didSave {
            saveStoredWebWordRecords()
        }
    }

    func deleteStoredWordRecords(ids: [String]) {
        if pdfWordRecordStore?.delete(ids: ids) != true {
            saveStoredWordRecords()
        }
    }

    func deleteStoredWebWordRecords(ids: [String]) {
        if webWordRecordStore?.delete(ids: ids) != true {
            saveStoredWebWordRecords()
        }
    }

    @discardableResult
    func updateStoredVocabularyRecords(
        ids: Set<String>,
        updatePDF: (inout StoredPDFWordRecord) -> Bool,
        updateWeb: (inout StoredWebWordRecord) -> Bool
    ) -> VocabularyRecordMutationResult {
        var updatedPDFRecords: [StoredPDFWordRecord] = []
        for index in storedWordRecords.indices where ids.contains(storedWordRecords[index].id) {
            guard updatePDF(&storedWordRecords[index]) else { continue }
            updatedPDFRecords.append(storedWordRecords[index])
        }
        if !updatedPDFRecords.isEmpty {
            let didSave = ReaderPerformance.measure(.vocabularyDatabaseWrite) {
                pdfWordRecordStore?.upsert(updatedPDFRecords) == true
            }
            if !didSave {
                saveStoredWordRecords()
            }
        }

        var updatedWebRecords: [StoredWebWordRecord] = []
        for index in storedWebWordRecords.indices where ids.contains(storedWebWordRecords[index].id) {
            guard updateWeb(&storedWebWordRecords[index]) else { continue }
            updatedWebRecords.append(storedWebWordRecords[index])
        }
        if !updatedWebRecords.isEmpty {
            let didSave = ReaderPerformance.measure(.vocabularyDatabaseWrite) {
                webWordRecordStore?.upsert(updatedWebRecords) == true
            }
            if !didSave {
                saveStoredWebWordRecords()
            }
        }

        return VocabularyRecordMutationResult(
            didUpdatePDF: !updatedPDFRecords.isEmpty,
            didUpdateWeb: !updatedWebRecords.isEmpty
        )
    }

    func scheduleStoredWordRecordsSave() {
        pdfWordRecordsSaveTask.schedule { [weak self] in
            self?.persistStoredWordRecordsSnapshot()
        }
    }

    func scheduleStoredWebWordRecordsSave() {
        webWordRecordsSaveTask.schedule { [weak self] in
            self?.persistStoredWebWordRecordsSnapshot()
        }
    }

    func flushStoredWordRecordsSave() {
        pdfWordRecordsSaveTask.flush()
    }

    func flushStoredWebWordRecordsSave() {
        webWordRecordsSaveTask.flush()
    }

    private func persistStoredWordRecordsSnapshot() {
        ReaderPerformance.measure(.vocabularyDatabaseWrite) {
            pdfWordRecordStore?.save(storedWordRecords)
        }
    }

    private func persistStoredWebWordRecordsSnapshot() {
        ReaderPerformance.measure(.vocabularyDatabaseWrite) {
            webWordRecordStore?.save(storedWebWordRecords)
        }
    }

    func flushCurrentBookWordRecordSaves() {
        flushStoredWordRecordsSave()
        flushStoredWebWordRecordsSave()
    }
}
