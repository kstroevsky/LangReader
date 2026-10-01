import XCTest
import NaturalLanguage
import LeafReaderCore
@testable import LeafReaderApp

final class VocabularyLanguageCatalogXCTests: XCTestCase {
    func testFeatureMatrixIsGeneratedFromDeclaredProfilesNotRuntimeAssets() throws {
        let noAppleAssets = VocabularyLanguageCatalogFactory.live(
            linguisticCapabilityProbe: { _ in
                AppleVocabularyLinguisticCapabilities(availableTagSchemes: [])
            }
        )
        let rows = noAppleAssets.declaredFeatureMatrixRows

        let english = try XCTUnwrap(rows.first { $0.language == .english })
        XCTAssertEqual(english.exact, .production)
        XCTAssertEqual(english.lemma, .production)
        XCTAssertEqual(english.partOfSpeech, .production)
        XCTAssertEqual(english.forms, .production)
        XCTAssertEqual(english.definition, .production)
        XCTAssertEqual(english.difficulty, .production)
        XCTAssertEqual(english.preparation, .production)

        let french = try XCTUnwrap(rows.first { $0.language == .french })
        XCTAssertEqual(french.exact, .production)
        XCTAssertEqual(french.lemma, .experimental)
        XCTAssertEqual(french.partOfSpeech, .experimental)
        XCTAssertEqual(french.forms, .disabled)
        XCTAssertEqual(french.definition, .disabled)
        XCTAssertEqual(french.difficulty, .disabled)
        XCTAssertEqual(french.preparation, .disabled)

        let italian = try XCTUnwrap(rows.first { $0.language == .italian })
        XCTAssertEqual(italian.exact, .production)
        XCTAssertEqual(italian.lemma, .disabled)
        XCTAssertEqual(italian.partOfSpeech, .disabled)
        XCTAssertEqual(italian.preparation, .disabled)

        XCTAssertTrue(noAppleAssets.declaredFeatureMatrixMarkdown.hasPrefix(
            "Language | Exact | Lemma | POS | Forms | Definition | Difficulty | Preparation\n"
        ))
    }

    private let fullAppleCapabilities = AppleVocabularyLinguisticCapabilities(
        availableTagSchemes: Set([
            NLTagScheme.lemma.rawValue,
            NLTagScheme.lexicalClass.rawValue,
            NLTagScheme.nameType.rawValue
        ])
    )

    func testPreparationReleaseListComesFromCatalogCapabilities() {
        let capabilities = fullAppleCapabilities
        let catalog = VocabularyLanguageCatalogFactory.live(
            linguisticCapabilityProbe: { _ in capabilities }
        )

        XCTAssertEqual(
            catalog.releasedLanguages(for: .vocabularyPreparation),
            [.german, .english].sorted { $0.bcp47 < $1.bcp47 }
        )
    }

