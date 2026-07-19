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
    }
}
