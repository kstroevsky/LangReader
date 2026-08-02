import CryptoKit
import Foundation
import SQLite3

package struct UserDataBackupConfiguration {
    package let applicationSupportDirectory: URL
    package let preferencesDomainName: String
    package let defaults: UserDefaults

    package init(
        applicationSupportDirectory: URL,
        preferencesDomainName: String,
        defaults: UserDefaults
    ) {
        self.applicationSupportDirectory = applicationSupportDirectory.standardizedFileURL
        self.preferencesDomainName = preferencesDomainName
        self.defaults = defaults
    }

    package static func production(defaults: UserDefaults = .standard) -> UserDataBackupConfiguration? {
        guard let supportRoot = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        return UserDataBackupConfiguration(
            applicationSupportDirectory: supportRoot
                .appendingPathComponent(AppIdentity.applicationSupportDirectoryName, isDirectory: true),
            preferencesDomainName: AppIdentity.bundleIdentifier,
            defaults: defaults
        )
    }
}

package struct UserDataBackupManifest: Codable, Equatable {
    package struct Entry: Codable, Equatable {
        package enum Kind: String, Codable {
            case database
            case preferences
            case readingNoteAsset
        }

        package let relativePath: String
        package let kind: Kind
        package let byteCount: Int64
        package let sha256: String
    }

    package let schemaVersion: Int
    package let createdAt: Date
    package let applicationBundleIdentifier: String
    package let preferencesDomainName: String
    package let includesReadingNoteAssetsDirectory: Bool
    package let entries: [Entry]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case createdAt = "created_at"
        case applicationBundleIdentifier = "application_bundle_identifier"
        case preferencesDomainName = "preferences_domain_name"
        case includesReadingNoteAssetsDirectory = "includes_reading_note_assets_directory"
        case entries
    }
}

package struct UserDataRestoreResult: Equatable {
    package let restoredEntryCount: Int
    package let requiresRelaunch: Bool
}

package enum UserDataBackupError: LocalizedError {
    case destinationExists(String)
    case invalidBackup(String)
    case unsupportedSchema(Int)
    case incompatibleApplication(String)
    case fileOperation(String)
    case sqliteSnapshot(String)
    case sqliteIntegrity(String)
    case preferences(String)
    case rollbackFailed(String)

    package var errorDescription: String? {
        switch self {
        case .destinationExists(let path):
            return "A backup already exists at \(path)."
        case .invalidBackup(let reason):
            return "The backup is invalid: \(reason)"
        case .unsupportedSchema(let version):
            return "Backup schema version \(version) is not supported."
        case .incompatibleApplication(let identifier):
            return "The backup belongs to a different application (\(identifier))."
        case .fileOperation(let reason):
            return "Backup file operation failed: \(reason)"
        case .sqliteSnapshot(let reason):
            return "Could not create a consistent SQLite snapshot: \(reason)"
        case .sqliteIntegrity(let path):
            return "SQLite integrity validation failed for \(path)."
        case .preferences(let reason):
            return "Preferences validation failed: \(reason)"
        case .rollbackFailed(let reason):
            return "Restore failed and rollback could not fully recover: \(reason)"
        }
    }
}