    func testPartialProfilesDoNotInheritEnglishProviders() throws {
        let capabilities = fullAppleCapabilities
        let catalog = VocabularyLanguageCatalogFactory.live(
            linguisticCapabilityProbe: { _ in capabilities }
        )
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

    func testMissingAppleSchemesDegradeLinguisticsWithoutChangingLanguage() throws {
        let noAppleSchemes = AppleVocabularyLinguisticCapabilities(availableTagSchemes: [])
        let catalog = VocabularyLanguageCatalogFactory.live(
            linguisticCapabilityProbe: { _ in noAppleSchemes }
        )
        let german = try XCTUnwrap(catalog.resolve(language: .german))

        XCTAssertEqual(german.language, .german)
        XCTAssertTrue(german.status(for: .exactForm).isAvailable)
        XCTAssertFalse(german.status(for: .lemmaEvidence).isAvailable)
        XCTAssertFalse(german.status(for: .partOfSpeechEvidence).isAvailable)
        XCTAssertFalse(german.status(for: .vocabularyPreparation).isAvailable)
        XCTAssertEqual(
            german.linguisticCacheIdentity.linguisticProviders.map(\.id).sorted(),
            [
                "linguistics.exact-form",
                "morphology.german-deterministic"
            ]
        )
    }

    func testItalianPolicyDoesNotEnableAppleLemmaEvenWhenSchemeExists() throws {
        let capabilities = fullAppleCapabilities
        let catalog = VocabularyLanguageCatalogFactory.live(
            linguisticCapabilityProbe: { _ in capabilities }
        )
        let italian = try XCTUnwrap(catalog.resolve(language: .italian))

        XCTAssertEqual(italian.language, .italian)
        XCTAssertFalse(italian.status(for: .lemmaEvidence).isAvailable)
        XCTAssertFalse(
            italian.linguisticCacheIdentity.linguisticProviders.contains {
                $0.id == "linguistics.apple-natural-language"
            }
        )
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

    func testRegionalEnglishKeepsRequestedIdentityAndComposesCapabilitiesIndependently() throws {
        let regionalEnglish = try XCTUnwrap(VocabularyLanguageID("en-GB"))
        let capabilities = fullAppleCapabilities
        let catalog = VocabularyLanguageCatalogFactory.live(
            linguisticCapabilityProbe: { language in
                language == regionalEnglish
                    ? capabilities
                    : AppleVocabularyLinguisticCapabilities(availableTagSchemes: [])
            }
        )

        let runtime = try XCTUnwrap(catalog.resolve(language: regionalEnglish))
        XCTAssertEqual(runtime.language, regionalEnglish)
        XCTAssertEqual(runtime.profile.language, regionalEnglish)
        XCTAssertEqual(runtime.linguisticCacheIdentity.language, regionalEnglish)
        XCTAssertEqual(runtime.definitions?.descriptor.id, "dictionary.ecdict")
        XCTAssertNil(runtime.difficulty)
        XCTAssertTrue(runtime.status(for: .lemmaEvidence).isAvailable)
        XCTAssertFalse(runtime.status(for: .difficulty).isAvailable)
        XCTAssertFalse(runtime.status(for: .formLabels).isAvailable)
        XCTAssertFalse(runtime.status(for: .domainResources).isAvailable)
        XCTAssertFalse(runtime.status(for: .vocabularyPreparation).isAvailable)
    }

    func testRegionalGermanUsesDeclaredProfileWithoutBorrowingGermanDifficulty() throws {
        let regionalGerman = try XCTUnwrap(VocabularyLanguageID("de-AT"))
        let capabilities = fullAppleCapabilities
        let catalog = VocabularyLanguageCatalogFactory.live(
            linguisticCapabilityProbe: { language in
                language == regionalGerman
                    ? capabilities
                    : AppleVocabularyLinguisticCapabilities(availableTagSchemes: [])
            }
        )

        let runtime = try XCTUnwrap(catalog.resolve(language: regionalGerman))
        XCTAssertEqual(runtime.language, regionalGerman)
        XCTAssertEqual(runtime.definitions?.descriptor.id, "dictionary.de-wiktionary")
        XCTAssertNil(runtime.difficulty)
        XCTAssertFalse(runtime.linguisticCacheIdentity.linguisticProviders.contains {
            $0.id == "morphology.german-deterministic"
        })
        XCTAssertFalse(runtime.status(for: .vocabularyPreparation).isAvailable)
    }

    func testRegionalPartialProfileKeepsIdentityWithoutInventingProviders() throws {
        let regionalPortuguese = try XCTUnwrap(VocabularyLanguageID("pt-BR"))
        let capabilities = fullAppleCapabilities
        let catalog = VocabularyLanguageCatalogFactory.live(
            linguisticCapabilityProbe: { language in
                language == regionalPortuguese
                    ? capabilities
                    : AppleVocabularyLinguisticCapabilities(availableTagSchemes: [])
            }
        )

        let runtime = try XCTUnwrap(catalog.resolve(language: regionalPortuguese))
        XCTAssertEqual(runtime.language, regionalPortuguese)
        XCTAssertEqual(runtime.profile.language, regionalPortuguese)
        XCTAssertTrue(runtime.status(for: .lemmaEvidence).isAvailable)
        XCTAssertNil(runtime.definitions)
        XCTAssertNil(runtime.difficulty)
        XCTAssertFalse(runtime.status(for: .vocabularyPreparation).isAvailable)
    }

    func testDifficultyCompatibilityDoesNotInheritDictionaryRange() throws {
        let catalog = VocabularyLanguageCatalogFactory.live()
        let regionalEnglish = try XCTUnwrap(VocabularyLanguageID("en-GB"))
        let regionalGerman = try XCTUnwrap(VocabularyLanguageID("de-AT"))

        XCTAssertNotNil(catalog.difficultyProvider(for: .english))
        XCTAssertNotNil(catalog.difficultyProvider(for: .german))
        XCTAssertNil(catalog.difficultyProvider(for: regionalEnglish))
        XCTAssertNil(catalog.difficultyProvider(for: regionalGerman))
        XCTAssertNil(catalog.difficultyProvider(for: .french))
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
