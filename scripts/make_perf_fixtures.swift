// Generates deterministic PDF and EPUB fixtures for the performance matrix.
//
//   swift scripts/make_perf_fixtures.swift <output-dir>
import AppKit
import PDFKit

let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
let sampleWords = [
    "Vokabel", "lesen", "Sprache", "Wörter", "Satz", "Absatz",
    "Bedeutung", "Kontext", "Übung", "Wiederholung"
]

func report(_ url: URL, detail: String) {
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
    print("  \(url.lastPathComponent): \(detail), \((size ?? 0) / 1024) KB")
}

/// Retains the historical raster fixtures used by the small/large launch gate.
func makeImagePDF(pages: Int, wordsPerPage: Int, to url: URL) {
    let document = PDFDocument()
    for pageIndex in 0..<pages {
        let image = NSImage(size: pageRect.size)
        image.lockFocus()
        NSColor.white.setFill()
        pageRect.fill()
        var text = "Page \(pageIndex + 1)\n\n"
        for word in 0..<wordsPerPage {
            text += sampleWords[word % sampleWords.count] + " "
            if word % 12 == 11 { text += "\n" }
        }
        (text as NSString).draw(
            in: pageRect.insetBy(dx: 48, dy: 48),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.black
            ]
        )
        image.unlockFocus()
        if let page = PDFPage(image: image) { document.insert(page, at: pageIndex) }
    }
    document.write(to: url)
    report(url, detail: "\(pages) raster pages")
}

func makeTextPDF(
    pages: Int,
    to url: URL,
    drawPage: (_ pageIndex: Int, _ bounds: CGRect) -> Void
) {
    var mediaBox = pageRect
    guard let consumer = CGDataConsumer(url: url as CFURL),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        fatalError("Unable to create \(url.path)")
    }
    for pageIndex in 0..<pages {
        context.beginPDFPage(nil)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(pageRect)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        drawPage(pageIndex, pageRect)
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
    }
    context.closePDF()
    report(url, detail: "\(pages) selectable-text pages")
}

func prose(pageIndex: Int, paragraphs: Int) -> String {
    (0..<paragraphs).map { paragraph in
        let rotation = (pageIndex + paragraph) % sampleWords.count
        let words = (0..<70).map { sampleWords[(rotation + $0) % sampleWords.count] }
        return words.joined(separator: " ") + "."
    }.joined(separator: "\n\n")
}

func makeCleanPDF(to url: URL) {
    makeTextPDF(pages: 300, to: url) { pageIndex, bounds in
        let title = "Clean selectable document — page \(pageIndex + 1)"
        (title as NSString).draw(
            at: CGPoint(x: 48, y: bounds.maxY - 54),
            withAttributes: [.font: NSFont.boldSystemFont(ofSize: 14)]
        )
        (prose(pageIndex: pageIndex, paragraphs: 7) as NSString).draw(
            in: CGRect(x: 48, y: 48, width: 516, height: 670),
            withAttributes: [.font: NSFont.systemFont(ofSize: 10)]
        )
    }
}

func makeComplexPDF(to url: URL) {
    makeTextPDF(pages: 120, to: url) { pageIndex, bounds in
        let header = "Journal header · Straße · Café · ﬁ ligature · page \(pageIndex + 1)"
        (header as NSString).draw(
            at: CGPoint(x: 38, y: bounds.maxY - 42),
            withAttributes: [.font: NSFont.boldSystemFont(ofSize: 11)]
        )
        let left = prose(pageIndex: pageIndex, paragraphs: 8)
            + "\n\ncoöperate naïve ﬂower e\u{301}lan soft\u{00AD}hyphen"
        let right = prose(pageIndex: pageIndex + 17, paragraphs: 8)
            + "\n\nE-Mail high-quality multi-column Fußgängerübergang"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8.5)]
        (left as NSString).draw(in: CGRect(x: 38, y: 54, width: 252, height: 670), withAttributes: attributes)
        (right as NSString).draw(in: CGRect(x: 322, y: 54, width: 252, height: 670), withAttributes: attributes)
        NSColor.lightGray.setStroke()
        NSBezierPath(rect: CGRect(x: 306, y: 54, width: 1, height: 670)).stroke()
    }
}

/// Mimics an OCR export: a raster page with an invisible, noisy text layer.
func makeOCRPDF(to url: URL) {
    makeTextPDF(pages: 100, to: url) { pageIndex, bounds in
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        bounds.fill()
        let visible = "SCAN \(pageIndex + 1)\nW0rter   mit  ungewohnlichen   Abstanden\nsi-\ncherzustellen  OCR  n0ise"
        (visible as NSString).draw(
            in: CGRect(x: 55, y: 420, width: 500, height: 250),
            withAttributes: [.font: NSFont(name: "Courier", size: 17) ?? NSFont.systemFont(ofSize: 17)]
        )
        image.unlockFocus()
        image.draw(in: bounds)

        let hidden = "scan page \(pageIndex + 1) Wörter   mit ungewöhnlichen   Abständen si-\ncherzustellen OCR noise"
        (hidden as NSString).draw(
            in: CGRect(x: 55, y: 420, width: 500, height: 250),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 17),
                .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.01)
            ]
        )
    }
}