/// Creates and restores the complete, non-rebuildable Leaf Reader user-data set.
///
/// A backup is a directory package containing `manifest.json` and `payload/`.
/// The payload includes the three user databases, the full preferences domain
/// (sessions, conversations, settings, and encrypted credentials), and reading-
/// note assets. Caches and downloaded resources are intentionally excluded.
///
/// Database snapshots use SQLite's online-backup API, so a live WAL database is
/// captured consistently without copying transient sidecars. Restore validates
/// hashes, the allow-listed layout, the preferences plist, and SQLite integrity
/// before making same-volume staged replacements. Every applied replacement is
/// rolled back in reverse order if a later step fails.
///
/// Production restore must run before the shared store singletons are opened,
/// then terminate/relaunch the app. Existing SQLite handles keep their old file
/// descriptors even after an atomic path replacement.
package final class UserDataBackupService {
    private static let schemaVersion = 1
    private static let manifestName = "manifest.json"
    private static let payloadName = "payload"
    private static let preferencesName = "preferences.plist"
    private static let readingNoteAssetsName = "ReadingNoteAssets"
    private static let restoreJournalName = "restore-journal.json"
    private static let rollbackPreferencesName = "previous-preferences.plist"
    private static let databaseNames = [
        "word-records.sqlite3",
        "personal-vocabulary.sqlite3",
        "reading-notes.sqlite"
    ]

    private let configuration: UserDataBackupConfiguration
    private let fileManager: FileManager
    private let restoreCheckpoint: (@Sendable (Int) throws -> Void)?

    /// A restore never deletes its transaction directory until this journal has
    /// reached a terminal state.  The file is rewritten atomically before each
    /// filesystem transition, making an interrupted restore recoverable on the
    /// next cold start.
    private struct RestoreJournal: Codable {
        enum TransactionPhase: String, Codable {
            case applying
            case committed
        }

        enum UnitPhase: String, Codable {
            case pending
            case movingOriginal
            case originalMoved
            case installingStaged
            case installed
        }

        struct Unit: Codable {
            let name: String
            let hadOriginal: Bool
            var phase: UnitPhase
        }

        var phase: TransactionPhase
        var units: [Unit]
        var preferencesApplyStarted: Bool
        var preferencesApplied: Bool
    }

    package init(
        configuration: UserDataBackupConfiguration,
        fileManager: FileManager = .default,
        restoreCheckpoint: (@Sendable (Int) throws -> Void)? = nil
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
        self.restoreCheckpoint = restoreCheckpoint
    }

    /// Must be called before the app opens shared stores.  An unrecoverable
    /// journal is deliberately surfaced rather than guessing which version of
    /// a user's files is authoritative.
    package func recoverInterruptedRestoreIfNeeded() throws {
        let parent = configuration.applicationSupportDirectory.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: parent.path) else { return }
        let prefix = ".\(AppIdentity.applicationSupportDirectoryName)-restore-"
        let candidates: [URL]
        do {
            candidates = try fileManager.contentsOfDirectory(
                at: parent,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ).filter { $0.lastPathComponent.hasPrefix(prefix) }
        } catch {
            throw UserDataBackupError.fileOperation("could not inspect restore recovery state: \(error.localizedDescription)")
        }
        for transactionURL in candidates.sorted(by: { $0.path < $1.path }) {
            let journalURL = transactionURL.appendingPathComponent(Self.restoreJournalName)
            guard fileManager.fileExists(atPath: journalURL.path) else {
                throw UserDataBackupError.rollbackFailed("restore transaction without journal at \(transactionURL.path)")
            }
            var journal = try readRestoreJournal(at: journalURL)
            if journal.phase == .committed {
                try fileManager.removeItem(at: transactionURL)
                continue
            }
            try rollbackRestoreTransaction(at: transactionURL, journal: &journal)
            try fileManager.removeItem(at: transactionURL)
        }
    }

    @discardableResult
    package func createBackup(at backupURL: URL) throws -> UserDataBackupManifest {
        let backupURL = backupURL.standardizedFileURL
        guard !fileManager.fileExists(atPath: backupURL.path) else {
            throw UserDataBackupError.destinationExists(backupURL.path)
        }
        try fileManager.createDirectory(
            at: backupURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let temporaryURL = backupURL.deletingLastPathComponent()
            .appendingPathComponent(".\(backupURL.lastPathComponent)-creating-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryURL) }

        let payloadURL = temporaryURL.appendingPathComponent(Self.payloadName, isDirectory: true)
        try fileManager.createDirectory(at: payloadURL, withIntermediateDirectories: true)

        var entries: [UserDataBackupManifest.Entry] = []
        let preferencesURL = payloadURL.appendingPathComponent(Self.preferencesName)
        let domain = configuration.defaults.persistentDomain(
            forName: configuration.preferencesDomainName
        ) ?? [:]
        let preferencesData: Data
        do {
            preferencesData = try PropertyListSerialization.data(
                fromPropertyList: domain,
                format: .binary,
                options: 0
            )
            try preferencesData.write(to: preferencesURL, options: .atomic)
        } catch {
            throw UserDataBackupError.preferences(error.localizedDescription)
        }
        entries.append(try entry(
            for: preferencesURL,
            relativePath: Self.preferencesName,
            kind: .preferences
        ))

        for name in Self.databaseNames {
            let source = configuration.applicationSupportDirectory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = payloadURL.appendingPathComponent(name)
            try snapshotSQLiteDatabase(from: source, to: destination)
            entries.append(try entry(for: destination, relativePath: name, kind: .database))
        }

        let sourceAssets = configuration.applicationSupportDirectory
            .appendingPathComponent(Self.readingNoteAssetsName, isDirectory: true)
        var sourceAssetsIsDirectory: ObjCBool = false
        let includesAssets = fileManager.fileExists(
            atPath: sourceAssets.path,
            isDirectory: &sourceAssetsIsDirectory
        ) && sourceAssetsIsDirectory.boolValue
        if includesAssets {
            let destinationAssets = payloadURL
                .appendingPathComponent(Self.readingNoteAssetsName, isDirectory: true)
            try fileManager.createDirectory(at: destinationAssets, withIntermediateDirectories: true)
            for source in try regularFilesRecursively(in: sourceAssets) {
                let suffix = relativePath(of: source, under: sourceAssets)
                let relative = Self.readingNoteAssetsName + "/" + suffix
                let destination = payloadURL.appendingPathComponent(relative)
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: source, to: destination)
                entries.append(try entry(
                    for: destination,
                    relativePath: relative,
                    kind: .readingNoteAsset
                ))
            }
        }

        entries.sort { $0.relativePath < $1.relativePath }
        let manifest = UserDataBackupManifest(
            schemaVersion: Self.schemaVersion,
            createdAt: Date(),
            applicationBundleIdentifier: AppIdentity.bundleIdentifier,
            preferencesDomainName: configuration.preferencesDomainName,
            includesReadingNoteAssetsDirectory: includesAssets,
            entries: entries
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var manifestData = try encoder.encode(manifest)
        manifestData.append(0x0A)
        try manifestData.write(
            to: temporaryURL.appendingPathComponent(Self.manifestName),
            options: .atomic
        )

        try fileManager.moveItem(at: temporaryURL, to: backupURL)
        return manifest
    }

    package func validateBackup(at backupURL: URL) throws -> UserDataBackupManifest {
        let backupURL = backupURL.standardizedFileURL
        let manifestURL = backupURL.appendingPathComponent(Self.manifestName)
        let payloadURL = backupURL.appendingPathComponent(Self.payloadName, isDirectory: true)
        let manifest: UserDataBackupManifest
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            manifest = try decoder.decode(
                UserDataBackupManifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw UserDataBackupError.invalidBackup("manifest.json could not be decoded")
        }

        guard manifest.schemaVersion == Self.schemaVersion else {
            throw UserDataBackupError.unsupportedSchema(manifest.schemaVersion)
        }
        guard manifest.applicationBundleIdentifier == AppIdentity.bundleIdentifier else {
            throw UserDataBackupError.incompatibleApplication(manifest.applicationBundleIdentifier)
        }
        guard manifest.preferencesDomainName == configuration.preferencesDomainName else {
            throw UserDataBackupError.invalidBackup("the preferences domain does not match this profile")
        }

        let assetsURL = payloadURL.appendingPathComponent(
            Self.readingNoteAssetsName,
            isDirectory: true
        )
        var assetsIsDirectory: ObjCBool = false
        let hasAssetsDirectory = fileManager.fileExists(
            atPath: assetsURL.path,
            isDirectory: &assetsIsDirectory
        ) && assetsIsDirectory.boolValue
        guard hasAssetsDirectory == manifest.includesReadingNoteAssetsDirectory else {
            throw UserDataBackupError.invalidBackup(
                "the reading-note assets directory does not match the manifest"
            )
        }

        var paths = Set<String>()
        var preferenceCount = 0
        for entry in manifest.entries {
            guard paths.insert(entry.relativePath).inserted else {
                throw UserDataBackupError.invalidBackup("duplicate entry \(entry.relativePath)")
            }
            try validateAllowed(entry)
            let url = try validatedPayloadURL(for: entry.relativePath, payloadRoot: payloadURL)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                throw UserDataBackupError.invalidBackup("missing payload file \(entry.relativePath)")
            }
            let size = try fileSize(url)
            guard size == entry.byteCount else {
                throw UserDataBackupError.invalidBackup("size mismatch for \(entry.relativePath)")
            }
            guard try sha256(url) == entry.sha256 else {
                throw UserDataBackupError.invalidBackup("checksum mismatch for \(entry.relativePath)")
            }
            switch entry.kind {
            case .database:
                try validateSQLiteIntegrity(url)
            case .preferences:
                preferenceCount += 1
                _ = try preferencesDictionary(at: url)
            case .readingNoteAsset:
                guard manifest.includesReadingNoteAssetsDirectory else {
                    throw UserDataBackupError.invalidBackup(
                        "reading-note assets are listed without their managed directory"
                    )
                }
                break
            }
        }
        guard preferenceCount == 1 else {
            throw UserDataBackupError.invalidBackup("exactly one preferences payload is required")
        }

        let actualFiles = Set(try regularFilesRecursively(in: payloadURL).map {
            relativePath(of: $0, under: payloadURL)
        })
        guard actualFiles == paths else {
            throw UserDataBackupError.invalidBackup("payload contains unlisted or missing files")
        }
        return manifest
    }

    @discardableResult
    package func restoreBackup(at backupURL: URL) throws -> UserDataRestoreResult {
        let backupURL = backupURL.standardizedFileURL
        let manifest = try validateBackup(at: backupURL)
        let payloadURL = backupURL.appendingPathComponent(Self.payloadName, isDirectory: true)
        let preferencesEntry = manifest.entries.first { $0.kind == .preferences }!
        let restoredPreferences = try preferencesDictionary(
            at: try validatedPayloadURL(for: preferencesEntry.relativePath, payloadRoot: payloadURL)
        )
        try fileManager.createDirectory(
            at: configuration.applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        let transactionURL = configuration.applicationSupportDirectory.deletingLastPathComponent()
            .appendingPathComponent(".\(AppIdentity.applicationSupportDirectoryName)-restore-\(UUID().uuidString)", isDirectory: true)
        let stageURL = transactionURL.appendingPathComponent("stage", isDirectory: true)
        let rollbackURL = transactionURL.appendingPathComponent("rollback", isDirectory: true)
        try fileManager.createDirectory(at: stageURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: rollbackURL, withIntermediateDirectories: true)

        let units = Self.databaseNames + [Self.readingNoteAssetsName]
        var journal = RestoreJournal(
            phase: .applying,
            units: units.map { name in
                RestoreJournal.Unit(
                    name: name,
                    hadOriginal: fileManager.fileExists(
                        atPath: configuration.applicationSupportDirectory.appendingPathComponent(name).path
                    ),
                    phase: .pending
                )
            },
            preferencesApplyStarted: false,
            preferencesApplied: false
        )
        try writeRestoreJournal(journal, at: transactionURL)
        let previousPreferences = configuration.defaults.persistentDomain(
            forName: configuration.preferencesDomainName
        ) ?? [:]
        do {
            let previousPreferencesData = try PropertyListSerialization.data(
                fromPropertyList: previousPreferences,
                format: .binary,
                options: 0
            )
            try previousPreferencesData.write(
                to: rollbackURL.appendingPathComponent(Self.rollbackPreferencesName),
                options: .atomic
            )
        } catch {
            throw UserDataBackupError.preferences("could not journal previous preferences: \(error.localizedDescription)")
        }

        let databaseEntries = Dictionary(uniqueKeysWithValues: manifest.entries
            .filter { $0.kind == .database }
            .map { ($0.relativePath, $0) })
        for name in Self.databaseNames {
            guard let entry = databaseEntries[name] else { continue }
            let source = try validatedPayloadURL(for: entry.relativePath, payloadRoot: payloadURL)
            try fileManager.copyItem(at: source, to: stageURL.appendingPathComponent(name))
        }
        if manifest.includesReadingNoteAssetsDirectory {
            let stagedAssets = stageURL.appendingPathComponent(Self.readingNoteAssetsName, isDirectory: true)
            try fileManager.createDirectory(at: stagedAssets, withIntermediateDirectories: true)
            for entry in manifest.entries where entry.kind == .readingNoteAsset {
                let source = try validatedPayloadURL(for: entry.relativePath, payloadRoot: payloadURL)
                let destination = stageURL.appendingPathComponent(entry.relativePath)
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: source, to: destination)
            }
        }

        do {
            for index in journal.units.indices {
                let name = journal.units[index].name
                let destination = configuration.applicationSupportDirectory.appendingPathComponent(name)
                let staged = stageURL.appendingPathComponent(name)
                let rollback = rollbackURL.appendingPathComponent(name)
                let hasStaged = fileManager.fileExists(atPath: staged.path)
                let hasDestination = fileManager.fileExists(atPath: destination.path)
                guard hasStaged || hasDestination else { continue }

                if hasDestination {
                    journal.units[index].phase = .movingOriginal
                    try writeRestoreJournal(journal, at: transactionURL)
                    try fileManager.moveItem(at: destination, to: rollback)
                    journal.units[index].phase = .originalMoved
                    try writeRestoreJournal(journal, at: transactionURL)
                }
                if hasStaged {
                    journal.units[index].phase = .installingStaged
                    try writeRestoreJournal(journal, at: transactionURL)
                    try fileManager.moveItem(at: staged, to: destination)
                    journal.units[index].phase = .installed
                    try writeRestoreJournal(journal, at: transactionURL)
                }
                try restoreCheckpoint?(index + 1)
            }

            journal.preferencesApplyStarted = true
            try writeRestoreJournal(journal, at: transactionURL)
            configuration.defaults.setPersistentDomain(
                restoredPreferences,
                forName: configuration.preferencesDomainName
            )
            guard configuration.defaults.synchronize() else {
                throw UserDataBackupError.preferences("the restored domain could not be synchronized")
            }
            journal.preferencesApplied = true
            journal.phase = .committed
            try writeRestoreJournal(journal, at: transactionURL)
        } catch {
            do {
                try rollbackRestoreTransaction(at: transactionURL, journal: &journal)
                try fileManager.removeItem(at: transactionURL)
            } catch {
                // The journal is intentionally retained for cold-start recovery.
                throw UserDataBackupError.rollbackFailed(error.localizedDescription)
            }
            throw error
        }

        // A committed journal has been durably recorded.  It is now safe to
        // remove the transaction; if that cleanup is interrupted, cold-start
        // recovery only removes the committed transaction and never rolls back.
        try fileManager.removeItem(at: transactionURL)

        return UserDataRestoreResult(
            restoredEntryCount: manifest.entries.count,
            requiresRelaunch: true
        )
    }

    private func writeRestoreJournal(_ journal: RestoreJournal, at transactionURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            try encoder.encode(journal).write(
                to: transactionURL.appendingPathComponent(Self.restoreJournalName),
                options: .atomic
            )
        } catch {
            throw UserDataBackupError.fileOperation("could not write restore journal: \(error.localizedDescription)")
        }
    }

    private func readRestoreJournal(at url: URL) throws -> RestoreJournal {
        do {
            return try JSONDecoder().decode(RestoreJournal.self, from: Data(contentsOf: url))
        } catch {
            throw UserDataBackupError.rollbackFailed("restore journal is unreadable at \(url.path)")
        }
    }

    /// Restores the pre-transaction filesystem and preferences state using the
    /// durable journal.  It is intentionally conservative: if an original is
    /// expected but neither the destination nor rollback copy can prove its
    /// whereabouts, recovery fails and keeps the transaction for inspection.
    private func rollbackRestoreTransaction(
        at transactionURL: URL,
        journal: inout RestoreJournal
    ) throws {
        let rollbackURL = transactionURL.appendingPathComponent("rollback", isDirectory: true)
        var failures: [String] = []

        if journal.preferencesApplyStarted {
            do {
                let preferencesURL = rollbackURL.appendingPathComponent(Self.rollbackPreferencesName)
                let priorPreferences = try preferencesDictionary(at: preferencesURL)
                configuration.defaults.setPersistentDomain(
                    priorPreferences,
                    forName: configuration.preferencesDomainName
                )
                guard configuration.defaults.synchronize() else {
                    throw UserDataBackupError.preferences("could not synchronize restored previous preferences")
                }
                journal.preferencesApplied = false
            } catch {
                failures.append("preferences")
            }
        }

        for unit in journal.units.reversed() {
            let destination = configuration.applicationSupportDirectory.appendingPathComponent(unit.name)
            let rollback = rollbackURL.appendingPathComponent(unit.name)
            let hasRollback = fileManager.fileExists(atPath: rollback.path)
            let hasDestination = fileManager.fileExists(atPath: destination.path)
            do {
                if hasRollback {
                    if hasDestination {
                        try fileManager.removeItem(at: destination)
                    }
                    try fileManager.moveItem(at: rollback, to: destination)
                    continue
                }

                // A new unit may have been installed before interruption. It
                // has no original rollback copy, so remove only after the
                // journal proves we had entered its install transition.
                if !unit.hadOriginal,
                   unit.phase == .installingStaged || unit.phase == .installed,
                   hasDestination {
                    try fileManager.removeItem(at: destination)
                    continue
                }

                if unit.hadOriginal,
                   unit.phase != .pending,
                   !hasDestination {
                    throw UserDataBackupError.rollbackFailed("missing original \(unit.name)")
                }
            } catch {
                failures.append(unit.name)
            }
        }

        guard failures.isEmpty else {
            throw UserDataBackupError.rollbackFailed(failures.joined(separator: ", "))
        }
    }

    private func validateAllowed(_ entry: UserDataBackupManifest.Entry) throws {
        switch entry.kind {
        case .preferences:
            guard entry.relativePath == Self.preferencesName else {
                throw UserDataBackupError.invalidBackup("preferences path is not allowed")
            }
        case .database:
            guard Self.databaseNames.contains(entry.relativePath) else {
                throw UserDataBackupError.invalidBackup("database path is not allowed")
            }
        case .readingNoteAsset:
            guard entry.relativePath.hasPrefix(Self.readingNoteAssetsName + "/") else {
                throw UserDataBackupError.invalidBackup("reading-note asset path is not allowed")
            }
        }
    }

    private func validatedPayloadURL(for relativePath: String, payloadRoot: URL) throws -> URL {
        guard !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/", omittingEmptySubsequences: false).contains(".."),
              !relativePath.split(separator: "/", omittingEmptySubsequences: false).contains("") else {
            throw UserDataBackupError.invalidBackup("unsafe payload path \(relativePath)")
        }
        let url = payloadRoot.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = payloadRoot.standardizedFileURL.path
        guard url.path.hasPrefix(rootPath + "/") else {
            throw UserDataBackupError.invalidBackup("payload path escapes the backup")
        }
        return url
    }

    private func entry(
        for url: URL,
        relativePath: String,
        kind: UserDataBackupManifest.Entry.Kind
    ) throws -> UserDataBackupManifest.Entry {
        UserDataBackupManifest.Entry(
            relativePath: relativePath,
            kind: kind,
            byteCount: try fileSize(url),
            sha256: try sha256(url)
        )
    }

    private func regularFilesRecursively(in directory: URL) throws -> [URL] {
        let rootValues = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else {
            throw UserDataBackupError.fileOperation("managed directory is not a real directory: \(directory.path)")
        }
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: [],
            errorHandler: { url, error in
                enumerationError = UserDataBackupError.fileOperation(
                    "could not enumerate \(url.path): \(error.localizedDescription)"
                )
                return false
            }
        ) else {
            throw UserDataBackupError.fileOperation("could not enumerate \(directory.path)")
        }
        var files: [URL] = []
        for case let url as URL in enumerator {
            if let enumerationError { throw enumerationError }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                throw UserDataBackupError.fileOperation("symbolic links are not allowed: \(url.path)")
            }
            if values.isRegularFile == true { files.append(url) }
            else if values.isDirectory == true { continue }
            else {
                throw UserDataBackupError.fileOperation("unsupported filesystem entry: \(url.path)")
            }
        }
        if let enumerationError { throw enumerationError }
        return files.sorted { $0.path < $1.path }
    }

    private func relativePath(of url: URL, under root: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
    }

    private func fileSize(_ url: URL) throws -> Int64 {
        guard let number = try fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber else {
            throw UserDataBackupError.fileOperation("could not read the size of \(url.path)")
        }
        return number.int64Value
    }

    private func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            guard !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func snapshotSQLiteDatabase(from sourceURL: URL, to destinationURL: URL) throws {
        var source: OpaquePointer?
        var destination: OpaquePointer?
        guard sqlite3_open_v2(sourceURL.path, &source, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(source)
            throw UserDataBackupError.sqliteSnapshot(sourceURL.lastPathComponent)
        }
        defer { sqlite3_close(source) }
        guard sqlite3_open(destinationURL.path, &destination) == SQLITE_OK else {
            sqlite3_close(destination)
            throw UserDataBackupError.sqliteSnapshot(destinationURL.lastPathComponent)
        }
        defer { sqlite3_close(destination) }
        guard let backup = sqlite3_backup_init(destination, "main", source, "main") else {
            throw UserDataBackupError.sqliteSnapshot(sourceURL.lastPathComponent)
        }
        var result: Int32 = SQLITE_OK
        var retries = 0
        repeat {
            result = sqlite3_backup_step(backup, -1)
            if result == SQLITE_BUSY || result == SQLITE_LOCKED {
                retries += 1
                sqlite3_sleep(10)
            }
        } while (result == SQLITE_BUSY || result == SQLITE_LOCKED) && retries < 100
        let finish = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finish == SQLITE_OK else {
            throw UserDataBackupError.sqliteSnapshot(sourceURL.lastPathComponent)
        }
    }

    private func validateSQLiteIntegrity(_ url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw UserDataBackupError.sqliteIntegrity(url.lastPathComponent)
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA integrity_check", -1, &statement, nil) == SQLITE_OK else {
            throw UserDataBackupError.sqliteIntegrity(url.lastPathComponent)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0),
              String(cString: value) == "ok" else {
            throw UserDataBackupError.sqliteIntegrity(url.lastPathComponent)
        }
    }

    private func preferencesDictionary(at url: URL) throws -> [String: Any] {
        do {
            let object = try PropertyListSerialization.propertyList(
                from: Data(contentsOf: url),
                options: [],
                format: nil
            )
            guard let dictionary = object as? [String: Any] else {
                throw UserDataBackupError.preferences("the root plist object is not a dictionary")
            }
            return dictionary
        } catch let error as UserDataBackupError {
            throw error
        } catch {
            throw UserDataBackupError.preferences(error.localizedDescription)
        }
    }
}
