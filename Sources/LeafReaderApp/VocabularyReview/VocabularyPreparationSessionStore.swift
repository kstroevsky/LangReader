import Foundation
import LeafReaderCore

struct VocabularyPreparationArchivedSession: Equatable {
    let archivedAt: Date
    let reason: String
    let session: VocabularyPreparationSession
}

struct VocabularyPreparationSessionStore {
    private struct ArchivedPayload: Codable, Equatable {
        let archivedAt: Date
        let reason: String
        let payload: Data
    }

    private struct Envelope: Codable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        let activePayload: Data
        /// Exact pre-envelope bytes are retained until the first compatibility
        /// decision. A normal save (for example invitation state) therefore
        /// cannot destroy a legacy session before it can be archived.
        let legacySourcePayload: Data?
        let archives: [ArchivedPayload]
    }

    private let defaults: UserDefaults
    private let key: String

    init(documentID: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = "bookSession.\(documentID).vocabularyPreparation"
    }

    func load() -> VocabularyPreparationSession? {
        guard let envelope = loadEnvelope() else { return nil }
        return try? JSONDecoder().decode(VocabularyPreparationSession.self, from: envelope.activePayload)
    }

    @discardableResult
    func save(_ session: VocabularyPreparationSession) -> Bool {
        guard let activePayload = try? JSONEncoder().encode(session) else { return false }
        let previous = loadEnvelope()
        let envelope = Envelope(
            schemaVersion: Envelope.currentSchemaVersion,
            activePayload: activePayload,
            legacySourcePayload: previous?.legacySourcePayload,
            archives: previous?.archives ?? []
        )
        guard let data = try? JSONEncoder().encode(envelope) else { return false }
        defaults.set(data, forKey: key)
        return true
    }

    /// Atomically archives the exact payload that produced the incompatible
    /// active session and installs a fresh session. The UserDefaults value is
    /// replaced only after both inner and outer encodings have succeeded.
    @discardableResult
    func archiveAndReplace(
        with session: VocabularyPreparationSession,
        reason: String,
        archivedAt: Date = Date()
    ) -> Bool {
        guard let activePayload = try? JSONEncoder().encode(session) else { return false }
        guard let previous = loadEnvelope() else { return save(session) }
        let incompatiblePayload = previous.legacySourcePayload ?? previous.activePayload
        var archives = previous.archives
        if !archives.contains(where: { $0.payload == incompatiblePayload }) {
            archives.append(ArchivedPayload(
                archivedAt: archivedAt,
                reason: reason,
                payload: incompatiblePayload
            ))
        }
        let envelope = Envelope(
            schemaVersion: Envelope.currentSchemaVersion,
            activePayload: activePayload,
            legacySourcePayload: nil,
            archives: archives
        )
        guard let data = try? JSONEncoder().encode(envelope) else { return false }
        defaults.set(data, forKey: key)
        return true
    }

    func archivedSessions() -> [VocabularyPreparationArchivedSession] {
        guard let envelope = loadEnvelope() else { return [] }
        return envelope.archives.compactMap { archive in
            guard let session = try? JSONDecoder().decode(
                VocabularyPreparationSession.self,
                from: archive.payload
            ) else { return nil }
            return VocabularyPreparationArchivedSession(
                archivedAt: archive.archivedAt,
                reason: archive.reason,
                session: session
            )
        }
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    private func loadEnvelope() -> Envelope? {
        guard let data = defaults.data(forKey: key) else { return nil }
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
           envelope.schemaVersion == Envelope.currentSchemaVersion,
           (try? JSONDecoder().decode(
            VocabularyPreparationSession.self,
            from: envelope.activePayload
           )) != nil {
            return envelope
        }
        guard (try? JSONDecoder().decode(VocabularyPreparationSession.self, from: data)) != nil else {
            return nil
        }
        return Envelope(
            schemaVersion: Envelope.currentSchemaVersion,
            activePayload: data,
            legacySourcePayload: data,
            archives: []
        )
    }
}