func run(_ executable: String, _ arguments: [String], in directory: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.standardOutput = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "PerfFixtures", code: Int(process.terminationStatus))
    }
}

func makeEPUB(chapters: Int, paragraphsPerChapter: Int, to url: URL) throws {
    let fileManager = FileManager.default
    let package = url.deletingLastPathComponent()
        .appendingPathComponent(".\(url.deletingPathExtension().lastPathComponent)-package", isDirectory: true)
    try? fileManager.removeItem(at: package)
    try? fileManager.removeItem(at: url)
    let meta = package.appendingPathComponent("META-INF", isDirectory: true)
    let oebps = package.appendingPathComponent("OEBPS", isDirectory: true)
    try fileManager.createDirectory(at: meta, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: oebps, withIntermediateDirectories: true)
    try "application/epub+zip".write(to: package.appendingPathComponent("mimetype"), atomically: true, encoding: .utf8)
    try """
    <?xml version="1.0"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
    </container>
    """.write(to: meta.appendingPathComponent("container.xml"), atomically: true, encoding: .utf8)

    var manifest = "<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>"
    var spine = ""
    var navigation = ""
    for chapter in 1...chapters {
        manifest += "<item id=\"c\(chapter)\" href=\"c\(chapter).xhtml\" media-type=\"application/xhtml+xml\"/>"
        spine += "<itemref idref=\"c\(chapter)\"/>"
        navigation += "<li><a href=\"c\(chapter).xhtml\">Chapter \(chapter)</a></li>"
        let paragraphs = (0..<paragraphsPerChapter).map { paragraph in
            let style = ["lead", "quote", "aside", "body"][paragraph % 4]
            return "<p class=\"\(style)\">\(prose(pageIndex: chapter + paragraph, paragraphs: 1))</p>"
        }.joined(separator: "\n")
        let chapterHTML = """
        <?xml version="1.0" encoding="utf-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>Chapter \(chapter)</title><link rel="stylesheet" href="style.css"/></head>
        <body><h1 id="chapter-\(chapter)">Chapter \(chapter)</h1>\(paragraphs)</body></html>
        """
        try chapterHTML.write(to: oebps.appendingPathComponent("c\(chapter).xhtml"), atomically: true, encoding: .utf8)
    }
    try """
    <?xml version="1.0" encoding="utf-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="book" version="3.0">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="book">leafreader-perf-\(chapters)</dc:identifier><dc:title>Performance Fixture</dc:title><dc:language>de</dc:language></metadata>
      <manifest>\(manifest)<item id="css" href="style.css" media-type="text/css"/></manifest><spine>\(spine)</spine>
    </package>
    """.write(to: oebps.appendingPathComponent("content.opf"), atomically: true, encoding: .utf8)
    try """
    <?xml version="1.0" encoding="utf-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc"><ol>\(navigation)</ol></nav></body></html>
    """.write(to: oebps.appendingPathComponent("nav.xhtml"), atomically: true, encoding: .utf8)
    try """
    body { font-family: serif; line-height: 1.55; } .lead { font-size: 1.1em; } .quote { margin-left: 3em; font-style: italic; }
    .aside { border-left: 3px solid #888; padding-left: 1em; } h1 { break-before: page; }
    """.write(to: oebps.appendingPathComponent("style.css"), atomically: true, encoding: .utf8)

    try run("/usr/bin/zip", ["-X", "-0", url.path, "mimetype"], in: package)
    try run("/usr/bin/zip", ["-X", "-r", "-9", url.path, "META-INF", "OEBPS"], in: package)
    try fileManager.removeItem(at: package)
    report(url, detail: "\(chapters) chapters / \(chapters * paragraphsPerChapter) paragraphs")
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make_perf_fixtures.swift <output-dir>\n".utf8))
    exit(2)
}
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

print("Generating performance fixtures in \(outDir.path):")
makeImagePDF(pages: 2, wordsPerPage: 120, to: outDir.appendingPathComponent("small.pdf"))
makeImagePDF(pages: 240, wordsPerPage: 240, to: outDir.appendingPathComponent("large.pdf"))
makeCleanPDF(to: outDir.appendingPathComponent("clean-300.pdf"))
makeComplexPDF(to: outDir.appendingPathComponent("complex.pdf"))
makeOCRPDF(to: outDir.appendingPathComponent("ocr.pdf"))
try makeEPUB(chapters: 80, paragraphsPerChapter: 12, to: outDir.appendingPathComponent("normal.epub"))
try makeEPUB(chapters: 400, paragraphsPerChapter: 10, to: outDir.appendingPathComponent("large.epub"))
