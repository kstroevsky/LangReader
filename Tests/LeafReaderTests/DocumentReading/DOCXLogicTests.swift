import Foundation
import LeafReaderCore

enum DOCXLogicTests {
    static func testTopLevelBlocksPreserveDocumentOrder() throws {
        let body = """
        <w:body>
          <w:p w:rsidR="first"><w:r><w:t>Before</w:t></w:r></w:p>
          <w:tbl>
            <w:tr><w:tc><w:p><w:r><w:t>Inside table</w:t></w:r></w:p></w:tc></w:tr>
          </w:tbl>
          <w:p><w:r><w:t>After</w:t></w:r></w:p>
        </w:body>
        """

        let blocks = WebDocumentLoader.docxTopLevelBlocks(from: body)

        try expectEqual(blocks.count, 3, "DOCX block parsing should return only top-level paragraphs and tables")
        try expect(blocks[0].hasPrefix("<w:p"), "DOCX block parsing should keep the first paragraph first")
        try expect(blocks[1].hasPrefix("<w:tbl"), "DOCX block parsing should keep the table between paragraphs")
        try expect(blocks[1].contains("Inside table"), "DOCX table blocks should retain their nested paragraphs")
        try expect(blocks[2].hasPrefix("<w:p"), "DOCX block parsing should keep the final paragraph last")
    }
}
