import Foundation
import NaturalLanguage
import LeafReaderCore

struct StoredWebWordRecord: Codable, Sendable {
    let id: String
    var vocabularyID: String? = nil
    let word: String
    var lemma: String? = nil
    var surfaceForm: String? = nil
    let context: String
    let occurrenceIndex: Int?
    let scrollProgress: Double
    var question: String
    var answer: String
    var dictionaryTags: String? = nil
    var dictionaryFrequency: Int? = nil
    let createdAt: Date
    var srs: VocabularySRSState?

    var vocabularyGroupingText: String {
        guard let lemma = lemma?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lemma.isEmpty else { return word }
        return lemma
    }

    var occurrenceSurfaceForm: String {
        guard let surfaceForm = surfaceForm?.trimmingCharacters(in: .whitespacesAndNewlines),
              !surfaceForm.isEmpty else { return word }
        return surfaceForm
    }
}

struct WebWordRecordMetadataRepair {
    struct Result {
        let records: [StoredWebWordRecord]
        let didChange: Bool
    }

    typealias LemmaResolver = @Sendable (String, NLLanguage) -> String

    static func repair(
        _ records: [StoredWebWordRecord],
        language: NLLanguage,
        lemmaResolver: LemmaResolver = { GermanLemmaResolver.lemma(for: $0, language: $1) }
    ) -> Result {
        var didChange = false
        var enriched = records.map { record -> StoredWebWordRecord in
            var record = record
            let surface = record.occurrenceSurfaceForm
            if record.surfaceForm != surface { didChange = true }
            record.surfaceForm = surface
            let lemma = record.lemma?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedLemma = lemma.flatMap { $0.isEmpty ? nil : $0 }
                ?? lemmaResolver(surface, language)
            if record.lemma != resolvedLemma { didChange = true }
            record.lemma = resolvedLemma
            return record
        }

        let orderedIndices = enriched.indices.sorted {
            let lhs = enriched[$0]
            let rhs = enriched[$1]
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id < rhs.id
        }
        var vocabularyIDByKey: [String: String] = [:]
        for index in orderedIndices {
            let record = enriched[index]
            let key = GermanLemmaResolver.groupingKey(
                word: record.word,
                lemma: record.lemma,
                language: language
            )
            guard !key.isEmpty, vocabularyIDByKey[key] == nil,
                  let vocabularyID = record.vocabularyID,
                  !vocabularyID.isEmpty else { continue }
            vocabularyIDByKey[key] = vocabularyID
        }
        for index in orderedIndices {
            let record = enriched[index]
            let key = GermanLemmaResolver.groupingKey(
                word: record.word,
                lemma: record.lemma,
                language: language
            )
            guard !key.isEmpty else { continue }
            let vocabularyID = vocabularyIDByKey[key] ?? record.id
            vocabularyIDByKey[key] = vocabularyID
            if enriched[index].vocabularyID != vocabularyID { didChange = true }
            enriched[index].vocabularyID = vocabularyID
        }

        return Result(records: enriched, didChange: didChange)
    }
}

struct WebWordRecordStore {
    private static let metadataRepairVersion = 1
    private let defaults: UserDefaults
    private let documentID: String
    private let storageKey: String
    private let migrationKey: String
    private let metadataRepairKey: String

    init(fileMD5: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        documentID = fileMD5
        storageKey = "bookSession.\(fileMD5).webWordRecords"
        migrationKey = "\(storageKey).sqliteMigrated"
        metadataRepairKey = "\(storageKey).metadataRepairVersion"
    }

    var needsMetadataRepair: Bool {
        defaults.integer(forKey: metadataRepairKey) < Self.metadataRepairVersion
    }

    func markMetadataRepairCompleted() {
        defaults.set(Self.metadataRepairVersion, forKey: metadataRepairKey)
    }

    func load() -> [StoredWebWordRecord] {
        let sqliteRecords = WordRecordSQLiteStore.shared.loadWebRecords(documentID: documentID)
        if !sqliteRecords.isEmpty {
            return sqliteRecords
        }
        if defaults.bool(forKey: migrationKey) {
            return []
        }
        let legacyRecords = loadLegacyRecords()
        if !legacyRecords.isEmpty {
            if WordRecordSQLiteStore.shared.saveWebRecords(documentID: documentID, records: legacyRecords) {
                defaults.set(true, forKey: migrationKey)
            }
            return legacyRecords
        }
        return legacyRecords
    }

    @discardableResult
    func save(_ records: [StoredWebWordRecord]) -> Bool {
        let didSave = WordRecordSQLiteStore.shared.saveWebRecords(documentID: documentID, records: records)
        if didSave {
            defaults.set(true, forKey: migrationKey)
        }
        return didSave
    }

    @discardableResult
    func upsert(_ record: StoredWebWordRecord) -> Bool {
        upsert([record])
    }

    @discardableResult
    func upsert(_ records: [StoredWebWordRecord]) -> Bool {
        let didSave = WordRecordSQLiteStore.shared.upsertWebRecords(documentID: documentID, records: records)
        if didSave {
            defaults.set(true, forKey: migrationKey)
        }
        return didSave
    }

    @discardableResult
    func delete(ids: [String]) -> Bool {
        let didDelete = WordRecordSQLiteStore.shared.deleteWebRecords(documentID: documentID, ids: ids)
        if didDelete {
            defaults.set(true, forKey: migrationKey)
        }
        return didDelete
    }

    private func loadLegacyRecords() -> [StoredWebWordRecord] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([StoredWebWordRecord].self, from: data)
        } catch {
            NSLog("LeafReader word records: failed to decode legacy web records (documentID=%@, error=%@)", documentID, error.localizedDescription)
            return []
        }
    }

    func existingRecord(in records: [StoredWebWordRecord], word: String, context: String, occurrenceIndex: Int? = nil) -> StoredWebWordRecord? {
        let normalizedWord = normalize(word)
        let normalizedContext = normalize(context)
        return records.first {
            normalize($0.word) == normalizedWord
                && normalize($0.context) == normalizedContext
                && ($0.occurrenceIndex == occurrenceIndex || $0.occurrenceIndex == nil || occurrenceIndex == nil)
        }
    }

    func linkedWordBubbles(from records: [StoredWebWordRecord]) -> [AIChatPanel.LinkedWordBubble] {
        var seenVocabulary = Set<String>()
        return records
            .filter { !$0.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.createdAt < $1.createdAt }
            .filter {
                let key = $0.vocabularyID ?? VocabularyTextPolicy.canonicalVocabularyKey($0.vocabularyGroupingText)
                return seenVocabulary.insert(key).inserted
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

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
