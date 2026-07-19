import Foundation

struct GermanDictionaryEntry: Equatable {
    let requestedWord: String
    let lemma: String
    let partOfSpeech: String?
    let meanings: [String]

    var metadata: VocabularyDictionaryMetadata {
        VocabularyDictionaryMetadata(tags: partOfSpeech, frequency: nil)
    }

    var sourceURL: URL? {
        var components = URLComponents(string: "https://de.wiktionary.org/wiki/")
        components?.path = "/wiki/" + lemma.replacingOccurrences(of: " ", with: "_")
        return components?.url
    }

    var markdown: String {
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

enum GermanWiktionaryParser {
    struct ParsedPage: Equatable {
        let lemma: String?
        let partOfSpeech: String?
        let meanings: [String]
    }

    static func parse(wikitext: String) -> ParsedPage? {
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
        return ParsedPage(lemma: lemma, partOfSpeech: partOfSpeech, meanings: meanings)
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

final class GermanWiktionaryDictionary {
    enum LookupError: Error {
        case invalidWord
        case noEntry
        case invalidResponse
    }

    static let shared = GermanWiktionaryDictionary()

    private let session: URLSession
    private let lock = NSLock()
    private var cache: [String: GermanDictionaryEntry] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func lookup(_ query: String, completion: @escaping (Result<GermanDictionaryEntry, Error>) -> Void) {
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
            meanings: page.meanings
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
