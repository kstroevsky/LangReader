import Foundation

package struct GermanDictionaryEntry: Equatable {
    package let requestedWord: String
    package let lemma: String
    package let partOfSpeech: String?
    package let meanings: [String]
    /// Parsed flexion table, when the page had one. Carried as plain data so
    /// this type stays free of any storage dependency; persisting it is the
    /// caller's job.
    package var flexion: GermanWiktionaryParser.FlexionTable?

    package init(
        requestedWord: String,
        lemma: String,
        partOfSpeech: String?,
        meanings: [String],
        flexion: GermanWiktionaryParser.FlexionTable? = nil
    ) {
        self.requestedWord = requestedWord
        self.lemma = lemma
        self.partOfSpeech = partOfSpeech
        self.meanings = meanings
        self.flexion = flexion
    }

    package var metadata: VocabularyDictionaryMetadata {
        VocabularyDictionaryMetadata(tags: partOfSpeech, frequency: nil)
    }

    package var sourceURL: URL? {
        var components = URLComponents(string: "https://de.wiktionary.org/wiki/")
        components?.path = "/wiki/" + lemma.replacingOccurrences(of: " ", with: "_")
        return components?.url
    }

    package var markdown: String {
        var lines = ["**\(lemma)**"]
        if let partOfSpeech, !partOfSpeech.isEmpty {
            lines[0] += " *(\(partOfSpeech))*"
        }
        if requestedWord.caseInsensitiveCompare(lemma) != .orderedSame {
            lines.append("\nGrundform von **\(requestedWord)**: **\(lemma)**")
        }
        lines.append("")
        lines.append(contentsOf: meanings.enumerated().map { "\($0.offset + 1). \($0.element)" })
        if let sourceURL {
            lines.append("\nQuelle: [Deutsch Wiktionary](\(sourceURL.absoluteString)) · CC BY-SA")
        }
        return lines.joined(separator: "\n")
    }
}

