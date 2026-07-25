import Cocoa

final class AISettingsPanelController {
    enum SettingsTab: Int {
        case general = 0
        case model = 1
        case vector = 2
        case speech = 3
        case cache = 4
    }

    enum Identifiers {
        static let saveButton = NSUserInterfaceItemIdentifier("saveAISettings")
        static let settingsTitleIcon = NSUserInterfaceItemIdentifier("settingsTitleIcon")
        static let settingsFormSurface = NSUserInterfaceItemIdentifier("settingsFormSurface")
        static let settingsCard = NSUserInterfaceItemIdentifier("settingsCard")
        static let settingsSpeechRowCard = NSUserInterfaceItemIdentifier("settingsSpeechRowCard")
    }

    /// State behind the SwiftUI General page, and the source of truth for
    /// saving it. Created when the panel is built.
    var generalSettings: GeneralSettingsModel?
    /// Same, for the SwiftUI Model page.
    var modelSettings: ModelSettingsModel?
    /// Same, for the SwiftUI AI Analysis page.
    var embeddingSettings: EmbeddingSettingsModel?
    /// State behind the SwiftUI Read Aloud page.
    var speechSettings: SpeechSettingsModel?
    /// The Cache page's live state. Not a `SettingsPage`: its actions apply
    /// immediately, so there is nothing for Save to commit.
    var cacheSettings: CacheSettingsModel?
    var onSaved: (() -> Void)?
    var onAppearanceChanged: (() -> Void)?
    var currentVectorIndexStatus: (() -> String)?
    var onStartVectorIndex: (() -> Void)?
    var onToggleVectorIndexPaused: (() -> Void)?
    var onCancelVectorIndex: (() -> Void)?
    var onClearCurrentVectorIndex: (() -> Void)?
    var onClearCurrentWordRecords: (() -> Void)?
    var currentSpeechLanguageHint: (() -> AISettingsStore.SpeechLanguageHint?)?

    let vectorCacheQueue = DispatchQueue(label: "com.linlu.leafreader.settings-vector-cache", qos: .utility)
    weak var parentWindow: NSWindow?
    var panel: SettingsPanel?
    weak var settingsTabControl: NSView?
    weak var settingsSidebarControl: NSView?
    weak var settingsScrollView: NSScrollView?
    weak var basicPage: NSView?
    weak var modelPage: NSView?
    weak var embeddingPage: NSView?
    weak var speechPage: NSView?
    weak var cachePage: NSView?
    var cacheRefreshTimer: Timer?
    var speechDownloadRefreshTimer: Timer?
    var speechVoicePreviewWorkItem: DispatchWorkItem?
    var isClosing = false
    var shouldNotifySavedAfterClose = false
    var appActivationObserver: NSObjectProtocol?

    deinit {
        cacheRefreshTimer?.invalidate()
        speechDownloadRefreshTimer?.invalidate()
        speechVoicePreviewWorkItem?.cancel()
        removeAppActivationObserver()
    }

}
