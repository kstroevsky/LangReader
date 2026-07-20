import Foundation

@main
struct GermanDictionaryLiveLookupTestRunner {
    static func main() {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<GermanDictionaryEntry, Error>?
        GermanWiktionaryDictionary.shared.lookup("Bewerbungsunterlagen") {
            result = $0
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 20) == .success else {
            fputs("GermanDictionaryLiveLookupTests failed: lookup timed out\n", stderr)
            exit(1)
        }
        switch result {
        case .success(let entry):
            guard entry.lemma == "Bewerbungsunterlage",
                  entry.meanings.contains(where: { $0.contains("Dokumente") }) else {
                fputs("GermanDictionaryLiveLookupTests failed: unexpected entry \(entry)\n", stderr)
                exit(1)
            }
            print("GermanDictionaryLiveLookupTests passed: \(entry.requestedWord) → \(entry.lemma)")
        case .failure(let error):
            fputs("GermanDictionaryLiveLookupTests failed: \(error)\n", stderr)
            exit(1)
        case nil:
            fputs("GermanDictionaryLiveLookupTests failed: missing result\n", stderr)
            exit(1)
        }

        verifyFlexionTables()
    }

    /// Parses live flexion tables from full pages.
    ///
    /// The offline fixtures are hand-trimmed excerpts, so only this check
    /// proves the allowlist still holds against the complete wikitext — real
    /// pages carry many more image parameters than an excerpt does.
    private static func verifyFlexionTables() {
        // (page, form, expected parameter that must list it)
        let expectations: [(page: String, form: String, parameter: String)] = [
            ("Haus", "Häuser", "Nominativ Plural"),
            ("Problem", "Probleme", "Nominativ Plural"),
            ("Buch", "Bücher", "Nominativ Plural"),
            ("gehen", "gegangen", "Partizip II"),
            ("gehen", "ging", "Präteritum_ich")
        ]

        for expectation in expectations {
            guard let wikitext = fetchWikitext(page: expectation.page) else {
                fputs("GermanDictionaryLiveLookupTests failed: could not fetch \(expectation.page)\n", stderr)
                exit(1)
            }
            guard let table = GermanWiktionaryParser.parseFlexion(wikitext: wikitext) else {
                fputs("GermanDictionaryLiveLookupTests failed: no flexion table for \(expectation.page)\n", stderr)
                exit(1)
            }
            guard table.forms(labeled: expectation.parameter).contains(expectation.form) else {
                fputs("""
                GermanDictionaryLiveLookupTests failed: \(expectation.page) \
                should list \(expectation.form) under \(expectation.parameter)\n
                """, stderr)
                exit(1)
            }
            let leaked = table.forms.filter {
                $0.label.hasPrefix("Bild")
                    || $0.surface.contains(".jpg")
                    || $0.surface.contains(".gif")
                    || $0.surface.contains(".png")
            }
            guard leaked.isEmpty else {
                fputs("""
                GermanDictionaryLiveLookupTests failed: \(expectation.page) \
                leaked image parameters as forms: \(leaked.map(\.surface))\n
                """, stderr)
                exit(1)
            }
        }
        print("GermanDictionaryLiveLookupTests passed: flexion tables parsed for \(Set(expectations.map(\.page)).count) pages")
    }

    private static func fetchWikitext(page: String) -> String? {
        var components = URLComponents(string: "https://de.wiktionary.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "parse"),
            URLQueryItem(name: "page", value: page),
            URLQueryItem(name: "prop", value: "wikitext"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2")
        ]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(
            "LeafVocabulary/1.0 (German vocabulary lookup)",
            forHTTPHeaderField: "User-Agent"
        )

        let semaphore = DispatchSemaphore(value: 0)
        var wikitext: String?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }
            guard let data,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let parse = object["parse"] as? [String: Any] else {
                return
            }
            wikitext = parse["wikitext"] as? String
        }.resume()
        guard semaphore.wait(timeout: .now() + 25) == .success else { return nil }
        return wikitext
    }
}
