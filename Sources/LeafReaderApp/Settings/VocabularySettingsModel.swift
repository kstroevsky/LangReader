import Foundation
import Observation
import LeafReaderCore

@MainActor
@Observable
final class VocabularySettingsModel {
    private let store: any VocabularyReaderPriorStoring
    private(set) var summaries: [VocabularyReaderPriorSummary] = []
    private(set) var isLoading = false

    init(store: any VocabularyReaderPriorStoring = VocabularyReaderPriorStore.shared) {
        self.store = store
        refresh()
    }

    func refresh() {
        let store = store
        isLoading = true
        Task { [weak self] in
            let summaries = await Task.detached { store.summaries() }.value
            guard let self else { return }
            self.summaries = summaries
            self.isLoading = false
        }
    }

    func reset(languageCode: String) {
        let store = store
        isLoading = true
        Task { [weak self] in
            _ = await Task.detached { store.reset(languageCode: languageCode) }.value
            guard let self else { return }
            self.refresh()
        }
    }
}
