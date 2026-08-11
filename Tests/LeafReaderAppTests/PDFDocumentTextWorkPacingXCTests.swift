import XCTest
@testable import LeafReaderApp

final class PDFDocumentTextWorkPacingXCTests: XCTestCase {
    func testDeferredBackgroundWorkYieldsAndThenResumes() {
        let token = PDFDocumentTextCancellationToken()
        token.deferWork(for: 0.03)
        let startedAt = ProcessInfo.processInfo.systemUptime

        XCTAssertFalse(token.waitUntilRunnableOrCancelled())
        XCTAssertGreaterThanOrEqual(
            ProcessInfo.processInfo.systemUptime - startedAt,
            0.02
        )
    }

    func testCancellationWinsOverDeferral() {
        let token = PDFDocumentTextCancellationToken()
        token.deferWork(for: 1)
        token.cancel()
        let startedAt = ProcessInfo.processInfo.systemUptime

        XCTAssertTrue(token.waitUntilRunnableOrCancelled())
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - startedAt, 0.05)
    }
}
