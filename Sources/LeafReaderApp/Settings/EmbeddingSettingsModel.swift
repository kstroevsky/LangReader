import Foundation
import Observation

/// State behind the AI Analysis (embedding) settings page.
///
/// Structurally the same page as Model — pick a service, fill in what that
/// service needs, supply a key, test it — so it renders through the shared
/// `AIServiceSection` and only supplies what differs. What differs is:
///
///   * the endpoint is **fixed and read-only** for every hosted provider and
///     editable only for "Other";
///   * keys are kept **per provider while the panel is open**, so switching
///     provider and back does not lose a key that was typed but not yet saved;
///   * there is an extra auto-index switch.
@Observable
final class EmbeddingSettingsModel: SettingsPage, AIServiceSettings {
    private let endpointOptions = AISettingsStore.embeddingEndpointOptions

    var selectedOptionID: String {
        didSet {
            guard selectedOptionID != oldValue else { return }
            // Stash whatever was typed for the provider being left, so coming
            // back to it does not show an empty field.
            pendingKeys[oldValue] = apiKey
            if oldValue == AISettingsStore.customEmbeddingEndpointID {
                lastCustomEndpoint = endpoint
                lastCustomModelName = modelName
            }
            loadFields(for: selectedOptionID)
        }
    }

    var endpoint: String
    var modelName: String
    var apiKey: String
    var autoIndexEnabled: Bool

    var isTestingConnection = false

    @ObservationIgnored var onTestConnection: (() -> Void)?

    /// Keys typed during this panel session, by provider.
    @ObservationIgnored private var pendingKeys: [String: String] = [:]
    @ObservationIgnored private var lastCustomEndpoint = ""
    @ObservationIgnored private var lastCustomModelName = ""

    init() {
        let selected = AISettingsStore.selectedEmbeddingEndpointOption
        selectedOptionID = selected.id
        endpoint = selected.endpoint
        modelName = AISettingsStore.embeddingModelName
        apiKey = AISettingsStore.embeddingAPIKeyMigratingLegacyIfNeeded(for: selected.id)
        autoIndexEnabled = AISettingsStore.autoEmbeddingIndexEnabled
        pendingKeys[selected.id] = apiKey
        if selected.id == AISettingsStore.customEmbeddingEndpointID {
            lastCustomEndpoint = selected.endpoint
            lastCustomModelName = modelName
        }
    }

    // MARK: - AIServiceSettings

    var options: [AIServiceOption] {
        endpointOptions.map { AIServiceOption(id: $0.id, title: $0.title) }
    }

    var serviceLabel: String { AppText.localized("向量服务", "Embedding Service") }

    private var isCustomEndpoint: Bool { selectedOptionID == AISettingsStore.customEmbeddingEndpointID }

    /// Always shown: even a hosted provider's URL is worth seeing, which is why
    /// the AppKit page unhid it unconditionally.
    var showsEndpointField: Bool { true }
    var isEndpointEditable: Bool { isCustomEndpoint }
    var endpointLabel: String { AppText.localized("向量接口", "Embedding Endpoint") }
    var endpointPlaceholder: String { "https://api.openai.com/v1/embeddings" }

    var showsModelNameField: Bool { true }
    var modelNameLabel: String { AppText.localized("向量模型", "Embedding Model") }
    var modelNamePlaceholder: String { AISettingsStore.fallbackEmbeddingModelName }

    var apiKeyLabel: String { AppText.localized("向量 API Key", "Embedding API Key") }
    var acceptsAPIKey: Bool { true }

    var testButtonTitle: String { AppText.localized("测试向量连接", "Test Embedding") }

    var sectionIdentifiers: AIServiceSectionIdentifiers {
        AIServiceSectionIdentifiers(
            picker: EmbeddingSettingsAccessibility.providerPicker,
            endpoint: EmbeddingSettingsAccessibility.endpointField,
            modelName: EmbeddingSettingsAccessibility.modelNameField,
            apiKey: EmbeddingSettingsAccessibility.apiKeyField,
            test: EmbeddingSettingsAccessibility.testButton
        )
    }

    func testConnection() {
        onTestConnection?()
    }

    // MARK: - Saving

    func commit() {
        AISettingsStore.saveEmbedding(
            endpoint: endpoint,
            modelName: modelName,
            apiKey: apiKey,
            optionID: selectedOptionID
        )
        AISettingsStore.saveAutoEmbeddingIndexEnabled(autoIndexEnabled)
    }

    // MARK: - Per-provider field contents

    private func loadFields(for optionID: String) {
        guard let option = endpointOptions.first(where: { $0.id == optionID }) else { return }
        if option.id == AISettingsStore.customEmbeddingEndpointID {
            endpoint = lastCustomEndpoint
            modelName = lastCustomModelName
        } else {
            endpoint = option.endpoint
            modelName = option.defaultModel
        }
        apiKey = pendingKeys[option.id] ?? AISettingsStore.embeddingAPIKey(for: option.id)
    }
}
