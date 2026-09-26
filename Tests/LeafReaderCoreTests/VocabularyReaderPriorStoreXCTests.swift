import Foundation
import SQLite3
import XCTest
@testable import LeafReaderCore

final class VocabularyReaderPriorStoreXCTests: XCTestCase {
    func testEligibilityRequiresFreshTwoSessionFortyVerifiedProfile() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let posterior = Array(repeating: 1.0 / 121.0, count: 121)
        XCTAssertTrue(VocabularyReaderPrior(
            languageCode: "en",
            thetaPosterior: posterior,
            completedSessionCount: 2,
            verifiedEvidenceCount: 40,
            lastUpdatedAt: now.addingTimeInterval(-179 * 24 * 60 * 60),
            algorithmVersion: 3
        ).isEligible(at: now))
        XCTAssertFalse(VocabularyReaderPrior(
            languageCode: "en",
            thetaPosterior: posterior,
            completedSessionCount: 1,
            verifiedEvidenceCount: 40,
            lastUpdatedAt: now,
            algorithmVersion: 3
        ).isEligible(at: now))
        XCTAssertFalse(VocabularyReaderPrior(
            languageCode: "en",
            thetaPosterior: posterior,
            completedSessionCount: 2,
            verifiedEvidenceCount: 39,
            lastUpdatedAt: now,
            algorithmVersion: 3
        ).isEligible(at: now))
    }

    func testStoreIsIdempotentPerCompletedSessionAndResetIsLanguageScoped() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("reader-prior-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = VocabularyReaderPriorStore(
            databaseURL: directory.appendingPathComponent("personal-vocabulary.sqlite3")
        )
        let posterior = Array(repeating: 1.0 / 121.0, count: 121)
        for _ in 0..<2 {
            XCTAssertTrue(store.recordCompletedSession(
                contributionID: "same-session",
                languageCode: "en",
                thetaPosterior: posterior,
                verifiedEvidenceCount: 24,
                completedAt: Date(timeIntervalSince1970: 100),
                algorithmVersion: 3
            ))
        }
        XCTAssertTrue(store.recordCompletedSession(
            contributionID: "german-session",
            languageCode: "de",
            thetaPosterior: posterior,
            verifiedEvidenceCount: 20,
            completedAt: Date(timeIntervalSince1970: 200),
            algorithmVersion: 3
        ))

        XCTAssertEqual(store.load(languageCode: "en")?.completedSessionCount, 1)
        XCTAssertEqual(store.load(languageCode: "en")?.verifiedEvidenceCount, 24)
        XCTAssertEqual(store.summaries().map(\.languageCode), ["de", "en"])
        XCTAssertTrue(store.reset(languageCode: "en"))
        XCTAssertNil(store.load(languageCode: "en"))
        XCTAssertNotNil(store.load(languageCode: "de"))
    }

    func testAlgorithmVersionChangeStartsFreshEligibilityEvidence() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("reader-prior-version-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = VocabularyReaderPriorStore(
            databaseURL: directory.appendingPathComponent("personal-vocabulary.sqlite3")
        )
        let posterior = Array(repeating: 1.0 / 121.0, count: 121)

        for index in 1...2 {
            XCTAssertTrue(store.recordCompletedSession(
                contributionID: "v3-\(index)",
                languageCode: "en",
                thetaPosterior: posterior,
                verifiedEvidenceCount: 24,
                completedAt: Date(timeIntervalSince1970: Double(index)),
                algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion
            ))
        }
        let v3 = try XCTUnwrap(store.load(languageCode: "en"))
        XCTAssertEqual(v3.completedSessionCount, 2)
        XCTAssertEqual(v3.verifiedEvidenceCount, 48)

        XCTAssertTrue(store.recordCompletedSession(
            contributionID: "v5-1",
            languageCode: "en",
            thetaPosterior: posterior,
            verifiedEvidenceCount: 24,
            completedAt: Date(timeIntervalSince1970: 3),
            algorithmVersion: VocabularyPreparationSession.lexicalReconciliationAlgorithmVersion
        ))
        let firstV5 = try XCTUnwrap(store.load(languageCode: "en"))
        XCTAssertEqual(
            firstV5.algorithmVersion,
            VocabularyPreparationSession.lexicalReconciliationAlgorithmVersion
        )
        XCTAssertEqual(firstV5.completedSessionCount, 1)
        XCTAssertEqual(firstV5.verifiedEvidenceCount, 24)
        XCTAssertFalse(firstV5.isEligible(at: Date(timeIntervalSince1970: 3)))

        XCTAssertTrue(store.recordCompletedSession(
            contributionID: "v5-2",
            languageCode: "en",
            thetaPosterior: posterior,
            verifiedEvidenceCount: 24,
            completedAt: Date(timeIntervalSince1970: 4),
            algorithmVersion: VocabularyPreparationSession.lexicalReconciliationAlgorithmVersion
        ))
        let secondV5 = try XCTUnwrap(store.load(languageCode: "en"))
        XCTAssertEqual(secondV5.completedSessionCount, 2)
        XCTAssertEqual(secondV5.verifiedEvidenceCount, 48)
        XCTAssertTrue(secondV5.isEligible(at: Date(timeIntervalSince1970: 4)))
    }

    func testWarmStartSmoothsAndMixesStoredPosterior() throws {
        var concentrated = Array(repeating: 0.0, count: 121)
        concentrated[90] = 1
        let prior = VocabularyReaderPrior(
            languageCode: "en",
            thetaPosterior: concentrated,
            completedSessionCount: 2,
            verifiedEvidenceCount: 40,
            lastUpdatedAt: Date(),
            algorithmVersion: 3
        )
        let grid = stride(from: -6.0, through: 6.0001, by: 0.1).map { $0 }
        let generic = Array(repeating: 1.0 / 121.0, count: 121)
        let warm = try XCTUnwrap(prior.warmStartPosterior(thetaGrid: grid, genericPrior: generic))

        XCTAssertEqual(warm.reduce(0, +), 1, accuracy: 1e-12)
        XCTAssertGreaterThan(warm[90], warm[60])
        XCTAssertGreaterThan(warm[89], generic[89] * 0.1)
        XCTAssertGreaterThan(warm[0], 0)
    }

    func testWarmStartWeightIsExplicitAndProductionDefaultIsUnchanged() throws {
        var concentrated = Array(repeating: 0.0, count: 121)
        concentrated[90] = 1
        let prior = VocabularyReaderPrior(
            languageCode: "en",
            thetaPosterior: concentrated,
            completedSessionCount: 2,
            verifiedEvidenceCount: 40,
            lastUpdatedAt: Date(),
            algorithmVersion: 3
        )
        let grid = (0...120).map { -6.0 + Double($0) * 0.1 }
        let generic = Array(repeating: 1.0 / 121.0, count: 121)
        let genericOnly = try XCTUnwrap(prior.warmStartPosterior(
            thetaGrid: grid,
            genericPrior: generic,
            warmPriorWeight: 0
        ))
        let storedOnly = try XCTUnwrap(prior.warmStartPosterior(
            thetaGrid: grid,
            genericPrior: generic,
            warmPriorWeight: 1
        ))
        let production = try XCTUnwrap(prior.warmStartPosterior(
            thetaGrid: grid,
            genericPrior: generic
        ))

        XCTAssertTrue(zip(genericOnly, generic).allSatisfy { abs($0 - $1) < 1e-15 })
        XCTAssertGreaterThan(storedOnly[90], production[90])
        XCTAssertEqual(production[90], storedOnly[90] * 0.9 + generic[90] * 0.1, accuracy: 1e-12)
    }

    func testFailedWriteCanRetryThroughReopenedIsolatedStoreWithoutDoubleCounting() throws {
        let posterior = Array(repeating: 1.0 / 121.0, count: 121)
        let unavailable = VocabularyReaderPriorStore(databaseURL: nil)
        XCTAssertFalse(unavailable.recordCompletedSession(
            contributionID: "retry-session",
            languageCode: "en",
            thetaPosterior: posterior,
            verifiedEvidenceCount: 24,
            completedAt: Date(timeIntervalSince1970: 100),
            algorithmVersion: 3
        ))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("reader-prior-retry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("isolated.sqlite3")
        XCTAssertTrue(VocabularyReaderPriorStore(databaseURL: databaseURL).recordCompletedSession(
            contributionID: "retry-session",
            languageCode: "en",
            thetaPosterior: posterior,
            verifiedEvidenceCount: 24,
            completedAt: Date(timeIntervalSince1970: 100),
            algorithmVersion: 3
        ))
        XCTAssertTrue(VocabularyReaderPriorStore(databaseURL: databaseURL).recordCompletedSession(
            contributionID: "retry-session",
            languageCode: "en",
            thetaPosterior: posterior,
            verifiedEvidenceCount: 24,
            completedAt: Date(timeIntervalSince1970: 100),
            algorithmVersion: 3
        ))

        let reopened = try XCTUnwrap(
            VocabularyReaderPriorStore(databaseURL: databaseURL).load(languageCode: "en")
        )
        XCTAssertEqual(reopened.completedSessionCount, 1)
        XCTAssertEqual(reopened.verifiedEvidenceCount, 24)
        XCTAssertTrue(zip(reopened.thetaPosterior, posterior).allSatisfy {
            abs($0 - $1) < 1e-15
        })
    }

    func testFutureTimestampAndIncompatibleVersionRemainIneligible() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let posterior = Array(repeating: 1.0 / 121.0, count: 121)
        XCTAssertFalse(VocabularyReaderPrior(
            languageCode: "en",
            thetaPosterior: posterior,
            completedSessionCount: 2,
            verifiedEvidenceCount: 40,
            lastUpdatedAt: now.addingTimeInterval(1),
            algorithmVersion: 3
        ).isEligible(at: now))
        let incompatible = VocabularyReaderPrior(
            languageCode: "en",
            thetaPosterior: posterior,
            completedSessionCount: 2,
            verifiedEvidenceCount: 40,
            lastUpdatedAt: now,
            algorithmVersion: 2
        )
        XCTAssertTrue(incompatible.isEligible(at: now))
        XCTAssertFalse(AdaptiveVocabularyAssessment(
            inventory: DocumentVocabularyInventory(languageCode: "en", candidates: []),
            mode: .targetCoverage(0.98),
            readerPrior: incompatible,
            currentDate: now
        ).usedEligibleReaderPrior)
    }

    func testSupersededExperimentalPriorsCannotWarmCurrentLexicalProtocol() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let posterior = Array(repeating: 1.0 / 121.0, count: 121)
        XCTAssertEqual(VocabularyPreparationSession.lexicalReconciliationAlgorithmVersion, 7)
        for supersededVersion in [4, 5, 6] {
            let superseded = VocabularyReaderPrior(
                languageCode: "en",
                thetaPosterior: posterior,
                completedSessionCount: 2,
                verifiedEvidenceCount: 40,
                lastUpdatedAt: now,
                algorithmVersion: supersededVersion
            )

            XCTAssertTrue(superseded.isEligible(at: now))
            XCTAssertFalse(AdaptiveVocabularyAssessment(
                inventory: DocumentVocabularyInventory(languageCode: "en", candidates: []),
                mode: .targetCoverage(0.98),
                readerPrior: superseded,
                currentDate: now,
                algorithmVersion: VocabularyPreparationSession.lexicalReconciliationAlgorithmVersion
            ).usedEligibleReaderPrior)
        }
    }

    func testSemanticFingerprintChangeArchivesPriorAndStartsFreshProfileAfterReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("reader-prior-semantic-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("personal-vocabulary.sqlite3")
        let firstFingerprint = try compatibilityFingerprint(profileVersion: "profile-v1")
        let secondFingerprint = try compatibilityFingerprint(profileVersion: "profile-v2")
        let posterior = Array(repeating: 1.0 / 121.0, count: 121)

        do {
            let store = VocabularyReaderPriorStore(databaseURL: databaseURL)
            for index in 1...2 {
                XCTAssertTrue(store.recordCompletedSession(
                    contributionID: "first-\(index)",
                    languageCode: "en",
                    thetaPosterior: posterior,
                    verifiedEvidenceCount: 24,
                    completedAt: Date(timeIntervalSince1970: Double(index)),
                    algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion,
                    compatibilityFingerprint: firstFingerprint
                ))
            }
            XCTAssertEqual(
                store.load(languageCode: "en", compatibilityFingerprint: firstFingerprint)?.completedSessionCount,
                2
            )
            XCTAssertNil(store.load(languageCode: "en", compatibilityFingerprint: secondFingerprint))

            XCTAssertTrue(store.recordCompletedSession(
                contributionID: "second-1",
                languageCode: "en",
                thetaPosterior: posterior,
                verifiedEvidenceCount: 24,
                completedAt: Date(timeIntervalSince1970: 3),
                algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion,
                compatibilityFingerprint: secondFingerprint
            ))
            let active = try XCTUnwrap(store.load(
                languageCode: "en",
                compatibilityFingerprint: secondFingerprint
            ))
            XCTAssertEqual(active.completedSessionCount, 1)
            XCTAssertEqual(active.verifiedEvidenceCount, 24)
            XCTAssertEqual(active.compatibilityFingerprintDigest, secondFingerprint.stableDigest)

            let archived = try XCTUnwrap(store.archivedPriors(languageCode: "en").only)
            XCTAssertEqual(archived.prior.completedSessionCount, 2)
            XCTAssertEqual(archived.prior.verifiedEvidenceCount, 48)
            XCTAssertEqual(archived.prior.compatibilityFingerprintDigest, firstFingerprint.stableDigest)
        }

        let reopened = VocabularyReaderPriorStore(databaseURL: databaseURL)
        XCTAssertEqual(
            reopened.load(languageCode: "en", compatibilityFingerprint: secondFingerprint)?.completedSessionCount,
            1
        )
        XCTAssertEqual(reopened.archivedPriors(languageCode: "en").count, 1)
        XCTAssertTrue(reopened.recordCompletedSession(
            contributionID: "second-1",
            languageCode: "en",
            thetaPosterior: posterior,
            verifiedEvidenceCount: 24,
            completedAt: Date(timeIntervalSince1970: 3),
            algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion,
            compatibilityFingerprint: secondFingerprint
        ))
        XCTAssertEqual(reopened.archivedPriors(languageCode: "en").count, 1)
        XCTAssertEqual(
            reopened.load(languageCode: "en", compatibilityFingerprint: secondFingerprint)?.completedSessionCount,
            1
        )
    }

    func testLegacyPriorWithoutFingerprintIsIneligibleAndRecoverableAfterSemanticReplacement() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("reader-prior-legacy-semantic-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("personal-vocabulary.sqlite3")
        let fingerprint = try compatibilityFingerprint(profileVersion: "profile-v1")
        let posterior = Array(repeating: 1.0 / 121.0, count: 121)
        let store = VocabularyReaderPriorStore(databaseURL: databaseURL)

        XCTAssertTrue(store.recordCompletedSession(
            contributionID: "legacy",
            languageCode: "en",
            thetaPosterior: posterior,
            verifiedEvidenceCount: 24,
            completedAt: Date(timeIntervalSince1970: 1),
            algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion
        ))
        XCTAssertNil(store.load(languageCode: "en", compatibilityFingerprint: fingerprint))

        XCTAssertTrue(store.recordCompletedSession(
            contributionID: "semantic",
            languageCode: "en",
            thetaPosterior: posterior,
            verifiedEvidenceCount: 24,
            completedAt: Date(timeIntervalSince1970: 2),
            algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion,
            compatibilityFingerprint: fingerprint
        ))
        XCTAssertEqual(
            store.load(languageCode: "en", compatibilityFingerprint: fingerprint)?.completedSessionCount,
            1
        )
        let archived = try XCTUnwrap(store.archivedPriors(languageCode: "en").only)
        XCTAssertEqual(archived.prior.completedSessionCount, 1)
        XCTAssertNil(archived.prior.compatibilityFingerprintDigest)

        XCTAssertTrue(store.reset(languageCode: "en"))
        XCTAssertNil(store.load(languageCode: "en"))
        XCTAssertTrue(store.archivedPriors(languageCode: "en").isEmpty)
    }

    func testArchiveFailureRollsBackReplacementAndContributionForRetry() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("reader-prior-archive-failure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("personal-vocabulary.sqlite3")
        let firstFingerprint = try compatibilityFingerprint(profileVersion: "profile-v1")
        let secondFingerprint = try compatibilityFingerprint(profileVersion: "profile-v2")
        let posterior = Array(repeating: 1.0 / 121.0, count: 121)
        let store = VocabularyReaderPriorStore(databaseURL: databaseURL)

        XCTAssertTrue(store.recordCompletedSession(
            contributionID: "first",
            languageCode: "en",
            thetaPosterior: posterior,
            verifiedEvidenceCount: 24,
            completedAt: Date(timeIntervalSince1970: 1),
            algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion,
            compatibilityFingerprint: firstFingerprint
        ))

        try executeSQLite(
            databaseURL: databaseURL,
            sql: """
            CREATE TRIGGER fail_reader_prior_archive
            BEFORE INSERT ON vocabulary_reader_prior_archives
            BEGIN
                SELECT RAISE(ABORT, 'injected archive failure');
            END
            """
        )
        XCTAssertFalse(store.recordCompletedSession(
            contributionID: "second",
            languageCode: "en",
            thetaPosterior: posterior,
            verifiedEvidenceCount: 24,
            completedAt: Date(timeIntervalSince1970: 2),
            algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion,
            compatibilityFingerprint: secondFingerprint
        ))
        XCTAssertEqual(
            store.load(languageCode: "en", compatibilityFingerprint: firstFingerprint)?.completedSessionCount,
            1
        )
        XCTAssertNil(store.load(languageCode: "en", compatibilityFingerprint: secondFingerprint))
        XCTAssertTrue(store.archivedPriors(languageCode: "en").isEmpty)

        try executeSQLite(databaseURL: databaseURL, sql: "DROP TRIGGER fail_reader_prior_archive")
        XCTAssertTrue(store.recordCompletedSession(
            contributionID: "second",
            languageCode: "en",
            thetaPosterior: posterior,
            verifiedEvidenceCount: 24,
            completedAt: Date(timeIntervalSince1970: 2),
            algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion,
            compatibilityFingerprint: secondFingerprint
        ))
        XCTAssertEqual(
            store.load(languageCode: "en", compatibilityFingerprint: secondFingerprint)?.completedSessionCount,
            1
        )
        XCTAssertEqual(store.archivedPriors(languageCode: "en").count, 1)
    }

    private func compatibilityFingerprint(
        profileVersion: String
    ) throws -> VocabularyPreparationCompatibilityFingerprint {
        VocabularyPreparationCompatibilityFingerprint(
            algorithmVersion: VocabularyPreparationSession.currentAlgorithmVersion,
            language: try XCTUnwrap(VocabularyLanguageID("en")),
            languageProfileVersion: profileVersion,
            linguisticProviders: [
                VocabularySemanticProviderIdentity(
                    id: "linguistic.test",
                    version: "1",
                    normalizationVersion: "normalization-v1"
                )
            ],
            linguisticRuntimeSignature: "runtime-v1",
            difficultyProvider: VocabularyDifficultyProviderSemanticIdentity(
                providerID: "difficulty.test",
                providerVersion: "1"
            ),
            definitionProvider: VocabularySemanticProviderIdentity(
                id: "definition.test",
                version: "1",
                normalizationVersion: "normalization-v1"
            ),
            normalizationVersion: "normalization-v1",
            assessmentPolicyVersion: "assessment-v1"
        )
    }

    private func executeSQLite(databaseURL: URL, sql: String) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &database), SQLITE_OK)
        defer { sqlite3_close(database) }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        let message = errorMessage.map { String(cString: $0) }
        sqlite3_free(errorMessage)
        XCTAssertEqual(result, SQLITE_OK, message ?? "SQLite statement failed")
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
