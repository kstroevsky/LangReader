import SwiftUI
import LeafReaderCore

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

/// The explanatory line under a control. Every settings page has these and they
/// should not drift apart in size or colour.
struct SettingsFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
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

/// One button in a `SettingsStatusRow`.
struct SettingsAction: Identifiable {
    enum Role {
        case normal
        /// Deletes something. Rendered in red, and expected to confirm first.
        case destructive
    }

    /// Doubles as the accessibility identifier.
    let id: String
    let title: String
    let symbol: String?
    var role: Role = .normal
    /// The AppKit rows gave each action its own colour; keeping it means the
    /// page still reads at a glance rather than as a wall of identical buttons.
    var tint: Color?
    var isEnabled = true
    let perform: () -> Void
}

/// A titled item with a status line, optional progress, and a row of actions.
///
/// The Cache and Read Aloud pages are both made of these — a cache with its size
/// and a Clear button, a book's index with its progress and Build / Pause /
/// Cancel, a speech runtime with its download state and Download / Delete. In
/// AppKit each was hand-built with its own card, labels, buttons and
/// constraints; they are the same row.
struct SettingsStatusRow: View {
    let title: String
    let status: String
    /// 0...1 while something is running, nil otherwise.
    var progress: Double?
    var actions: [SettingsAction] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            SettingsFootnote(status)
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }
            if !actions.isEmpty {
                // Wraps rather than overflowing: the cache row has five.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { buttons }
                    VStack(alignment: .leading, spacing: 8) { buttons }
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var buttons: some View {
        ForEach(actions) { action in
            Button(role: action.role == .destructive ? .destructive : nil) {
                action.perform()
            } label: {
                // The glyph carries the colour and the title stays in the
                // primary text colour, which is what the AppKit buttons did.
                // `.tint()` alone does not colour a bordered button on macOS.
                HStack(spacing: 5) {
                    if let symbol = action.symbol {
                        Image(systemName: symbol)
                            .foregroundStyle(action.tint ?? .accentColor)
                    }
                    Text(action.title)
                }
            }
            .disabled(!action.isEnabled)
            .accessibilityIdentifier(action.id)
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
                SettingsFootnote(note)
            }

            Button(model.testButtonTitle) {
                model.testConnection()
            }
            .disabled(model.isTestingConnection)
            .accessibilityIdentifier(ids.test)
        }
    }
}
