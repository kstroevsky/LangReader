import XCTest

final class UserDataBackupServiceXCTests: XCTestCase {
    func testRoundTripRestoresDatabasesPreferencesAndAssets() throws {
        try UserDataBackupServiceTests.testRoundTripRestoresDatabasesPreferencesAndAssets()
    }

    func testTamperedPayloadIsRejectedBeforeMutation() throws {
        try UserDataBackupServiceTests.testTamperedPayloadIsRejectedBeforeMutation()
    }

    func testFailedRestoreRollsBackEveryReplacement() throws {
        try UserDataBackupServiceTests.testFailedRestoreRollsBackEveryReplacement()
    }

    func testMissingDeclaredEmptyAssetsDirectoryIsRejected() throws {
        try UserDataBackupServiceTests.testMissingDeclaredEmptyAssetsDirectoryIsRejected()
    }
}
