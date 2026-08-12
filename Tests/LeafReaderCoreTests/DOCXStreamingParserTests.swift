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

    func testAccumulatesEntitiesUnicodeTabsBreaksAndSplitCharacterCallbacks() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let documentURL = directory.appendingPathComponent("document.xml")
        try Data("""
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body><w:p><w:r><w:t xml:space="preserve">Grüße &amp; </w:t><w:tab/><w:t>€</w:t><w:br/><w:t>漢字 😀</w:t></w:r></w:p></w:body>
        </w:document>
        """.utf8).write(to: documentURL)

        let result = try WebDocumentLoader.docxStreamingContent(
            from: documentURL,
            directory: directory,
            relationships: [:]
        )

        XCTAssertEqual(result.plainText, ["Grüße & €漢字 😀"])
        XCTAssertTrue(result.html.contains("Grüße &amp; &emsp;€<br>漢字 😀"))
    }

    func testGroupsListsMapsHeadingLevelsAndAlignmentsAndDropsMissingRelationships() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let documentURL = directory.appendingPathComponent("document.xml")
        try Data("""
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
          xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
          xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><w:body>
          <w:p><w:pPr><w:pStyle w:val="Title"/></w:pPr><w:r><w:t>Title</w:t></w:r></w:p>
          <w:p><w:pPr><w:pStyle w:val="Heading2"/><w:jc w:val="right"/></w:pPr><w:r><w:t>Second</w:t></w:r></w:p>
          <w:p><w:pPr><w:pStyle w:val="Heading3"/><w:jc w:val="both"/></w:pPr><w:r><w:t>Third</w:t></w:r></w:p>
          <w:p><w:pPr><w:pStyle w:val="ListParagraph"/></w:pPr><w:r><w:t>• One</w:t></w:r></w:p>
          <w:p><w:pPr><w:numPr/></w:pPr><w:r><w:t>Two</w:t></w:r></w:p>
          <w:p><w:hyperlink r:id="missing"><w:r><w:t>Plain link</w:t></w:r></w:hyperlink></w:p>
          <w:p><w:r><w:drawing><a:blip r:embed="missing-image"/></w:drawing></w:r></w:p>
        </w:body></w:document>
        """.utf8).write(to: documentURL)

        let result = try WebDocumentLoader.docxStreamingContent(
            from: documentURL,
            directory: directory,
            relationships: [:]
        )

        XCTAssertEqual(result.plainText, ["Title", "Second", "Third", "• One", "Two", "Plain link"])
        XCTAssertEqual(result.tocItems.map(\.title), ["Title", "Second", "Third"])
        XCTAssertEqual(result.tocItems.map(\.level), [0, 1, 2])
        XCTAssertTrue(result.html.contains("<h2 id=\"docx-heading-2\" class=\"docx-align-right\">Second</h2>"))
        XCTAssertTrue(result.html.contains("<h3 id=\"docx-heading-3\" class=\"docx-align-justify\">Third</h3>"))
        XCTAssertTrue(result.html.contains("<ul>\n<li>One</li>\n<li>Two</li>\n</ul>"))
        XCTAssertTrue(result.html.contains("<p>Plain link</p>"))
        XCTAssertFalse(result.html.contains("<a href="))
        XCTAssertFalse(result.html.contains("<img"))
    }

    func testExternalEntitiesAreNeverResolved() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let secretURL = directory.appendingPathComponent("secret.txt")
        let documentURL = directory.appendingPathComponent("document.xml")
        try Data("DO NOT LOAD".utf8).write(to: secretURL)
        try Data("""
        <!DOCTYPE w:document [<!ENTITY external SYSTEM "\(secretURL.absoluteString)">]>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body><w:p><w:r><w:t>&external;</w:t></w:r></w:p></w:body>
        </w:document>
        """.utf8).write(to: documentURL)

        do {
            let result = try WebDocumentLoader.docxStreamingContent(
                from: documentURL,
                directory: directory,
                relationships: [:]
            )
            XCTAssertFalse(result.plainText.joined().contains("DO NOT LOAD"))
            XCTAssertFalse(result.html.contains("DO NOT LOAD"))
        } catch {
            XCTAssertFalse(error.localizedDescription.contains("DO NOT LOAD"))
        }
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

        let cacheRoot = directory.appendingPathComponent("prepared-cache", isDirectory: true)
        let document = try WebDocumentLoader.loadPreparedDOCX(url: url, cacheRootURL: cacheRoot)
        XCTAssertNotNil(document.htmlFileURL)
        XCTAssertTrue(document.html.isEmpty)
        XCTAssertFalse(document.plainText.isEmpty)
        let renderedHTML = try String(contentsOf: try XCTUnwrap(document.htmlFileURL), encoding: .utf8)
        print(
            "DOCX_PRIVATE_FIXTURE html_utf8=\(renderedHTML.utf8.count) " +
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
