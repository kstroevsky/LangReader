import Foundation
import LeafReaderCore

struct VocabularyPreparationSessionStore {
    private let defaults: UserDefaults
    private let key: String

    init(documentID: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = "bookSession.\(documentID).vocabularyPreparation"
    }

    func load() -> VocabularyPreparationSession? {
        guard let data = defaults.data(forKey: key),
              let session = try? JSONDecoder().decode(VocabularyPreparationSession.self, from: data) else {
            return nil
        }
        return session
    }

    func save(_ session: VocabularyPreparationSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
