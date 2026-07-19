import Foundation

enum DocumentImportDecisionLogicTests {
    static func testSingleSupportedDropOpensDirectly() throws {
        let document = URL(fileURLWithPath: "/books/one.pdf")
        try expectEqual(
            DocumentImportDecision.make(urls: [document, URL(fileURLWithPath: "/books/skip.txt")]),
            .open(document),
            "one supported dropped document should open directly"
        )
    }

    static func testMultipleDropsPresentTheShelf() throws {
        let first = URL(fileURLWithPath: "/books/one.pdf")
        let second = URL(fileURLWithPath: "/books/two.epub")
        try expectEqual(
            DocumentImportDecision.make(urls: [first, second, first]),
            .showShelf([first, second]),
            "multiple dropped documents should deduplicate and present the shelf"
        )
        try expectEqual(
            DocumentImportDecision.make(urls: [first, first]),
            .showShelf([first]),
            "a multiple-file drop should still present the shelf after deduplication"
        )
        try expectEqual(
            DocumentImportDecision.make(urls: [URL(fileURLWithPath: "/books/skip.txt")]),
            .ignore,
            "unsupported drops should be ignored"
        )
    }
}
