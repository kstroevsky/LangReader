import Foundation
import LeafReaderCore

enum DOCXLogicTests {
    static func testTopLevelBlocksPreserveDocumentOrder() throws {
        let result = try renderDocument("""
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:r><w:t>Before</w:t></w:r></w:p>
            <w:tbl>
              <w:tr><w:tc><w:p><w:r><w:t>Inside table</w:t></w:r></w:p></w:tc></w:tr>
            </w:tbl>
            <w:p><w:r><w:t>After</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """)

        let before = try requiredOffset(of: "<p>Before</p>", in: result.html)
        let table = try requiredOffset(of: "<table>", in: result.html)
        let cell = try requiredOffset(of: "<td>\n<p>Inside table</p>\n</td>", in: result.html)
        let after = try requiredOffset(of: "<p>After</p>", in: result.html)
        try expect(before < table && table < cell && cell < after, "DOCX streaming should preserve top-level and table order")
        try expectEqual(result.plainText, ["Before", "Inside table", "After"], "DOCX text should follow document order")
    }

    static func testStreamingRendererPreservesFormattingAndTOC() throws {
        let result = try renderDocument(
            """
            <w:document
              xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
              xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
              <w:body>
                <w:p>
                  <w:pPr><w:pStyle w:val="Heading1"/><w:jc w:val="center"/></w:pPr>
                  <w:r><w:rPr><w:b/><w:i/><w:u/></w:rPr><w:t>Über &amp; bereit</w:t></w:r>
                  <w:hyperlink r:id="link"><w:r><w:t> Link</w:t></w:r></w:hyperlink>
                </w:p>
                <w:p><w:pPr><w:numPr/></w:pPr><w:r><w:t>- Item</w:t></w:r></w:p>
                <w:p><w:r><w:tab/><w:t>Tabbed</w:t><w:br/><w:t>Line</w:t></w:r></w:p>
                <w:p><w:r><w:drawing><a:blip r:embed="image"/></w:drawing></w:r></w:p>
              </w:body>
            </w:document>
            """,
            relationshipsXML: """
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="link" Target="https://example.com/?a=1&amp;b=2"/>
              <Relationship Id="image" Target="media/image 1.png"/>
            </Relationships>
            """
        )

        try expect(result.html.contains("<h1 id=\"docx-heading-1\" class=\"docx-align-center\">"), "Heading alignment should be retained")
        try expect(result.html.contains("<u><em><strong>Über &amp; bereit</strong></em></u>"), "Run formatting and entities should be retained")
        try expect(result.html.contains("<a href=\"https://example.com/?a=1&amp;b=2\"> Link</a>"), "Hyperlinks should be escaped and retained")
        try expect(result.html.contains("<ul>\n<li>Item</li>\n</ul>"), "List markers should not be duplicated in rendered HTML")
        try expect(result.html.contains("&emsp;Tabbed<br>Line"), "Tabs and line breaks should be retained")
        try expect(result.html.contains("word/media/image%201.png"), "Embedded media should resolve relative to the unpacked document")
        try expectEqual(result.plainText, ["Über & bereit Link", "- Item", "TabbedLine"], "Plain text should retain the existing source-text contract")
        try expectEqual(result.tocItems.count, 1, "A heading should create one TOC item")
        try expectEqual(result.tocItems[0].title, "Über & bereit Link", "TOC text should be emitted during parsing")
        try expectEqual(result.tocItems[0].href, "#docx-heading-1", "TOC anchors should match rendered headings")
        try expectEqual(result.tocItems[0].level, 0, "Heading 1 should map to TOC level zero")
    }

    static func testMalformedDocumentXMLFails() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let documentURL = directory.appendingPathComponent("document.xml")
        try Data("<w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:p>".utf8)
            .write(to: documentURL)
        do {
            _ = try WebDocumentLoader.docxStreamingContent(from: documentURL, directory: directory, relationships: [:])
            throw TestFailure(description: "Malformed DOCX XML should fail")
        } catch is TestFailure {
            throw TestFailure(description: "Malformed DOCX XML should fail before returning content")
        } catch {
            // Expected parser error.
        }
    }

    private static func renderDocument(
        _ documentXML: String,
        relationshipsXML: String? = nil
    ) throws -> DOCXStreamingResult {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let documentURL = directory.appendingPathComponent("document.xml")
        try Data(documentXML.utf8).write(to: documentURL)
        let relationships: [String: String]
        if let relationshipsXML {
            let relationshipsURL = directory.appendingPathComponent("relationships.xml")
            try Data(relationshipsXML.utf8).write(to: relationshipsURL)
            relationships = try WebDocumentLoader.docxStreamingRelationships(from: relationshipsURL)
        } else {
            relationships = [:]
        }
        return try WebDocumentLoader.docxStreamingContent(
            from: documentURL,
            directory: directory,
            relationships: relationships
        )
    }

    private static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeafReader-DOCXTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func requiredOffset(of needle: String, in haystack: String) throws -> Int {
        guard let range = haystack.range(of: needle) else {
            throw TestFailure(description: "Missing rendered DOCX fragment: \(needle)")
        }
        return haystack.distance(from: haystack.startIndex, to: range.lowerBound)
    }
}
