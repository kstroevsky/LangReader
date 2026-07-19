import Foundation

/// The complete, engine-neutral input needed to synthesize one audio file.
struct SpeechSynthesisRequest {
    let text: String
    let outputURL: URL
    let voiceID: String?
    let languageHint: AISettingsStore.SpeechLanguageHint?
    let speedMultiplier: Double?
    let piperLengthScale: Double?
}

/// The concrete engine adapters retained by the playback coordinator for its lifetime.
struct SpeechRuntimeAdapters {
    let kokoro = KokoroTTSBackend()
    let piper = PiperTTSBackend()
    let supertonic = SupertonicCoreMLTTSBackend()

    func stopAll() {
        kokoro.stop()
        piper.stop()
        supertonic.stop()
    }
}

/// Selects and drives exactly one local Speech Runtime for a synthesis request.
enum SpeechSynthesisRuntime: Equatable {
    case kokoroCoreML
    case piper
    case supertonic
    case unavailable

    static let backendEnvironmentKey = "LEAFREADER_TTS_BACKEND"

    init(runtime: SpeechRuntimeResourceManager.Runtime) {
        switch runtime {
        case .kokoro:
            self = .kokoroCoreML
        case .piper:
            self = .piper
        case .supertonic:
            self = .supertonic
        }
    }

    var runtime: SpeechRuntimeResourceManager.Runtime? {
        switch self {
        case .kokoroCoreML:
            return .kokoro
        case .piper:
            return .piper
        case .supertonic:
            return .supertonic
        case .unavailable:
            return nil
        }
    }

    static func selected(
        for text: String,
        languageHint: AISettingsStore.SpeechLanguageHint? = nil
    ) -> SpeechSynthesisRuntime {
        let wantsChinese = languageHint == .chinese
            || (languageHint != .english && SpeechTextPolicy.prefersChineseTTS(text))
        let configuredRuntime = SpeechRuntimeResourceManager.runnableRuntime(
            preferredID: AISettingsStore.selectedSpeechRuntimeID
        )
        let overrideBackendID = ProcessInfo.processInfo.environment[backendEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return selected(
            wantsChinese: wantsChinese,
            hasRunnableKokoro: SpeechRuntimeResourceManager.isRunnable(.kokoro),
            overrideBackendID: overrideBackendID,
            configuredRuntime: configuredRuntime
        )
    }

    static func selected(
        wantsChinese: Bool,
        hasRunnableKokoro: Bool,
        overrideBackendID: String?,
        configuredRuntime: SpeechRuntimeResourceManager.Runtime?
    ) -> SpeechSynthesisRuntime {
        if wantsChinese {
            return hasRunnableKokoro ? .kokoroCoreML : .unavailable
        }
        switch overrideBackendID {
        case "piper", "piper-tts":
            return .piper
        case "supertonic", "supertonic-coreml", "supertonic-mlx":
            return .supertonic
        case "kokoro", "kokoro-coreml", "coreml":
            return .kokoroCoreML
        default:
            return configuredRuntime.map(Self.init(runtime:)) ?? .unavailable
        }
    }

    func synthesize(
        _ request: SpeechSynthesisRequest,
        using adapters: SpeechRuntimeAdapters
    ) -> Result<Void, SpeechSynthesisError> {
        switch self {
        case .kokoroCoreML:
            return adapters.kokoro.synthesizeResult(
                text: request.text,
                outputURL: request.outputURL,
                voiceID: request.voiceID,
                languageHint: request.languageHint,
                speed: request.speedMultiplier
            )
        case .piper:
            return adapters.piper.synthesizeResult(
                text: request.text,
                outputURL: request.outputURL,
                voiceID: request.voiceID,
                lengthScale: request.piperLengthScale
            )
        case .supertonic:
            return adapters.supertonic.synthesizeResult(
                text: request.text,
                outputURL: request.outputURL,
                voiceID: request.voiceID,
                languageHint: request.languageHint,
                speed: request.speedMultiplier
            )
        case .unavailable:
            return .failure(.unsupportedLanguage(AppText.localized("当前朗读引擎", "Selected speech runtime")))
        }
    }

    func stop(using adapters: SpeechRuntimeAdapters) {
        switch self {
        case .kokoroCoreML:
            adapters.kokoro.stop()
        case .piper:
            adapters.piper.stop()
        case .supertonic:
            adapters.supertonic.stop()
        case .unavailable:
            break
        }
    }

    func stopOtherRuntimes(using adapters: SpeechRuntimeAdapters) {
        switch self {
        case .kokoroCoreML:
            adapters.piper.stop()
            adapters.supertonic.stop()
        case .piper:
            adapters.kokoro.stop()
            adapters.supertonic.stop()
        case .supertonic:
            adapters.kokoro.stop()
            adapters.piper.stop()
        case .unavailable:
            adapters.stopAll()
        }
    }
}
