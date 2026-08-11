#!/usr/bin/env swift
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make_docx_perf_fixture.swift <output.docx>\n".utf8))
    exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
guard output.pathExtension.lowercased() == "docx" else {
    FileHandle.standardError.write(Data("output must end in .docx\n".utf8))
    exit(2)
}
let manager = FileManager.default
let root = manager.temporaryDirectory.appendingPathComponent("LeafReader-Synthetic-DOCX-\(UUID().uuidString)", isDirectory: true)
defer { try? manager.removeItem(at: root) }

func write(_ text: String, path: String) throws {
    let url = root.appendingPathComponent(path)
    try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

do {
    let repeated = (0..<5_000).map { index in
        "<w:p><w:r><w:t>Deterministic paragraph \(index): Grüße, 漢字, 😀 &amp; XML entities.</w:t></w:r></w:p>"
    }.joined()
    let body = """
    <w:p><w:pPr><w:pStyle w:val="Title"/><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/><w:i/><w:u/></w:rPr><w:t>Complete synthetic DOCX</w:t></w:r></w:p>
    <w:p><w:pPr><w:pStyle w:val="Heading2"/><w:jc w:val="right"/></w:pPr><w:r><w:t>Formatting &amp; links</w:t></w:r></w:p>
    <w:p><w:hyperlink r:id="external"><w:r><w:t>External link</w:t></w:r></w:hyperlink><w:r><w:tab/><w:t>after tab</w:t><w:br/><w:t>after break</w:t></w:r></w:p>
    <w:p><w:pPr><w:pStyle w:val="Heading3"/><w:jc w:val="both"/></w:pPr><w:r><w:t>Lists, tables &amp; media</w:t></w:r></w:p>
    <w:p><w:pPr><w:numPr/></w:pPr><w:r><w:t>- First list item</w:t></w:r></w:p>
    <w:p><w:pPr><w:pStyle w:val="ListParagraph"/></w:pPr><w:r><w:t>Second list item</w:t></w:r></w:p>
    <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Cell one</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Cell two</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
    <w:p><w:r><w:drawing><a:blip r:embed="image"/></w:drawing></w:r></w:p>
    <w:p><w:hyperlink r:id="missing"><w:r><w:t>Missing relationship fallback</w:t></w:r></w:hyperlink></w:p>
    <w:p></w:p>
    \(repeated)
    """
    try write("""
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
      xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
      xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><w:body>\(body)</w:body></w:document>
    """, path: "word/document.xml")
    try write("""
    <?xml version="1.0" encoding="UTF-8"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="external" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://example.com/?a=1&amp;b=2" TargetMode="External"/>
      <Relationship Id="image" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image.png"/>
    </Relationships>
    """, path: "word/_rels/document.xml.rels")
    try write("""
    <?xml version="1.0" encoding="UTF-8"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Default Extension="png" ContentType="image/png"/>
      <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    </Types>
    """, path: "[Content_Types].xml")
    try write("""
    <?xml version="1.0" encoding="UTF-8"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="document" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """, path: "_rels/.rels")
    let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    let imageURL = root.appendingPathComponent("word/media/image.png")
    try manager.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try png.write(to: imageURL)

    let archiveFiles = [
        "[Content_Types].xml", "_rels/.rels", "word/document.xml",
        "word/_rels/document.xml.rels", "word/media/image.png"
    ]
    let fixedDate = Date(timeIntervalSince1970: 978_307_200)
    for path in archiveFiles {
        try manager.setAttributes([.modificationDate: fixedDate], ofItemAtPath: root.appendingPathComponent(path).path)
    }
    if manager.fileExists(atPath: output.path) { try manager.removeItem(at: output) }
    try manager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
    process.arguments = ["-X", "-q", output.path] + archiveFiles
    process.currentDirectoryURL = root
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw NSError(domain: "DOCXFixture", code: Int(process.terminationStatus)) }
    print(output.path)
} catch {
    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
    exit(1)
}
