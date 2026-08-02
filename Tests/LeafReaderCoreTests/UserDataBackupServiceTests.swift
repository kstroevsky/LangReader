import Foundation
import SQLite3
import LeafReaderCore

enum UserDataBackupServiceTests {
    private struct Fixture {
        let root: URL
        let support: URL
        let backup: URL
        let defaults: UserDefaults
        let domain: String

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("LeafReaderBackupTests-\(UUID().uuidString)", isDirectory: true)
            support = root.appendingPathComponent("ApplicationSupport", isDirectory: true)
            backup = root.appendingPathComponent("snapshot.leafreaderbackup", isDirectory: true)
            domain = "LeafReaderBackupTests.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: domain) else {
                throw TestFailure(description: "could not create isolated defaults")
            }
            self.defaults = defaults
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        }

        func service(
            checkpoint: (@Sendable (Int) throws -> Void)? = nil
        ) -> UserDataBackupService {
            UserDataBackupService(
                configuration: UserDataBackupConfiguration(
                    applicationSupportDirectory: support,
                    preferencesDomainName: domain,
                    defaults: defaults
                ),
                restoreCheckpoint: checkpoint
            )
        }

        func cleanUp() {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        }
    }

    static func testRoundTripRestoresDatabasesPreferencesAndAssets() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        try seedManagedData(fixture, value: "before")
        fixture.defaults.set("before", forKey: "readerTheme")
        fixture.defaults.synchronize()

        let manifest = try fixture.service().createBackup(at: fixture.backup)
        try expectEqual(manifest.schemaVersion, 1, "the backup format is explicitly versioned")
        try expect(
            manifest.entries.contains { $0.relativePath == "preferences.plist" },
            "preferences are listed in the validated manifest"
        )
        try expect(
            !manifest.entries.contains { $0.relativePath.hasSuffix("-wal") || $0.relativePath.hasSuffix("-shm") },
            "live SQLite sidecars are replaced by consistent database snapshots"
        )

        try seedManagedData(fixture, value: "after")
        fixture.defaults.set("after", forKey: "readerTheme")
        fixture.defaults.synchronize()

        let result = try fixture.service().restoreBackup(at: fixture.backup)
        try expect(result.requiresRelaunch, "restoring stores requires a relaunch before they are reopened")
        try expectEqual(try databaseValue(fixture.support.appendingPathComponent("word-records.sqlite3")), "before", "word records restore")
        try expectEqual(try databaseValue(fixture.support.appendingPathComponent("personal-vocabulary.sqlite3")), "before", "personal vocabulary restores")
        try expectEqual(try databaseValue(fixture.support.appendingPathComponent("reading-notes.sqlite")), "before", "reading notes restore")
        try expectEqual(fixture.defaults.string(forKey: "readerTheme"), "before", "preferences restore")
        let asset = fixture.support.appendingPathComponent("ReadingNoteAssets/note-image.txt")
        try expectEqual(try String(contentsOf: asset, encoding: .utf8), "before", "note assets restore")
    }

    static func testTamperedPayloadIsRejectedBeforeMutation() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        try seedManagedData(fixture, value: "backup")
        fixture.defaults.set("backup", forKey: "readerTheme")
        _ = try fixture.service().createBackup(at: fixture.backup)

        try seedManagedData(fixture, value: "current")
        fixture.defaults.set("current", forKey: "readerTheme")
        let payloadAsset = fixture.backup
            .appendingPathComponent("payload/ReadingNoteAssets/note-image.txt")
        try Data("tampered".utf8).write(to: payloadAsset, options: .atomic)

        do {
            _ = try fixture.service().restoreBackup(at: fixture.backup)
            throw TestFailure(description: "a tampered backup should not restore")
        } catch is TestFailure {
            throw TestFailure(description: "a tampered backup should not restore")
        } catch {
            // Expected: validation fails before the transaction starts.
        }
        try expectEqual(try databaseValue(fixture.support.appendingPathComponent("word-records.sqlite3")), "current", "validation failure leaves databases untouched")
        try expectEqual(fixture.defaults.string(forKey: "readerTheme"), "current", "validation failure leaves preferences untouched")
    }

    static func testFailedRestoreRollsBackEveryReplacement() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        try seedManagedData(fixture, value: "backup")
        fixture.defaults.set("backup", forKey: "readerTheme")
        _ = try fixture.service().createBackup(at: fixture.backup)

        try seedManagedData(fixture, value: "current")
        fixture.defaults.set("current", forKey: "readerTheme")
        enum InjectedFailure: Error { case stop }
        let failingService = fixture.service { replacementCount in
            if replacementCount == 1 { throw InjectedFailure.stop }
        }

        do {
            _ = try failingService.restoreBackup(at: fixture.backup)
            throw TestFailure(description: "the injected restore failure should surface")
        } catch is TestFailure {
            throw TestFailure(description: "the injected restore failure should surface")
        } catch {
            // Expected: one replacement happened, then the transaction rolled back.
        }

        try expectEqual(try databaseValue(fixture.support.appendingPathComponent("word-records.sqlite3")), "current", "rollback restores the database that was already swapped")
        try expectEqual(try databaseValue(fixture.support.appendingPathComponent("personal-vocabulary.sqlite3")), "current", "rollback leaves later databases intact")
        try expectEqual(fixture.defaults.string(forKey: "readerTheme"), "current", "rollback preserves current preferences")
        let asset = fixture.support.appendingPathComponent("ReadingNoteAssets/note-image.txt")
        try expectEqual(try String(contentsOf: asset, encoding: .utf8), "current", "rollback preserves current assets")
    }

    static func testMissingDeclaredEmptyAssetsDirectoryIsRejected() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }

        try seedManagedData(fixture, value: "backup")
        let assets = fixture.support.appendingPathComponent("ReadingNoteAssets", isDirectory: true)
        try FileManager.default.removeItem(at: assets.appendingPathComponent("note-image.txt"))
        let manifest = try fixture.service().createBackup(at: fixture.backup)
        try expect(
            manifest.includesReadingNoteAssetsDirectory,
            "an empty managed assets directory remains part of the snapshot contract"
        )

        try FileManager.default.removeItem(
            at: fixture.backup.appendingPathComponent("payload/ReadingNoteAssets", isDirectory: true)
        )
        do {
            _ = try fixture.service().validateBackup(at: fixture.backup)
            throw TestFailure(description: "a missing declared assets directory should be rejected")
        } catch is TestFailure {
            throw TestFailure(description: "a missing declared assets directory should be rejected")
        } catch {
            // Expected: manifest structure validation catches the missing empty directory.
        }
    }

    static func testColdStartRecoveryRollsBackInterruptedRestore() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try seedManagedData(fixture, value: "before")

        let transaction = fixture.support.deletingLastPathComponent()
            .appendingPathComponent(".LeafVocabulary-restore-interrupted", isDirectory: true)
        let rollback = transaction.appendingPathComponent("rollback", isDirectory: true)
        try FileManager.default.createDirectory(at: rollback, withIntermediateDirectories: true)
        let wordDatabase = fixture.support.appendingPathComponent("word-records.sqlite3")
        try FileManager.default.moveItem(at: wordDatabase, to: rollback.appendingPathComponent("word-records.sqlite3"))
        try createDatabase(at: wordDatabase, value: "after")
        let priorPreferences = try PropertyListSerialization.data(fromPropertyList: [:], format: .binary, options: 0)
        try priorPreferences.write(to: rollback.appendingPathComponent("previous-preferences.plist"), options: .atomic)
        let journal = """
        {"phase":"applying","units":[
        {"name":"word-records.sqlite3","hadOriginal":true,"phase":"installed"},
        {"name":"personal-vocabulary.sqlite3","hadOriginal":true,"phase":"pending"},
        {"name":"reading-notes.sqlite","hadOriginal":true,"phase":"pending"},
        {"name":"ReadingNoteAssets","hadOriginal":true,"phase":"pending"}
        ],"preferencesApplyStarted":false,"preferencesApplied":false}
        """
        try Data(journal.utf8).write(to: transaction.appendingPathComponent("restore-journal.json"), options: .atomic)

        try fixture.service().recoverInterruptedRestoreIfNeeded()
        try expectEqual(try databaseValue(wordDatabase), "before", "cold-start recovery restores the original swapped database")
        try expect(!FileManager.default.fileExists(atPath: transaction.path), "verified recovery cleans its journal directory")
    }

    static func testBackupRejectsSymbolicLinkInManagedAssets() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try seedManagedData(fixture, value: "before")
        let assets = fixture.support.appendingPathComponent("ReadingNoteAssets", isDirectory: true)
        let symlink = assets.appendingPathComponent("linked-secret.txt")
        try FileManager.default.createSymbolicLink(
            atPath: symlink.path,
            withDestinationPath: fixture.root.appendingPathComponent("outside.txt").path
        )

        do {
            _ = try fixture.service().createBackup(at: fixture.backup)
            throw TestFailure(description: "a managed asset symlink must fail closed")
        } catch is TestFailure {
            throw TestFailure(description: "a managed asset symlink must fail closed")
        } catch {
            // Expected: archive enumeration rejects links instead of copying a
            // partial or out-of-tree asset set into the manifest.
        }
        try expect(!FileManager.default.fileExists(atPath: fixture.backup.path), "a rejected enumeration does not publish a backup")
    }

    @MainActor
    static func testCoordinatorRejectsBackupAfterPersistenceActivation() throws {
        let fixture = try Fixture()
        defer { fixture.cleanUp() }
        try seedManagedData(fixture, value: "before")
        let coordinator = UserDataBackupCoordinator(configuration: UserDataBackupConfiguration(
            applicationSupportDirectory: fixture.support,
            preferencesDomainName: fixture.domain,
            defaults: fixture.defaults
        ))
        coordinator.markPersistenceActive()

        do {
            _ = try coordinator.createColdStartBackup(at: fixture.backup)
            throw TestFailure(description: "a live persistence capture must be rejected")
        } catch is TestFailure {
            throw TestFailure(description: "a live persistence capture must be rejected")
        } catch {
            // Expected: only the cold-start coordinator may orchestrate a snapshot.
        }
    }

    private static func seedManagedData(_ fixture: Fixture, value: String) throws {
        for name in ["word-records.sqlite3", "personal-vocabulary.sqlite3", "reading-notes.sqlite"] {
            let url = fixture.support.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
            try createDatabase(at: url, value: value)
        }
        let assets = fixture.support.appendingPathComponent("ReadingNoteAssets", isDirectory: true)
        try? FileManager.default.removeItem(at: assets)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data(value.utf8).write(to: assets.appendingPathComponent("note-image.txt"), options: .atomic)
    }

    private static func createDatabase(at url: URL, value: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            throw TestFailure(description: "could not create SQLite fixture")
        }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, "CREATE TABLE state(value TEXT NOT NULL);", nil, nil, nil) == SQLITE_OK else {
            throw TestFailure(description: "could not create SQLite fixture table")
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO state(value) VALUES (?)", -1, &statement, nil) == SQLITE_OK else {
            throw TestFailure(description: "could not prepare SQLite fixture insert")
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TestFailure(description: "could not insert SQLite fixture")
        }
    }

    private static func databaseValue(_ url: URL) throws -> String {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw TestFailure(description: "could not open restored SQLite fixture")
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM state LIMIT 1", -1, &statement, nil) == SQLITE_OK else {
            throw TestFailure(description: "could not query restored SQLite fixture")
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0) else {
            throw TestFailure(description: "restored SQLite fixture has no value")
        }
        return String(cString: text)
    }
}