package enum GermanWiktionaryParser {
    package struct ParsedPage: Equatable {
        package let lemma: String?
        package let partOfSpeech: String?
        package let meanings: [String]
        package var flexion: FlexionTable?
    }

    package static func parse(wikitext: String) -> ParsedPage? {
        guard let german = germanSection(in: wikitext) else { return nil }
        let partOfSpeech = firstCapture(
            pattern: #"\{\{Wortart\|([^|}]+)\|Deutsch"#,
            in: german
        )
        let lemma = firstCapture(
            pattern: #"des\s+(?:Substantivs|Verbs|Adjektivs)\s+'''\[\[([^\]|]+)"#,
            in: german
        ) ?? firstCapture(
            pattern: #"\{\{Grundformverweis[^|}]*\|([^|}]+)"#,
            in: german
        )
        let meanings = meaningLines(in: german)
        return ParsedPage(
            lemma: lemma,
            partOfSpeech: partOfSpeech,
            meanings: meanings,
            flexion: parseFlexion(wikitext: wikitext)
        )
    }

    // MARK: - Flexion tables

    package struct FlexionForm: Equatable {
        /// The Wiktionary parameter name, e.g. `Nominativ Plural`, `Partizip II`.
        package let label: String
        package let surface: String
        /// Wiktionary marks alternative forms with a trailing `*`
        /// (`Dativ Singular*=Hause`).
        package let isVariant: Bool
    }

    package struct FlexionTable: Equatable {
        /// `m`, `f` or `n`. More discriminating than a part-of-speech tag for
        /// the noun/noun homographs German is full of — `die Steuer` (tax)
        /// versus `das Steuer` (helm).
        package let genus: String?
        package let auxiliary: String?
        package let forms: [FlexionForm]

        package func forms(labeled label: String) -> [String] {
            forms.filter { $0.label == label }.map(\.surface)
        }
    }

    /// Parameter names that carry an actual inflected form.
    ///
    /// This is an allowlist rather than a blocklist on purpose: the Übersicht
    /// template interleaves image parameters with grammatical ones
    /// (`|Bild 1=Leamouth riverside building 1.jpg|mini|1|…`), so anything not
    /// named here — including captions and filenames — is discarded.
    private static let flexionFormKeys: Set<String> = [
        "Nominativ Singular", "Nominativ Plural",
        "Genitiv Singular", "Genitiv Plural",
        "Dativ Singular", "Dativ Plural",
        "Akkusativ Singular", "Akkusativ Plural",
        "Partizip II", "Partizip I",
        "Imperativ Singular", "Imperativ Plural"
    ]

    /// Verb parameters are person-suffixed (`Präsens_ich`, `Präteritum_ich`).
    private static let flexionFormKeyPrefixes = [
        "Präsens_", "Präteritum_", "Konjunktiv II_", "Konjunktiv I_"
    ]

    /// Parses the `{{Deutsch … Übersicht}}` table from a lemma page.
    ///
    /// Only this table is parseable. `Flexion:` subpages store principal parts
    /// and generate their paradigms through MediaWiki templates
    /// (`{{Deutsch Verb unregelmäßig|3=ging|5=gegangen}}`), so they yield no
    /// literal forms to read. That makes this table a labeled subset of the
    /// paradigm rather than the whole of it.
    package static func parseFlexion(wikitext: String) -> FlexionTable? {
        let scope = germanSection(in: wikitext) ?? wikitext
        guard let block = uebersichtBlock(in: scope) else { return nil }

        var genus: String?
        var auxiliary: String?
        var forms: [FlexionForm] = []

        // Each parameter occupies its own line. Splitting the block on "|"
        // instead would corrupt image parameters, whose values contain pipes.
        for rawLine in block.split(whereSeparator: { $0.isNewline }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("|"), let separator = line.firstIndex(of: "=") else { continue }

            let rawKey = String(line[line.index(after: line.startIndex)..<separator])
                .trimmingCharacters(in: .whitespaces)
            let value = cleanMarkup(String(line[line.index(after: separator)...]))
            guard !value.isEmpty else { continue }

            let isVariant = rawKey.hasSuffix("*")
            let key = isVariant ? String(rawKey.dropLast()) : rawKey

            switch key {
            case "Genus":
                genus = value
            case "Hilfsverb":
                auxiliary = value
            default:
                guard flexionFormKeys.contains(key)
                    || flexionFormKeyPrefixes.contains(where: { key.hasPrefix($0) }) else {
                    continue
                }
                forms.append(FlexionForm(label: key, surface: value, isVariant: isVariant))
            }
        }

        guard !forms.isEmpty || genus != nil else { return nil }
        return FlexionTable(genus: genus, auxiliary: auxiliary, forms: forms)
    }

    /// Extracts the body of the first `{{Deutsch … Übersicht}}` template,
    /// tracking brace depth so nested templates in values do not end it early.
    private static func uebersichtBlock(in text: String) -> String? {
        guard let header = text.range(
            of: #"\{\{Deutsch [^\n}]*Übersicht"#,
            options: .regularExpression
        ) else {
            return nil
        }
        var depth = 2
        var index = header.upperBound
        var body = ""
        while index < text.endIndex {
            let character = text[index]
            if character == "{", text.index(after: index) < text.endIndex,
               text[text.index(after: index)] == "{" {
                depth += 2
                body.append("{{")
                index = text.index(index, offsetBy: 2)
                continue
            }
            if character == "}", text.index(after: index) < text.endIndex,
               text[text.index(after: index)] == "}" {
                depth -= 2
                if depth <= 0 { return body }
                body.append("}}")
                index = text.index(index, offsetBy: 2)
                continue
            }
            body.append(character)
            index = text.index(after: index)
        }
        return body.isEmpty ? nil : body
    }

    private static func germanSection(in text: String) -> String? {
        guard let header = text.range(
            of: #"(?m)^==[^\n]*\{\{Sprache\|Deutsch\}\}[^\n]*==\s*$"#,
            options: .regularExpression
        ) else {
            return nil
        }
        let remainder = text[header.upperBound...]
        if let next = remainder.range(of: #"(?m)^==[^=].*==\s*$"#, options: .regularExpression) {
            return String(remainder[..<next.lowerBound])
        }
        return String(remainder)
    }

    private static func meaningLines(in section: String) -> [String] {
        guard let heading = section.range(of: "{{Bedeutungen}}") else { return [] }
        let remainder = section[heading.upperBound...]
        let block: Substring
        if let nextHeading = remainder.range(of: #"(?m)^\{\{[^\n]+\}\}\s*$"#, options: .regularExpression) {
            block = remainder[..<nextHeading.lowerBound]
        } else {
            block = remainder[...]
        }
        return block
            .split(whereSeparator: { $0.isNewline })
            .compactMap { line -> String? in
                let value = String(line).trimmingCharacters(in: .whitespaces)
                guard value.range(of: #"^:\[[^]]+\]\s*"#, options: .regularExpression) != nil else {
                    return nil
                }
                let withoutIndex = value.replacingOccurrences(
                    of: #"^:\[[^]]+\]\s*"#,
                    with: "",
                    options: .regularExpression
                )
                let cleaned = cleanMarkup(withoutIndex)
                return cleaned.isEmpty ? nil : cleaned
            }
    }

    private static func cleanMarkup(_ value: String) -> String {
        var result = value
        result = result.replacingOccurrences(of: #"<ref[^>]*>.*?</ref>"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"<ref[^>]*/>"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\[\[([^]|]+)\|([^]]+)\]\]"#, with: "$2", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\[\[([^]]+)\]\]"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: "''", with: "")
        result = result.replacingOccurrences(of: #"\{\{K\|([^}]+)\}\}"#, with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\{\{[^}]+\}\}"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstCapture(pattern: String, in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return String(value[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// `@unchecked Sendable` is accurate: the `cache` is reached only under `lock`
/// and `session` is an immutable `let`.
package final class GermanWiktionaryDictionary: @unchecked Sendable {
    package enum LookupError: Error {
        case invalidWord
        case noEntry
        case invalidResponse
    }

    package static let shared = GermanWiktionaryDictionary()

    private let session: URLSession
    private let lock = NSLock()
    private var cache: [String: GermanDictionaryEntry] = [:]

    package init(session: URLSession = .shared) {
        self.session = session
    }

    package func lookup(_ query: String, completion: @escaping (Result<GermanDictionaryEntry, Error>) -> Void) {
        let word = VocabularyTextPolicy.normalizedVocabularyText(query)
        guard VocabularyTextPolicy.isSingleEnglishWord(word) else {
            completion(.failure(LookupError.invalidWord))
            return
        }
        let key = VocabularyTextPolicy.canonicalVocabularyKey(word)
        lock.lock()
        let cached = cache[key]
        lock.unlock()
        if let cached {
            completion(.success(cached))
            return
        }
        fetchPage(word: word) { [weak self] result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let parsed):
                if parsed.meanings.isEmpty,
                   let lemma = parsed.lemma,
                   VocabularyTextPolicy.canonicalVocabularyKey(lemma) != key {
                    self?.fetchPage(word: lemma) { lemmaResult in
                        switch lemmaResult {
                        case .failure(let error):
                            completion(.failure(error))
                        case .success(let lemmaPage):
                            self?.finishEntry(requestedWord: word, fallbackLemma: lemma, page: lemmaPage, completion: completion)
                        }
                    }
                    return
                }
                self?.finishEntry(requestedWord: word, fallbackLemma: word, page: parsed, completion: completion)
            }
        }
    }

    private func finishEntry(
        requestedWord: String,
        fallbackLemma: String,
        page: GermanWiktionaryParser.ParsedPage,
        completion: @escaping (Result<GermanDictionaryEntry, Error>) -> Void
    ) {
        guard !page.meanings.isEmpty else {
            completion(.failure(LookupError.noEntry))
            return
        }
        let entry = GermanDictionaryEntry(
            requestedWord: requestedWord,
            lemma: page.lemma ?? fallbackLemma,
            partOfSpeech: page.partOfSpeech,
            meanings: page.meanings,
            flexion: page.flexion
        )

        lock.lock()
        cache[VocabularyTextPolicy.canonicalVocabularyKey(requestedWord)] = entry
        lock.unlock()
        completion(.success(entry))
    }

    private func fetchPage(
        word: String,
        completion: @escaping (Result<GermanWiktionaryParser.ParsedPage, Error>) -> Void
    ) {
        var components = URLComponents(string: "https://de.wiktionary.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "parse"),
            URLQueryItem(name: "page", value: word),
            URLQueryItem(name: "prop", value: "wikitext"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2")
        ]
        guard let url = components?.url else {
            completion(.failure(LookupError.invalidWord))
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("LeafVocabulary/1.0 (German vocabulary lookup)", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let parse = object["parse"] as? [String: Any],
                  let wikitext = parse["wikitext"] as? String,
                  let parsed = GermanWiktionaryParser.parse(wikitext: wikitext) else {
                completion(.failure(LookupError.noEntry))
                return
            }
            completion(.success(parsed))
        }.resume()
    }
}
