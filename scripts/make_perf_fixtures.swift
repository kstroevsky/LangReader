// Generates the PDF fixtures the performance baseline opens.
//
// A baseline is only comparable if the thing measured is the same every time,
// so the fixtures are synthesised deterministically here rather than depending
// on whatever documents happen to be on the machine. Small = the fast path,
// large = the one whose open time actually moves.
//
//   swift scripts/make_perf_fixtures.swift <output-dir>
import AppKit
import PDFKit

func makePDF(pages: Int, wordsPerPage: Int, to url: URL) {
    let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
    let document = PDFDocument()
    let sampleWords = ["Vokabel", "lesen", "Sprache", "Wörter", "Satz", "Absatz",
                       "Bedeutung", "Kontext", "Übung", "Wiederholung"]
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
            withAttributes: [.font: NSFont.systemFont(ofSize: 12),
                             .foregroundColor: NSColor.black]
        )
        image.unlockFocus()
        if let page = PDFPage(image: image) {
            document.insert(page, at: pageIndex)
        }
    }
    document.write(to: url)
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
    print("  \(url.lastPathComponent): \(pages) pages, \((size ?? 0) / 1024) KB")
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: make_perf_fixtures.swift <output-dir>\n".data(using: .utf8)!)
    exit(2)
}
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

print("Generating PDF fixtures in \(outDir.path):")
makePDF(pages: 2, wordsPerPage: 120, to: outDir.appendingPathComponent("small.pdf"))
makePDF(pages: 240, wordsPerPage: 240, to: outDir.appendingPathComponent("large.pdf"))
