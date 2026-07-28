import AVFoundation
import Foundation

enum SpeechUtteranceFactory {
    static func utterance(for text: String, languageCode: String? = nil) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice(for: text, languageCode: languageCode)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        return utterance
    }

    private static func voice(for text: String, languageCode: String?) -> AVSpeechSynthesisVoice? {
        for language in preferredLanguages(for: text, languageCode: languageCode) {
            if let voice = AVSpeechSynthesisVoice(language: language) {
                return voice
            }
            if let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix(language) }) {
                return voice
            }
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    private static func preferredLanguages(for text: String, languageCode: String?) -> [String] {
        let resolvedLanguage = languageCode ?? SpeechTextPolicy.systemSpeechLanguageCode(for: text)
        if resolvedLanguage.hasPrefix("zh") {
            return ["zh-CN", "zh-Hans", "zh-TW", "zh-Hant", "zh-HK"]
        }
        if resolvedLanguage.hasPrefix("de") {
            return ["de-DE", "de-AT", "de-CH", "de"]
        }
        return ["en-US"]
    }
}
