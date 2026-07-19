import Foundation
import NaturalLanguage

extension SpeechTextPolicy {
    static func isEnglishCandidate(_ text: String) -> Bool {
        guard !text.isEmpty,
              text.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil else {
            return false
        }
        return !text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2A6DF:
                return true
            default:
                return false
            }
        }
    }

    static func isChineseCandidate(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: Self.isCJK)
    }

    static func prefersChineseTTS(_ text: String) -> Bool {
        let counts = languageSignalCounts(in: text)
        guard counts.cjk > 0 else { return false }
        guard counts.latin > 0 else { return true }
        if counts.cjk >= counts.latin {
            return true
        }
        return counts.cjk >= 8 && counts.cjk * 4 >= counts.latin
    }

    static func prefersChineseReadAloudDocumentTTS(_ text: String) -> Bool {
        let counts = languageSignalCounts(in: text)
        guard counts.cjk >= 40 else { return false }
        guard counts.latin > 0 else { return true }
        return counts.cjk * 2 >= counts.latin
    }

    /// Returns the language used by macOS's built-in voice for short vocabulary
    /// playback. Local runtimes currently cover English and Chinese; German is
    /// deliberately routed to the system voice, which has native German voices.
    static func systemSpeechLanguageCode(for text: String) -> String {
        if prefersChineseTTS(text) {
            return "zh-CN"
        }
        if prefersGermanTTS(text) {
            return "de-DE"
        }
        return "en-US"
    }

    static func prefersGermanTTS(_ text: String) -> Bool {
        let value = normalizedCommonInput(text)
        guard !value.isEmpty,
              !prefersChineseTTS(value),
              value.range(of: #"\p{L}"#, options: .regularExpression) != nil else {
            return false
        }

        // These are unambiguous German orthographic signals, including the
        // common vocabulary forms the reader was previously pronouncing in English.
        if value.range(of: #"[äöüÄÖÜßẞ]"#, options: .regularExpression) != nil {
            return true
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(value)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        let germanConfidence = hypotheses[.german] ?? 0
        let englishConfidence = hypotheses[.english] ?? 0
        return germanConfidence >= 0.5 && germanConfidence > englishConfidence
    }

    static func isLocalTTSCandidate(_ text: String) -> Bool {
        isEnglishCandidate(text) || isChineseCandidate(text)
    }

    static func normalizedReadAloudInput(_ text: String) -> String {
        if prefersChineseTTS(text) {
            return normalizedCommonInput(text)
        }
        return normalizedEnglishInput(text)
    }

    static func normalizedEnglishInput(_ text: String) -> String {
        var value = normalizedPunctuationInput(text)
        value = value.replacingOccurrences(
            of: #"(?i)([A-Za-z])-\s*[\r\n]+\s*([A-Za-z])"#,
            with: "$1$2",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"([A-Za-z])\s*'\s*([A-Za-z])"#,
            with: "$1'$2",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(^|[\r\n]+|[.!?]\s+|"\s*)([B-HJ-Zb-hj-z])\s+([a-z]{2,})"#,
            with: "$1$2$3",
            options: .regularExpression
        )
        value = collapseWhitespace(in: value)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedCommonInput(_ text: String) -> String {
        collapseWhitespace(in: normalizedPunctuationInput(text))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedPunctuationInput(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00AD}", with: "")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .replacingOccurrences(of: "\u{2026}", with: "...")
    }

    static func collapseWhitespace(in text: String) -> String {
        text
            .replacingOccurrences(
                of: #"[\r\n\t]+"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s{2,}"#,
                with: " ",
                options: .regularExpression
            )
    }

    static func languageSignalCounts(in text: String) -> (cjk: Int, latin: Int) {
        var cjk = 0
        var latin = 0
        for scalar in text.unicodeScalars {
            if isCJK(scalar) {
                cjk += 1
            } else if isLatinLetter(scalar) {
                latin += 1
            }
        }
        return (cjk, latin)
    }

    static func isLatinLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x41...0x5A, 0x61...0x7A:
            return true
        default:
            return false
        }
    }

    static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x2A6DF:
            return true
        default:
            return false
        }
    }
}
