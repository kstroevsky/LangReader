import XCTest
import LeafReaderCore
@testable import LeafReaderApp

final class VocabularyLanguageCatalogXCTests: XCTestCase {
    func testPreparationReleaseListComesFromCatalogCapabilities() {
        let catalog = VocabularyLanguageCatalogFactory.live()

        XCTAssertEqual(
            catalog.releasedLanguages(for: .vocabularyPreparation),
            [.german, .english].sorted { $0.bcp47 < $1.bcp47 }
        )
    }

    func testPartialProfilesDoNotInheritEnglishProviders() throws {
        let catalog = VocabularyLanguageCatalogFactory.live()
        let french = try XCTUnwrap(catalog.resolve(language: .french))
        let italian = try XCTUnwrap(catalog.resolve(language: .italian))

        XCTAssertTrue(french.status(for: .exactForm).isAvailable)
        XCTAssertTrue(french.status(for: .lemmaEvidence).isAvailable)
        XCTAssertFalse(french.status(for: .vocabularyPreparation).isAvailable)
        XCTAssertNil(french.definitions)
        XCTAssertNil(french.difficulty)

        XCTAssertTrue(italian.status(for: .exactForm).isAvailable)
        XCTAssertFalse(italian.status(for: .lemmaEvidence).isAvailable)
        XCTAssertFalse(italian.status(for: .vocabularyPreparation).isAvailable)
        XCTAssertNil(italian.definitions)
        XCTAssertNil(italian.difficulty)
    }

    func testECDICTMetadataAbstainsOutsideEnglish() {
        XCTAssertNil(VocabularyDictionaryMetadataService.metadata(for: "Haus", language: .german))
        XCTAssertNil(VocabularyDictionaryMetadataService.metadata(for: "casa", language: .italian))
    }

    func testDefinitionProvidersAreSelectedOnlyForCompatibleLanguages() throws {
        let catalog = VocabularyLanguageCatalogFactory.live()

        XCTAssertEqual(
            catalog.definitionProvider(for: .english)?.descriptor.id,
            "dictionary.ecdict"
        )
        XCTAssertEqual(
            catalog.definitionProvider(for: .german)?.descriptor.id,
            "dictionary.de-wiktionary"
        )
        XCTAssertNil(catalog.definitionProvider(for: .french))

        let regionalEnglish = try XCTUnwrap(VocabularyLanguageID("en-GB"))
        XCTAssertEqual(
            catalog.definitionProvider(for: regionalEnglish)?.descriptor.id,
            "dictionary.ecdict"
        )
    }

    @MainActor
    func testDefinitionRoutingIdentityRejectsLanguageRevisionChanges() throws {
        let provider = try XCTUnwrap(
            VocabularyLanguageCatalogFactory.live().definitionProvider(for: .english)
        )
        let panel = AIChatPanel(frame: .zero)
        let initial = VocabularyDefinitionRoutingContext(
            language: .english,
            languageRevision: 3,
            provider: provider
        )
        panel.onVocabularyDefinitionContextRequested = { initial }

        XCTAssertTrue(panel.isDefinitionRoutingIdentityCurrent(initial.identity))

        panel.onVocabularyDefinitionContextRequested = {
            VocabularyDefinitionRoutingContext(
                language: .english,
                languageRevision: 4,
                provider: provider
            )
        }
        XCTAssertFalse(panel.isDefinitionRoutingIdentityCurrent(initial.identity))
    }

    func testEnglishDefinitionProviderRejectsGermanRequest() async {
        let provider = EnglishECDICTVocabularyDefinitionProvider()
        do {
            _ = try await provider.definition(for: VocabularyDefinitionRequest(
                language: .german,
                lemma: "Haus",
                context: ""
            ))
            XCTFail("Expected a language mismatch to fail closed")
        } catch let error as VocabularyDefinitionProviderError {
            XCTAssertEqual(
                error,
                .incompatibleLanguage(requested: .german, providerID: provider.descriptor.id)
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
