import Foundation
import Observation
import LeafReaderCore

/// State behind the Model settings page.
///
/// Everything on this page is **pending** — nothing is written until Save, so a
/// cancelled panel leaves the model, key and endpoints untouched.
///
/// The page's awkward part is that three of the models keep their endpoint and
/// model name in their *own* defaults keys (custom / Azure, Ollama, local
/// OpenAI), so switching the picker has to swap the two text fields' contents
/// along with the API key. The AppKit page did that by mutating eight views and
/// six layout constraints from `updateCustomModelFields`; here it falls out of
/// `selectedModelID` changing.
@Observable
final class ModelSettingsModel: SettingsPage, AIServiceSettings {
    let models: [AIModelConfig] = AISettingsStore.models

    var selectedModelID: String {
        didSet {
            guard selectedModelID != oldValue else { return }
            loadFields(for: selectedModelID)
        }
    }

    var apiKey: String
    /// The custom / Azure / local-OpenAI base URL. Only meaningful when
    /// `showsEndpointField`.
    var endpoint: String
    /// The model ID or Azure deployment name. Only meaningful when
    /// `showsModelNameField`.
    var modelName: String

    /// Set while a connection test is in flight, so the button cannot be
    /// double-fired.
    var isTestingConnection = false

    /// Runs a "Test Chat" round trip. Supplied by the panel, which owns the
    /// alert presentation.
    @ObservationIgnored var onTestConnection: (() -> Void)?

    init() {
        let selected = AISettingsStore.selectedModel
        selectedModelID = selected.id
        apiKey = AISettingsStore.apiKey(for: selected)
        endpoint = Self.storedEndpoint(for: selected.id)
        modelName = Self.storedModelName(for: selected.id)
    }

    // MARK: - AIServiceSettings

    var options: [AIServiceOption] {
        models.map { AIServiceOption(id: $0.id, title: $0.displayName) }
    }

    /// The section's picker binds here; `selectedModelID` is the page's own
    /// name for it.
    var selectedOptionID: String {
        get { selectedModelID }
        set { selectedModelID = newValue }
    }

    var serviceLabel: String { AppText.model }
    var apiKeyLabel: String { "API Key" }
    var apiKeyNote: String? {
        AppText.localized("该模型在本机运行，无需 API Key。", "This model runs locally and needs no API key.")
    }
    var testButtonTitle: String { AppText.localized("测试模型连接", "Test Chat") }

    var sectionIdentifiers: AIServiceSectionIdentifiers {
        AIServiceSectionIdentifiers(
            picker: ModelSettingsAccessibility.modelPicker,
            endpoint: ModelSettingsAccessibility.endpointField,
            modelName: ModelSettingsAccessibility.modelNameField,
            apiKey: ModelSettingsAccessibility.apiKeyField,
            test: ModelSettingsAccessibility.testButton
        )
    }

    func testConnection() {
        onTestConnection?()
    }

    // MARK: - Derived shape

    var selectedModel: AIModelConfig? {
        models.first { $0.id == selectedModelID }
    }

    private var isCustom: Bool { selectedModelID == AISettingsStore.customModelID }
    private var isOllama: Bool { selectedModelID == AISettingsStore.ollamaModelID }
    private var isLocalOpenAI: Bool { selectedModelID == AISettingsStore.localOpenAIModelID }

    /// Ollama has no endpoint to configure — only a model name.
    var showsEndpointField: Bool { isCustom || isLocalOpenAI }
    var showsModelNameField: Bool { isCustom || isOllama || isLocalOpenAI }

    /// Ollama takes no key at all; the field is disabled rather than hidden so
    /// the page does not reflow when the picker changes.
    var acceptsAPIKey: Bool { selectedModel?.acceptsAPIKey ?? true }

    var endpointLabel: String {
        isLocalOpenAI
            ? AppText.localized("本地 URL", "Local URL")
            : AppText.localized("自定义 / Azure URL", "Custom / Azure URL")
    }

    var modelNameLabel: String {
        (isOllama || isLocalOpenAI)
            ? AppText.localized("模型 ID", "Model ID")
            : AppText.localized("模型 ID / Azure 部署名", "Model ID / Azure Deployment")
    }

    var endpointPlaceholder: String {
        isLocalOpenAI
            ? "http://127.0.0.1:8000/v1"
            : "https://resource.openai.azure.com/openai/deployments/deployment/chat/completions?api-version=2024-10-21"
    }

    var modelNamePlaceholder: String {
        if isOllama { return "llama3.1" }
        return isLocalOpenAI ? "gemma-4-e4b-it-4bit" : "gpt-4o-mini"
    }

    // MARK: - Saving

    /// The reason this page cannot be saved yet, or nil when it is valid.
    func validationError() -> String? {
        if isCustom {
            return AISettingsStore.customValidationError(endpoint: endpoint, modelName: modelName)
        }
        if isOllama {
            return AISettingsStore.ollamaValidationError(modelName: modelName)
        }
        if isLocalOpenAI {
            return AISettingsStore.localOpenAIValidationError(endpoint: endpoint, modelName: modelName)
        }
        return nil
    }

    /// Persists the page. Call `validationError()` first — the store writes
    /// whichever endpoint/name keys the selected model uses and ignores the
    /// rest, so an invalid value would be saved just as happily.
    func commit() {
        AISettingsStore.save(
            modelID: selectedModelID,
            apiKey: apiKey,
            customEndpoint: endpoint,
            customModelName: modelName
        )
    }

    // MARK: - Per-model field contents

    /// Reloads the key and the two text fields for a newly picked model, so the
    /// page always shows that model's own stored values rather than the previous
    /// model's.
    private func loadFields(for modelID: String) {
        if let model = models.first(where: { $0.id == modelID }) {
            apiKey = AISettingsStore.apiKey(for: model)
        }
        endpoint = Self.storedEndpoint(for: modelID)
        modelName = Self.storedModelName(for: modelID)
    }

    private static func storedEndpoint(for modelID: String) -> String {
        modelID == AISettingsStore.localOpenAIModelID
            ? AISettingsStore.localOpenAIEndpointString
            : AISettingsStore.customEndpointString
    }

    private static func storedModelName(for modelID: String) -> String {
        switch modelID {
        case AISettingsStore.ollamaModelID: return AISettingsStore.ollamaModelName
        case AISettingsStore.localOpenAIModelID: return AISettingsStore.localOpenAIModelName
        default: return AISettingsStore.customModelName
        }
    }
}
