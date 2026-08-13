import Cocoa
import PDFKit
import LeafReaderCore

enum PDFTextQuoteAnchorBuilder {
    static func make(
        pageIndex: Int,
        selection: PDFSelection,
        page: PDFPage,
        sourceText: String
    ) -> TextQuoteAnchor? {
        let rangeCount = selection.numberOfTextRanges(on: page)
        guard rangeCount > 0 else { return nil }
        var combinedRange = selection.range(at: 0, on: page)
        guard combinedRange.location != NSNotFound else { return nil }
        if rangeCount > 1 {
            for index in 1..<rangeCount {
                let range = selection.range(at: index, on: page)
                guard range.location != NSNotFound else { continue }
                combinedRange = NSUnionRange(combinedRange, range)
            }
        }
        return make(pageIndex: pageIndex, sourceRange: combinedRange, sourceText: sourceText)
    }

    static func make(pageIndex: Int, sourceRange: NSRange, sourceText: String) -> TextQuoteAnchor? {
        TextQuoteAnchor(unitOrdinal: pageIndex, sourceRange: sourceRange, sourceText: sourceText)
    }
}

struct PDFWordRecordStore {
    private static let metadataRepairVersion = 1
    private let defaults: UserDefaults
    private let documentID: String
    private let storageKey: String
    private let migrationKey: String
    private let metadataRepairKey: String

    init(fileMD5: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        documentID = fileMD5
        storageKey = "bookSession.\(fileMD5).wordRecords"
        migrationKey = "\(storageKey).sqliteMigrated"
        metadataRepairKey = "\(storageKey).metadataRepairVersion"
    }

    var needsMetadataRepair: Bool {
        defaults.integer(forKey: metadataRepairKey) < Self.metadataRepairVersion
    }

    func markMetadataRepairCompleted() {
        defaults.set(Self.metadataRepairVersion, forKey: metadataRepairKey)
    }

    func load() -> [StoredPDFWordRecord] {
        let sqliteRecords = WordRecordSQLiteStore.shared.loadPDFRecords(documentID: documentID)
        if !sqliteRecords.isEmpty {
            return sqliteRecords
        }
        if defaults.bool(forKey: migrationKey) {
            return []
        }
        let legacyRecords = loadLegacyRecords()
        if !legacyRecords.isEmpty {
            if WordRecordSQLiteStore.shared.savePDFRecords(documentID: documentID, records: legacyRecords) {
                defaults.set(true, forKey: migrationKey)
            }
            return legacyRecords
        }
        return legacyRecords
    }

    @discardableResult
    func save(_ records: [StoredPDFWordRecord]) -> Bool {
        let didSave = WordRecordSQLiteStore.shared.savePDFRecords(documentID: documentID, records: records)
        if didSave {
            defaults.set(true, forKey: migrationKey)
        }
        return didSave
    }

    @discardableResult
    func upsert(_ record: StoredPDFWordRecord) -> Bool {
        let didSave = WordRecordSQLiteStore.shared.upsertPDFRecord(documentID: documentID, record: record)
        if didSave {
            defaults.set(true, forKey: migrationKey)
        }
        return didSave
    }

    @discardableResult
    func upsert(_ records: [StoredPDFWordRecord]) -> Bool {
        let didSave = WordRecordSQLiteStore.shared.upsertPDFRecords(documentID: documentID, records: records)
        if didSave {
            defaults.set(true, forKey: migrationKey)
        }
        return didSave
    }

    @discardableResult
    func delete(ids: [String]) -> Bool {
        let didDelete = WordRecordSQLiteStore.shared.deletePDFRecords(documentID: documentID, ids: ids)
        if didDelete {
            defaults.set(true, forKey: migrationKey)
        }
        return didDelete
    }

    private func loadLegacyRecords() -> [StoredPDFWordRecord] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([StoredPDFWordRecord].self, from: data)
        } catch {
            NSLog("LeafReader word records: failed to decode legacy PDF records (documentID=%@, error=%@)", documentID, error.localizedDescription)
            return []
        }
    }

    func recordKey(pageIndex: Int, bounds: CGRect) -> String {
        "\(pageIndex):\(Int(bounds.origin.x.rounded())):\(Int(bounds.origin.y.rounded())):\(Int(bounds.width.rounded())):\(Int(bounds.height.rounded()))"
    }

    func recordKey(record: StoredPDFWordRecord) -> String {
        record.occurrenceKey
    }

    func existingRecord(
        in records: [StoredPDFWordRecord],
        pageIndex: Int,
        bounds: CGRect,
        textAnchor: TextQuoteAnchor? = nil
    ) -> StoredPDFWordRecord? {
        if let textAnchor {
            let semanticKey = "text:\(textAnchor.unitOrdinal):\(textAnchor.sourceStart):\(textAnchor.sourceLength)"
            if let record = records.first(where: { recordKey(record: $0) == semanticKey }) {
                return record
            }
        }
        let key = recordKey(pageIndex: pageIndex, bounds: bounds)
        return records.first { record in
            recordKey(pageIndex: record.pageIndex, bounds: record.bounds.cgRect) == key
        }
    }

    func linkedWordBubbles(from records: [StoredPDFWordRecord]) -> [AIChatPanel.LinkedWordBubble] {
        var seenWords = Set<String>()
        return records
            .filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.createdAt < $1.createdAt }
            .filter {
                let key = $0.vocabularyID ?? VocabularyTextPolicy.canonicalVocabularyKey($0.word)
                return seenWords.insert(key).inserted
            }
            .map {
                AIChatPanel.LinkedWordBubble(
                    id: $0.id,
                    word: $0.word,
                    question: $0.question,
                    answer: $0.answer
                )
            }
    }
}
