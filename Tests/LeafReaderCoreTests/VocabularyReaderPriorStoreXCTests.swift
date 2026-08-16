import Foundation
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
}
