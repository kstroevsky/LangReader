import SwiftUI

/// The contract every settings page's model satisfies, so the panel's Save can
/// iterate its pages instead of naming each one — adding a page should not mean
/// editing `saveCurrentSettings`.
protocol SettingsPage: AnyObject {
    /// Why this page cannot be saved yet, or nil when it is valid.
    func validationError() -> String?
    /// Persists the page. Only called once every page validates.
    func commit()
}

extension SettingsPage {
    func validationError() -> String? { nil }
}

// MARK: - Form chrome

extension View {
    /// The look every settings page shares. One place to change it, rather than
    /// three modifiers repeated per page.
    func settingsFormStyle() -> some View {
        formStyle(.grouped).scrollContentBackground(.hidden)
    }
}

/// A labelled text field, the settings pages' most common row.
struct SettingsTextRow: View {
    let label: String
    let placeholder: String
    let identifier: String
    @Binding var text: String
    var isSecure = false
    var isEnabled = true

    var body: some View {
        LabeledContent(label) {
            Group {
                if isSecure {
                    SecureField("", text: $text, prompt: Text(placeholder))
                } else {
                    TextField("", text: $text, prompt: Text(placeholder))
                }
            }
            .labelsHidden()
            .disabled(!isEnabled)
            .accessibilityIdentifier(identifier)
        }
    }
}

// MARK: - The AI service section

/// One selectable AI service: a chat model, or an embedding endpoint.
struct AIServiceOption: Identifiable, Hashable {
    let id: String
    let title: String
}

/// Accessibility identifiers for one instance of `AIServiceSection`. They differ
/// per page, so the smoke test can tell the chat model's key field from the
/// embedding one.
struct AIServiceSectionIdentifiers {
    let picker: String
    let endpoint: String
    let modelName: String
    let apiKey: String
    let test: String
}

/// The shape the **Model** and **AI Analysis** pages share: pick a service,
/// then — for the services that need it — an endpoint and a model name, then a
/// key, then test the connection.
///
/// Both pages were built separately in AppKit, each with its own popup,
/// show/hide logic and constraint swapping (`updateCustomModelFields` and
/// `updateEmbeddingEndpointFields` are the same function twice). Here the shape
/// is written once and each page supplies only what differs.
protocol AIServiceSettings: AnyObject, Observable {
    var options: [AIServiceOption] { get }
    var selectedOptionID: String { get set }
    var serviceLabel: String { get }

    /// Endpoint and model name are hidden for the services that have neither
    /// (a hosted model), and the two are independent — Ollama has a model name
    /// but no endpoint.
    var showsEndpointField: Bool { get }
    var endpointLabel: String { get }
    var endpointPlaceholder: String { get }
    var endpoint: String { get set }
    /// Some endpoints are fixed by the provider and shown read-only.
    var isEndpointEditable: Bool { get }

    var showsModelNameField: Bool { get }
    var modelNameLabel: String { get }
    var modelNamePlaceholder: String { get }
    var modelName: String { get set }

    var apiKeyLabel: String { get }
    var apiKey: String { get set }
    /// False for services that run locally; the field is disabled rather than
    /// hidden so the page does not reflow when the picker changes.
    var acceptsAPIKey: Bool { get }
    /// Shown under a disabled key field to say why it is disabled.
    var apiKeyNote: String? { get }

    var testButtonTitle: String { get }
    var isTestingConnection: Bool { get }
    func testConnection()

    var sectionIdentifiers: AIServiceSectionIdentifiers { get }
}

extension AIServiceSettings {
    var isEndpointEditable: Bool { true }
    var apiKeyNote: String? { nil }
}

struct AIServiceSection<Model: AIServiceSettings>: View {
    @Bindable var model: Model

    var body: some View {
        let ids = model.sectionIdentifiers
        Section {
            Picker(model.serviceLabel, selection: $model.selectedOptionID) {
                ForEach(model.options) { option in
                    Text(option.title).tag(option.id)
                }
            }
            .accessibilityIdentifier(ids.picker)

            if model.showsEndpointField {
                SettingsTextRow(
                    label: model.endpointLabel,
                    placeholder: model.endpointPlaceholder,
                    identifier: ids.endpoint,
                    text: $model.endpoint,
                    isEnabled: model.isEndpointEditable
                )
            }

            if model.showsModelNameField {
                SettingsTextRow(
                    label: model.modelNameLabel,
                    placeholder: model.modelNamePlaceholder,
                    identifier: ids.modelName,
                    text: $model.modelName
                )
            }
        }

        Section {
            SettingsTextRow(
                label: model.apiKeyLabel,
                placeholder: AppText.apiKeyPlaceholder,
                identifier: ids.apiKey,
                text: $model.apiKey,
                isSecure: true,
                isEnabled: model.acceptsAPIKey
            )
            if let note = model.apiKeyNote, !model.acceptsAPIKey {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button(model.testButtonTitle) {
                model.testConnection()
            }
            .disabled(model.isTestingConnection)
            .accessibilityIdentifier(ids.test)
        }
    }
}
