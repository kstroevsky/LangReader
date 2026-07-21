import Foundation
import Observation

/// State behind the General settings page.
///
/// The page has two kinds of setting and the distinction is deliberate:
///
///   * **Live** — theme and reading-area brightness apply the moment they
///     change, because the point of those controls is to see the result.
///   * **Pending** — language and the two switches are held until Save, so a
///     cancelled panel leaves them untouched.
///
/// Holding this in a model rather than reading it back off the controls also
/// removes a real hazard: the old save path asked the checkboxes directly
/// (`checkbox?.state == .on`), so if the controls were ever absent it would read
/// `nil == .on` — `false` — and silently switch both settings off.
@Observable
final class GeneralSettingsModel {
    /// Applies a theme or brightness change to the rest of the app.
    private let onAppearanceChanged: () -> Void

    // MARK: Live settings

    var theme: ReaderTheme {
        didSet {
            guard theme != oldValue else { return }
            ReaderTheme.selected = theme
            onAppearanceChanged()
        }
    }

    /// The brightness slider's position, in the policy's own units.
    var brightness: Double {
        didSet {
            guard brightness != oldValue else { return }
            ReaderTheme.pdfDimmingStrength = PDFBrightnessPolicy.dimmingStrength(forSliderValue: brightness)
            onAppearanceChanged()
        }
    }

    /// Brightness only applies to the tinted themes; the untinted theme draws
    /// the document as authored, so the control is hidden rather than inert.
    var showsBrightness: Bool { theme != .original }

    // MARK: Pending settings

    var language: AppText.Language
    var speaksSelectedWord: Bool
    var savesAIConversation: Bool

    let brightnessRange: ClosedRange<Double> = 0...PDFBrightnessPolicy.sliderMaximum

    init(onAppearanceChanged: @escaping () -> Void = {}) {
        self.onAppearanceChanged = onAppearanceChanged
        theme = ReaderTheme.selected
        brightness = PDFBrightnessPolicy.sliderValue(forDimmingStrength: ReaderTheme.pdfDimmingStrength)
        language = AppText.selectedLanguage
        speaksSelectedWord = AISettingsStore.speakSelectedWordEnabled
        savesAIConversation = AISettingsStore.saveAIConversationEnabled
    }

    /// Persists the pending settings. Called from the panel's Save.
    ///
    /// - Returns: whether the display language changed, since that requires the
    ///   whole interface to be relabelled.
    @discardableResult
    func commit() -> Bool {
        let languageChanged = language != AppText.selectedLanguage
        AppText.selectedLanguage = language
        AISettingsStore.saveSpeakSelectedWordEnabled(speaksSelectedWord)
        AISettingsStore.saveAIConversationEnabled(savesAIConversation)
        // Theme and brightness already applied live; writing them again here
        // keeps Save meaning "everything on this page is now persisted".
        ReaderTheme.selected = theme
        ReaderTheme.pdfDimmingStrength = PDFBrightnessPolicy.dimmingStrength(forSliderValue: brightness)
        return languageChanged
    }

}
