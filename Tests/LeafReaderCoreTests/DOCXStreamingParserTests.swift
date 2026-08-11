import Foundation
import XCTest
@testable import LeafReaderCore

final class DOCXStreamingParserTests: XCTestCase {
    func testStreamsBodyTextFormattingTablesMediaAndTOCInDocumentOrder() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let documentURL = directory.appendingPathComponent("document.xml")
        let relationshipsURL = directory.appendingPathComponent("relationships.xml")
        try Data("""
        <w:document
          xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
          xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
          <w:body>
            <w:p><w:pPr><w:pStyle w:val="Heading1"/><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:i/><w:u/></w:rPr><w:t>Über &amp; bereit</w:t></w:r><w:hyperlink r:id="link"><w:r><w:t> Link</w:t></w:r></w:hyperlink></w:p>
            <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Inside table</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
            <w:p><w:pPr><w:numPr/></w:pPr><w:r><w:t>- Item</w:t></w:r></w:p>
            <w:p><w:r><w:drawing><a:blip r:embed="image"/></w:drawing></w:r></w:p>
          </w:body>
        </w:document>
        """.utf8).write(to: documentURL)
        try Data("""
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="link" Target="https://example.com/?a=1&amp;b=2"/>
          <Relationship Id="image" Target="media/image 1.png"/>
        </Relationships>
        """.utf8).write(to: relationshipsURL)

        let relationships = try WebDocumentLoader.docxStreamingRelationships(from: relationshipsURL)
        let result = try WebDocumentLoader.docxStreamingContent(
            from: documentURL,
            directory: directory,
            relationships: relationships
        )

        XCTAssertEqual(result.plainText, ["Über & bereit Link", "Inside table", "- Item"])
        XCTAssertTrue(result.html.contains("<h1 id=\"docx-heading-1\" class=\"docx-align-center\">"))
        XCTAssertTrue(result.html.contains("<u><em><strong>Über &amp; bereit</strong></em></u>"))
        XCTAssertTrue(result.html.contains("<a href=\"https://example.com/?a=1&amp;b=2\"> Link</a>"))
        XCTAssertTrue(result.html.contains("<td>\n<p>Inside table</p>\n</td>"))
        XCTAssertTrue(result.html.contains("<ul>\n<li>Item</li>\n</ul>"))
        XCTAssertTrue(result.html.contains("word/media/image%201.png"))
        XCTAssertEqual(result.tocItems.count, 1)
        XCTAssertEqual(result.tocItems[0].title, "Über & bereit Link")
        XCTAssertEqual(result.tocItems[0].href, "#docx-heading-1")
        XCTAssertEqual(result.tocItems[0].level, 0)
    }

    func testMalformedDocumentFailsInsteadOfReturningPartialHTML() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let documentURL = directory.appendingPathComponent("document.xml")
        try Data("<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:p>".utf8)
            .write(to: documentURL)

        XCTAssertThrowsError(
            try WebDocumentLoader.docxStreamingContent(
                from: documentURL,
                directory: directory,
                relationships: [:]
            )
        )
    }

    func testPrivateFixtureLoadsWhenProvided() throws {
        guard let path = ProcessInfo.processInfo.environment["LEAFREADER_DOCX_FIXTURE"],
              !path.isEmpty else {
            throw XCTSkip("Set LEAFREADER_DOCX_FIXTURE to exercise a private real-world document")
        }
        let url = URL(fileURLWithPath: path)
        let directory = try WebDocumentLoader.unzip(url: url)
        defer { try? FileManager.default.removeItem(at: directory) }
        let documentURL = directory.appendingPathComponent("word/document.xml")
        let relationshipsURL = directory.appendingPathComponent("word/_rels/document.xml.rels")
        let xml = try String(contentsOf: documentURL, encoding: .utf8)
        let legacyRelationships = WebDocumentLoader.docxRelationships(from: relationshipsURL)
        let streamingRelationships = try WebDocumentLoader.docxStreamingRelationships(from: relationshipsURL)
        let legacy = WebDocumentLoader.docxBodyContent(
            from: xml,
            directory: directory,
            relationships: legacyRelationships
        )
        let streaming = try WebDocumentLoader.docxStreamingContent(
            from: documentURL,
            directory: directory,
            relationships: streamingRelationships
        )
        XCTAssertEqual(streaming.plainText, legacy.plainText)
        XCTAssertEqual(canonicalHTML(streaming.html), canonicalHTML(legacy.html))
        let legacyTOC = WebDocumentLoader.docxTOCItems(from: legacy.html)
        XCTAssertEqual(streaming.tocItems.map(\.title), legacyTOC.map(\.title))
        XCTAssertEqual(streaming.tocItems.map(\.href), legacyTOC.map(\.href))
        XCTAssertEqual(streaming.tocItems.map(\.level), legacyTOC.map(\.level))

        let document = try WebDocumentLoader.loadDOCX(url: url)
        XCTAssertFalse(document.html.isEmpty)
        XCTAssertFalse(document.plainText.isEmpty)
        print(
            "DOCX_PRIVATE_FIXTURE html_utf8=\(document.html.utf8.count) " +
            "plain_characters=\(document.plainText.count) toc=\(document.tocItems.count)"
        )
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeafReader-DOCXStreamingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func canonicalHTML(_ html: String) -> String {
        var output = html.replacingOccurrences(of: "&emsp;", with: "")
        for _ in 0..<3 {
            output = output.replacingOccurrences(
                of: #"<(strong|em|u)>\s*</\1>"#,
                with: "",
                options: .regularExpression
            )
        }
        return output.replacingOccurrences(of: #">\s+<"#, with: "><", options: .regularExpression)
    }
}
