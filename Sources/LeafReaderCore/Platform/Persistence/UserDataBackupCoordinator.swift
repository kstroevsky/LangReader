import Foundation

/// The only production-facing entry point for backup work.  A consistent
/// package cannot be assembled after SQLite and preferences stores are live;
/// callers must use this coordinator before persistence activation.
@MainActor
package final class UserDataBackupCoordinator {
    private let service: UserDataBackupService
    private var persistenceIsActive = false

    package init(configuration: UserDataBackupConfiguration) {
        service = UserDataBackupService(configuration: configuration)
    }

    package func recoverBeforePersistenceActivation() throws {
        guard !persistenceIsActive else {
            throw UserDataBackupError.fileOperation("restore recovery was requested after persistence became active")
        }
        try service.recoverInterruptedRestoreIfNeeded()
    }

    @discardableResult
    package func createColdStartBackup(at url: URL) throws -> UserDataBackupManifest {
        guard !persistenceIsActive else {
            throw UserDataBackupError.fileOperation("backup capture requires a cold, quiescent persistence state")
        }
        return try service.createBackup(at: url)
    }

    @discardableResult
    package func restoreColdStartBackup(at url: URL) throws -> UserDataRestoreResult {
        guard !persistenceIsActive else {
            throw UserDataBackupError.fileOperation("backup restore requires a cold, quiescent persistence state")
        }
        return try service.restoreBackup(at: url)
    }

    package func markPersistenceActive() {
        persistenceIsActive = true
    }
}
