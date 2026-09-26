import Foundation
import LeafReaderCore

struct VocabularyDocumentLanguageStore {
    private let defaults: UserDefaults
    private let key: String

    init(documentID: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = "bookSession.\(documentID).vocabularyLanguage"
    }

    func load() -> VocabularyDocumentLanguageMetadata? {
        guard let data = defaults.data(forKey: key),
              let metadata = try? JSONDecoder().decode(VocabularyDocumentLanguageMetadata.self, from: data),
              metadata.isCompatible else {
            return nil
        }
        return metadata
    }

    @discardableResult
    func save(resolution: VocabularyLanguageResolution) -> Bool {
        guard resolution.languageID != nil,
              let data = try? JSONEncoder().encode(VocabularyDocumentLanguageMetadata(resolution: resolution)) else {
            return false
        }
        defaults.set(data, forKey: key)
        return true
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
