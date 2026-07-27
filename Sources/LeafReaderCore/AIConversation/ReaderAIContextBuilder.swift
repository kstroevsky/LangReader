import Foundation

package struct ReaderAIContextBuilder {
    package static func selectedTextContext(selectedText: String, sourceText: String, radius: Int) -> String? {
        sentenceContext(containing: selectedText, in: sourceText)
            ?? characterWindowContext(containing: selectedText, in: sourceText, radius: radius)
    }

    package static func selectedTextContext(occurrenceRange: NSRange, sourceText: String, radius: Int) -> String? {
        guard occurrenceRange.location != NSNotFound,
              occurrenceRange.length > 0,
              let range = Range(occurrenceRange, in: sourceText) else { return nil }
        return sentenceContext(around: range, in: sourceText)
            ?? characterWindowContext(around: range, in: sourceText, radius: radius)
    }

    package static func visibleWebTextScript(preserveLineBreaks: Bool) -> String {
        let selector = preserveLineBreaks
            ? "h1,h2,h3,h4,h5,h6,p,li,blockquote,pre,td,th"
            : "h1,h2,h3,h4,h5,h6,p,li,blockquote,pre,td,th,div"
        let surroundingBlockCount = preserveLineBreaks ? 0 : 1
        return """
        (() => {
          const blocks = Array.from(document.body.querySelectorAll('\(selector)'));
          const seen = new Set();
          const parts = [];
          const visibleIndexes = [];
          for (let index = 0; index < blocks.length; index++) {
            const el = blocks[index];
            const rect = el.getBoundingClientRect();
            if (rect.bottom < 0 || rect.top > window.innerHeight || rect.width <= 0 || rect.height <= 0) continue;
            visibleIndexes.push(index);
          }
          if (!visibleIndexes.length) return '';
          const startIndex = Math.max(0, visibleIndexes[0] - \(surroundingBlockCount));
          const endIndex = Math.min(blocks.length - 1, visibleIndexes[visibleIndexes.length - 1] + \(surroundingBlockCount));
          for (let index = startIndex; index <= endIndex; index++) {
            const el = blocks[index];
            const text = (el.innerText || el.textContent || '').replace(/\\s+/g, ' ').trim();
            if (!text || seen.has(text)) continue;
            seen.add(text);
            parts.push(text);
          }
          return parts.join('\\n\\n').slice(0, 8000);
        })();
        """
    }

    package static func normalizeVisibleWebText(_ text: String, preserveLineBreaks: Bool) -> String {
        preserveLineBreaks ? normalizeReaderTextPreservingParagraphs(text) : normalizeWhitespace(text)
    }

    package static func webProgressTextWindow(plainText: String, progress: Double) -> String {
        let text = normalizeWhitespace(plainText)
        guard !text.isEmpty else { return "" }
        let center = Int(Double(text.count) * progress)
        let lower = max(0, center - 2200)
        let upper = min(text.count, center + 3800)
        let start = text.index(text.startIndex, offsetBy: lower)
        let end = text.index(text.startIndex, offsetBy: upper)
        return String(text[start..<end])
    }

    package static func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    package static func normalizeReaderTextPreservingParagraphs(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"[ \t]+\n"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n[ \t]+"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    package static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    package static func hasTrimmedText(_ text: String) -> Bool {
        !trimmed(text).isEmpty
    }

    package static func nonEmptyTrimmedLines(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .map(trimmed)
            .filter { !$0.isEmpty }
    }

    package static func joinedNonEmptyParagraphs(_ parts: [String]) -> String {
        parts
            .filter(hasTrimmedText)
            .joined(separator: "\n\n")
    }

    private static func sentenceContext(containing selectedText: String, in text: String) -> String? {
        let normalizedText = normalizeWhitespace(text)
        let normalizedSelection = normalizeWhitespace(selectedText)
        guard !normalizedText.isEmpty, !normalizedSelection.isEmpty else { return nil }
        guard let range = normalizedText.range(of: normalizedSelection, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }

        let sentenceStart = normalizedText[..<range.lowerBound].lastIndex { char in
            ".!?。！？\n".contains(char)
        }.map { normalizedText.index(after: $0) } ?? normalizedText.startIndex
        let sentenceEnd = normalizedText[range.upperBound...].firstIndex { char in
            ".!?。！？\n".contains(char)
        }.map { normalizedText.index(after: $0) } ?? normalizedText.endIndex
        let sentence = normalizeWhitespace(trimLeadingContextQuotes(String(normalizedText[sentenceStart..<sentenceEnd])))
        guard sentence.count > normalizedSelection.count else { return nil }
        return sentence
    }

    private static func sentenceContext(around range: Range<String.Index>, in text: String) -> String? {
        let sentenceStart = text[..<range.lowerBound].lastIndex { char in
            ".!?。！？".contains(char)
        }.map { text.index(after: $0) } ?? text.startIndex
        let sentenceEnd = text[range.upperBound...].firstIndex { char in
            ".!?。！？".contains(char)
        }.map { text.index(after: $0) } ?? text.endIndex
        let rawSentence = String(text[sentenceStart..<sentenceEnd])
        let sentence = normalizeWhitespace(
            trimLeadingContextQuotes(trimLeadingPDFContextHeadingLines(rawSentence))
        )
        let selectedText = normalizeWhitespace(String(text[range]))
        guard sentence.count > selectedText.count else { return nil }
        return sentence
    }

    private static func trimLeadingPDFContextHeadingLines(_ text: String) -> String {
        var lines = text.components(separatedBy: .newlines)
        while lines.first.map({ trimmed($0).isEmpty }) == true {
            lines.removeFirst()
        }
        while lines.count > 1 {
            let first = trimmed(lines[0])
            let next = trimmed(lines[1])
            guard looksLikePDFContextHeading(first, followedBy: next) else { break }
            lines.removeFirst()
            while lines.first.map({ trimmed($0).isEmpty }) == true {
                lines.removeFirst()
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func looksLikePDFContextHeading(_ line: String, followedBy nextLine: String) -> Bool {
        guard !line.isEmpty,
              line.count <= 100,
              line.range(of: #"[.!?。！？]$"#, options: .regularExpression) == nil,
              let nextFirst = nextLine.first,
              nextFirst.isUppercase || nextFirst.isNumber else {
            return false
        }
        if line.contains("/") {
            return true
        }
        if let first = line.first,
           !first.isLetter,
           !first.isNumber,
           !#""“”‘’'`„«"#.contains(first) {
            return true
        }
        let letters = line.filter(\.isLetter)
        return letters.count >= 2 && line == line.uppercased()
    }

    private static func characterWindowContext(
        around range: Range<String.Index>,
        in text: String,
        radius: Int
    ) -> String? {
        let prefixStart = text.index(
            range.lowerBound,
            offsetBy: -radius,
            limitedBy: text.startIndex
        ) ?? text.startIndex
        let suffixEnd = text.index(
            range.upperBound,
            offsetBy: radius,
            limitedBy: text.endIndex
        ) ?? text.endIndex
        return normalizeWhitespace(trimLeadingContextQuotes(String(text[prefixStart..<suffixEnd])))
    }

    private static func characterWindowContext(containing selectedText: String, in text: String, radius: Int) -> String? {
        let normalizedText = normalizeWhitespace(text)
        let normalizedSelection = normalizeWhitespace(selectedText)
        guard !normalizedText.isEmpty, !normalizedSelection.isEmpty else { return nil }
        guard let range = normalizedText.range(of: normalizedSelection, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return nil
        }

        let prefixStart = normalizedText.index(range.lowerBound, offsetBy: -radius, limitedBy: normalizedText.startIndex) ?? normalizedText.startIndex
        let suffixEnd = normalizedText.index(range.upperBound, offsetBy: radius, limitedBy: normalizedText.endIndex) ?? normalizedText.endIndex
        return normalizeWhitespace(trimLeadingContextQuotes(String(normalizedText[prefixStart..<suffixEnd])))
    }

    package static func trimLeadingContextQuotes(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = result.first, #""“”‘’'`"#.contains(first) {
            result.removeFirst()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}
