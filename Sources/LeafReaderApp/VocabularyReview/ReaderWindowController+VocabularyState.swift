import Foundation
import NaturalLanguage
import LeafReaderCore

extension ReaderWindowController {
    /// Language the current document's vocabulary is grouped by. All lemma
    /// resolution and occurrence scanning for saved words must use this one
    /// value so their grouping keys stay consistent.
    var vocabularyDocumentLanguage: NLLanguage {
        get {
            vocabularyState.documentLanguageResolution.languageID?.appleNaturalLanguage ?? .undetermined
        }
        set {
            guard let language = VocabularyLanguageID(newValue.rawValue) else {
                _ = vocabularyState.updateLanguageResolution(.undetermined(.unresolved(.inconclusiveRecognition)))
                return
            }
            setVocabularyDocumentLanguageResolution(.resolved(VocabularyResolvedLanguage(
                id: language,
                provenance: .persistedDocumentMetadata
            )))
        }
    }

    var vocabularyDocumentLanguageResolution: VocabularyLanguageResolution {
        vocabularyState.documentLanguageResolution
    }

    var vocabularyDocumentLanguageID: VocabularyLanguageID? {
        vocabularyState.documentLanguageResolution.languageID
    }

    func resolvedVocabularyLemma(
        for surfaceForm: String,
        language: VocabularyLanguageID? = nil
    ) -> String {
        let surface = VocabularyTextPolicy.normalizedVocabularyText(surfaceForm)
        guard let language = language ?? vocabularyDocumentLanguageID else {
            return surface
        }
        let analyzerFactory = vocabularyLanguageCatalog.resolve(language: language)?.linguisticAnalyzerFactory
            ?? .exactForm
        return GermanLemmaResolver.lemma(
            for: surface,
            language: language,
            analyzerFactory: analyzerFactory
        )
    }

    func vocabularyGroupingKey(
        word: String,
        lemma: String? = nil,
        language: VocabularyLanguageID? = nil
    ) -> String {
        let fallback = VocabularyExporter.nonEmptyText(lemma)
            ?? VocabularyTextPolicy.normalizedVocabularyText(word)
        guard let language = language ?? vocabularyDocumentLanguageID else {
            return VocabularyTextPolicy.canonicalVocabularyKey(fallback)
        }
        let analyzerFactory = vocabularyLanguageCatalog.resolve(language: language)?.linguisticAnalyzerFactory
            ?? .exactForm
        return GermanLemmaResolver.groupingKey(
            word: word,
            lemma: lemma,
            language: language,
            analyzerFactory: analyzerFactory
        )
    }

    var vocabularyLanguageRevision: UInt64 { vocabularyState.languageRevision }

    func setVocabularyDocumentLanguageResolution(_ resolution: VocabularyLanguageResolution) {
        guard vocabularyState.updateLanguageResolution(resolution) else { return }
        guard let documentID = currentFileMD5 else { return }
        _ = VocabularyDocumentLanguageStore(documentID: documentID).save(resolution: resolution)
    }

    func restoreVocabularyDocumentLanguageMetadata() {
        guard let documentID = currentFileMD5,
              let resolution = VocabularyDocumentLanguageStore(documentID: documentID)
                .load()?
                .restoredResolution else { return }
        _ = vocabularyState.updateLanguageResolution(resolution, replacingUserSelection: true)
    }

    var storedWordRecords: [StoredPDFWordRecord] {
        get { vocabularyState.storedWordRecords }
        set { vocabularyState.storedWordRecords = newValue }
    }

    var pendingPDFWordRecords: [String: PendingPDFWordRecord] {
        get { vocabularyState.pendingPDFWordRecords }
        set { vocabularyState.pendingPDFWordRecords = newValue }
    }

    var pdfWordRecordStore: PDFWordRecordStore? {
        get { vocabularyState.pdfWordRecordStore }
        set { vocabularyState.pdfWordRecordStore = newValue }
    }

    var storedWebWordRecords: [StoredWebWordRecord] {
        get { vocabularyState.storedWebWordRecords }
        set { vocabularyState.storedWebWordRecords = newValue }
    }

    var pendingWebWordRecords: [String: PendingWebWordRecord] {
        get { vocabularyState.pendingWebWordRecords }
        set { vocabularyState.pendingWebWordRecords = newValue }
    }

    var webWordRecordStore: WebWordRecordStore? {
        get { vocabularyState.webWordRecordStore }
        set { vocabularyState.webWordRecordStore = newValue }
    }

    var currentVocabularyExportRecords: [VocabularyExportRecord] {
        get { vocabularyState.currentExportRecords }
        set { vocabularyState.currentExportRecords = newValue }
    }
}
