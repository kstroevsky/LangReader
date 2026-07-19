import Foundation

enum SpeechSynthesisRuntimeTests {
    static func testRuntimeMapping() throws {
        try expectEqual(SpeechSynthesisRuntime(runtime: .kokoro), .kokoroCoreML, "Kokoro should map to its CoreML synthesis runtime")
        try expectEqual(SpeechSynthesisRuntime(runtime: .piper), .piper, "Piper should map to its synthesis runtime")
        try expectEqual(SpeechSynthesisRuntime(runtime: .supertonic), .supertonic, "Supertonic should map to its synthesis runtime")
        try expectEqual(SpeechSynthesisRuntime.kokoroCoreML.runtime, .kokoro, "Kokoro synthesis runtime should preserve its install runtime")
        try expect(SpeechSynthesisRuntime.unavailable.runtime == nil, "an unavailable synthesis runtime should not report an install runtime")
    }

    static func testSelectionPolicy() throws {
        try expectEqual(
            SpeechSynthesisRuntime.selected(
                wantsChinese: true,
                hasRunnableKokoro: true,
                overrideBackendID: "piper",
                configuredRuntime: .piper
            ),
            .kokoroCoreML,
            "Chinese text should use Kokoro when it is runnable"
        )
        try expectEqual(
            SpeechSynthesisRuntime.selected(
                wantsChinese: true,
                hasRunnableKokoro: false,
                overrideBackendID: "kokoro",
                configuredRuntime: .kokoro
            ),
            .unavailable,
            "Chinese text should fail clearly when Kokoro is unavailable"
        )
        try expectEqual(
            SpeechSynthesisRuntime.selected(
                wantsChinese: false,
                hasRunnableKokoro: false,
                overrideBackendID: "supertonic-coreml",
                configuredRuntime: .piper
            ),
            .supertonic,
            "an explicit runtime override should win for non-Chinese text"
        )
        try expectEqual(
            SpeechSynthesisRuntime.selected(
                wantsChinese: false,
                hasRunnableKokoro: false,
                overrideBackendID: nil,
                configuredRuntime: .piper
            ),
            .piper,
            "configured runtime should be selected without an override"
        )
    }
}
