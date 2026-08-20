import Foundation
import Observation
import AppKit
import LeafReaderCore

@MainActor
protocol VocabularyResearchExportSaving {
    func save(_ data: Data, suggestedFilename: String) throws -> Bool
}

@MainActor
private struct PanelVocabularyResearchExportSaver: VocabularyResearchExportSaving {
    func save(_ data: Data, suggestedFilename: String) throws -> Bool {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedFilename
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        try data.write(to: url, options: .atomic)
        return true
    }
}

@MainActor
@Observable
final class VocabularySettingsModel {
    private let store: any VocabularyReaderPriorStoring
    private let researchStore: any VocabularyResearchEvidenceStoring
    private let researchExportSaver: any VocabularyResearchExportSaving
    private let preferences: UserDefaults
    private(set) var summaries: [VocabularyReaderPriorSummary] = []
    private(set) var isLoading = false
    private(set) var researchPreview = ""
    private(set) var researchRecordCount = 0
    private(set) var exportError: String?
    var firstLanguageCode = ""
    var selfRatedProficiency = ""

    var participantPseudonym: String {
        if let existing = preferences.string(forKey: Self.pseudonymKey), !existing.isEmpty {
            return existing
        }
        let generated = "lr-\(UUID().uuidString.lowercased())"
        preferences.set(generated, forKey: Self.pseudonymKey)
        return generated
    }

    init(
        store: any VocabularyReaderPriorStoring = VocabularyReaderPriorStore.shared,
        researchStore: any VocabularyResearchEvidenceStoring = VocabularyResearchEvidenceStore.shared,
        researchExportSaver: any VocabularyResearchExportSaving = PanelVocabularyResearchExportSaver(),
        preferences: UserDefaults = .standard
    ) {
        self.store = store
        self.researchStore = researchStore
        self.researchExportSaver = researchExportSaver
        self.preferences = preferences
        refresh()
    }

    func refresh() {
        let store = store
        let researchStore = researchStore
        isLoading = true
        Task { [weak self] in
            let (summaries, count) = await Task.detached {
                (store.summaries(), researchStore.recordCount())
            }.value
            guard let self else { return }
            self.summaries = summaries
            self.researchRecordCount = count
            self.isLoading = false
        }
    }

    func resetPseudonym() {
        preferences.removeObject(forKey: Self.pseudonymKey)
        researchPreview = ""
        _ = participantPseudonym
    }

    func previewResearchExport() {
        let startedAt = ProcessInfo.processInfo.systemUptime
        defer {
            ReaderPerformance.record(
                .vocabularyResearchExport,
                milliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            )
        }
        let export = makeResearchExport()
        guard let data = try? export.encoded(), let text = String(data: data, encoding: .utf8) else {
            exportError = AppText.localized("无法生成导出预览。", "Could not generate export preview.")
            return
        }
        researchPreview = text
        exportError = nil
    }

    func saveResearchExport() {
        let export = makeResearchExport()
        guard !export.records.isEmpty else {
            exportError = AppText.localized("没有可导出的测试证据。", "There is no assessment evidence to export.")
            return
        }
        let startedAt = ProcessInfo.processInfo.systemUptime
        defer {
            ReaderPerformance.record(
                .vocabularyResearchExport,
                milliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
            )
        }
        do {
            guard try researchExportSaver.save(
                export.encoded(),
                suggestedFilename: "leafreader-vocabulary-research.json"
            ) else { return }
            exportError = nil
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func makeResearchExport() -> VocabularyResearchExport {
        researchStore.export(profile: VocabularyResearchProfile(
            participantPseudonym: participantPseudonym,
            firstLanguageCode: firstLanguageCode,
            selfRatedProficiency: selfRatedProficiency
        ))
    }

    private static let pseudonymKey = "VocabularyResearch.participantPseudonym.v1"

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
