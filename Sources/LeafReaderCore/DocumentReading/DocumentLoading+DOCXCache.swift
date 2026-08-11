import CryptoKit
import Foundation

package struct DOCXPreparedCachePolicy: Sendable {
    package let maximumBytes: Int64
    package let maximumEntries: Int

    package init(maximumBytes: Int64 = 512 * 1_024 * 1_024, maximumEntries: Int = 10) {
        self.maximumBytes = maximumBytes
        self.maximumEntries = maximumEntries
    }
}

private struct DOCXPreparedTOCItem: Codable {
    let title: String
    let href: String
    let level: Int

    init(_ item: ReaderTOCItem) {
        title = item.title
        href = item.href
        level = item.level
    }

    var readerItem: ReaderTOCItem {
        ReaderTOCItem(title: title, href: href, level: level)
    }
}

private struct DOCXPreparedMediaFile: Codable {
    let path: String
    let bytes: Int64
}

private struct DOCXPreparedManifest: Codable {
    let schemaVersion: Int
    let fingerprint: String
    let title: String
    let entryBytes: Int64
    let htmlSHA256: String
    let plainTextSHA256: String
    let tocSHA256: String
    let media: [DOCXPreparedMediaFile]
}

private struct DOCXPreparedEntry {
    let directory: URL
    var document: WebReadableDocument
}

private enum DOCXPreparedCache {
    static let schemaVersion = 1
    static let manifestName = "manifest.json"
    static let htmlName = "rendered.html"
    static let plainTextName = "plain-text.txt"
    static let tocName = "toc.json"

    static func defaultRoot() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["LEAFREADER_DOCX_CACHE_ROOT"],
           !override.isEmpty {
            let root = URL(fileURLWithPath: override, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            return root
        }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let root = caches
            .appendingPathComponent(AppIdentity.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("DOCXPreparedCache", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func key(fingerprint: String, title: String) -> String {
        let input = "\(schemaVersion)\u{0}\(fingerprint)\u{0}\(title)"
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func selectedArchiveEntries(from allEntries: [String]) throws -> [String] {
        for path in allEntries {
            let rawComponents = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !path.contains("\\"),
                  !path.contains("\0"),
                  !path.hasPrefix("/"),
                  !rawComponents.contains(".."),
                  EPUBPathResolver.safeArchivePath(path) != nil else {
                throw NSError(domain: "LeafReader", code: -3, userInfo: [
                    NSLocalizedDescriptionKey: "The DOCX archive contains an unsafe path: \(path)"
                ])
            }
        }
        guard allEntries.contains("word/document.xml") else {
            throw NSError(domain: "LeafReader", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "The DOCX archive has no word/document.xml entry."
            ])
        }
        return allEntries.filter {
            $0 == "word/document.xml"
                || $0 == "word/_rels/document.xml.rels"
                || ($0.hasPrefix("word/media/") && !$0.hasSuffix("/"))
        }
    }

    static func load(
        directory: URL,
        fingerprint: String,
        title: String,
        measurements: [DocumentLoadMeasurement]
    ) throws -> DOCXPreparedEntry {
        let manifestURL = directory.appendingPathComponent(manifestName)
        let htmlURL = directory.appendingPathComponent(htmlName)
        let plainURL = directory.appendingPathComponent(plainTextName)
        let tocURL = directory.appendingPathComponent(tocName)
        let manifestData = try Data(contentsOf: manifestURL, options: .mappedIfSafe)
        let manifest = try JSONDecoder().decode(DOCXPreparedManifest.self, from: manifestData)
        guard manifest.schemaVersion == schemaVersion,
              manifest.fingerprint == fingerprint,
              manifest.title == title,
              manifest.entryBytes > 0,
              digest(of: htmlURL) == manifest.htmlSHA256,
              digest(of: plainURL) == manifest.plainTextSHA256,
              digest(of: tocURL) == manifest.tocSHA256 else {
            throw NSError(domain: "LeafReader", code: -4, userInfo: [
                NSLocalizedDescriptionKey: "The prepared DOCX cache entry is invalid."
            ])
        }
        for media in manifest.media {
            guard let path = EPUBPathResolver.safeArchivePath(media.path),
                  path == media.path,
                  fileSize(directory.appendingPathComponent(path)) == media.bytes else {
                throw NSError(domain: "LeafReader", code: -4, userInfo: [
                    NSLocalizedDescriptionKey: "A prepared DOCX media file is invalid."
                ])
            }
        }
        let plainText = try String(contentsOf: plainURL, encoding: .utf8)
        let tocData = try Data(contentsOf: tocURL, options: .mappedIfSafe)
        let toc = try JSONDecoder().decode([DOCXPreparedTOCItem].self, from: tocData).map(\.readerItem)
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: directory.path)
        return DOCXPreparedEntry(
            directory: directory,
            document: WebReadableDocument(
                html: "",
                htmlFileURL: htmlURL,
                baseURL: directory,
                plainText: plainText,
                plainTextLoader: nil,
                coverImageURL: nil,
                tocItems: toc,
                diagnostics: [],
                loadMeasurements: measurements
            )
        )
    }

    static func write(
        directory: URL,
        fingerprint: String,
        title: String,
        content: DOCXStreamingResult
    ) throws -> Int64 {
        let htmlURL = directory.appendingPathComponent(htmlName)
        let plainURL = directory.appendingPathComponent(plainTextName)
        let tocURL = directory.appendingPathComponent(tocName)
        let body = content.html.isEmpty ? "<p>Unable to read DOCX content.</p>" : content.html
        let html = WebDocumentLoader.pageHTML(
            title: title,
            body: body,
            documentStyles: WebDocumentLoader.docxReaderStyles,
            profile: .docx
        )
        let plainText = content.plainText.joined(separator: "\n\n")
        let tocData = try JSONEncoder().encode(content.tocItems.map(DOCXPreparedTOCItem.init))
        try Data(html.utf8).write(to: htmlURL, options: .atomic)
        try Data(plainText.utf8).write(to: plainURL, options: .atomic)
        try tocData.write(to: tocURL, options: .atomic)

        let media = try mediaFiles(in: directory)
        let contentBytes = fileSize(htmlURL) + fileSize(plainURL) + fileSize(tocURL)
            + media.reduce(0) { $0 + $1.bytes }
        let provisional = DOCXPreparedManifest(
            schemaVersion: schemaVersion,
            fingerprint: fingerprint,
            title: title,
            entryBytes: contentBytes,
            htmlSHA256: try requiredDigest(of: htmlURL),
            plainTextSHA256: try requiredDigest(of: plainURL),
            tocSHA256: try requiredDigest(of: tocURL),
            media: media
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var final = provisional
        var manifestData = try encoder.encode(final)
        for _ in 0..<3 {
            let exactBytes = contentBytes + Int64(manifestData.count)
            guard exactBytes != final.entryBytes else { break }
            final = DOCXPreparedManifest(
                schemaVersion: provisional.schemaVersion,
                fingerprint: provisional.fingerprint,
                title: provisional.title,
                entryBytes: exactBytes,
                htmlSHA256: provisional.htmlSHA256,
                plainTextSHA256: provisional.plainTextSHA256,
                tocSHA256: provisional.tocSHA256,
                media: provisional.media
            )
            manifestData = try encoder.encode(final)
        }
        try manifestData.write(to: directory.appendingPathComponent(manifestName), options: .atomic)
        return final.entryBytes
    }

    static func clean(root: URL, keeping currentKey: String, policy: DOCXPreparedCachePolicy) {
        guard var entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter({ $0.lastPathComponent != currentKey && !$0.lastPathComponent.hasPrefix(".building-") }) else {
            return
        }
        entries.sort {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }
        let current = root.appendingPathComponent(currentKey, isDirectory: true)
        var totalBytes = entryBytes(at: current)
        var totalEntries = FileManager.default.fileExists(atPath: current.path) ? 1 : 0
        for entry in entries {
            totalBytes += entryBytes(at: entry)
            totalEntries += 1
        }
        while (totalEntries > policy.maximumEntries || totalBytes > policy.maximumBytes), !entries.isEmpty {
            let victim = entries.removeFirst()
            let bytes = entryBytes(at: victim)
            if (try? FileManager.default.removeItem(at: victim)) != nil {
                totalBytes -= bytes
                totalEntries -= 1
            }
        }
    }

    static func entryBytes(at directory: URL) -> Int64 {
        let manifestURL = directory.appendingPathComponent(manifestName)
        if let data = try? Data(contentsOf: manifestURL),
           let manifest = try? JSONDecoder().decode(DOCXPreparedManifest.self, from: data) {
            return manifest.entryBytes
        }
        return 0
    }

    private static func mediaFiles(in directory: URL) throws -> [DOCXPreparedMediaFile] {
        let mediaRoot = directory.appendingPathComponent("word/media", isDirectory: true)
        guard FileManager.default.fileExists(atPath: mediaRoot.path) else { return [] }
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: mediaRoot,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var media: [DOCXPreparedMediaFile] = []
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: Set(resourceKeys))
            guard values.isRegularFile == true else { continue }
            let path = EPUBPathResolver.relativeFilePath(from: directory, to: file)
            guard EPUBPathResolver.safeArchivePath(path) == path else {
                throw NSError(domain: "LeafReader", code: -3, userInfo: [
                    NSLocalizedDescriptionKey: "The prepared DOCX media path is unsafe."
                ])
            }
            media.append(DOCXPreparedMediaFile(path: path, bytes: Int64(values.fileSize ?? 0)))
        }
        return media.sorted { $0.path < $1.path }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1)
    }

    private static func digest(of url: URL) -> String? {
        DocumentContentFingerprint.sha256(for: url)
    }

    private static func requiredDigest(of url: URL) throws -> String {
        guard let digest = digest(of: url) else {
            throw NSError(domain: "LeafReader", code: -5, userInfo: [
                NSLocalizedDescriptionKey: "Unable to fingerprint a prepared DOCX file."
            ])
        }
        return digest
    }
}

extension WebDocumentLoader {
    package static func validatedDOCXArchiveEntries(_ entries: [String]) throws -> [String] {
        try DOCXPreparedCache.selectedArchiveEntries(from: entries)
    }

    package static func loadPreparedDOCX(
        url: URL,
        cacheRootURL: URL? = nil,
        policy: DOCXPreparedCachePolicy = .init()
    ) throws -> WebReadableDocument {
        let title = url.deletingPathExtension().lastPathComponent
        var measurements: [DocumentLoadMeasurement] = []

        var startedAt = ProcessInfo.processInfo.systemUptime
        guard let fingerprint = DocumentContentFingerprint.sha256(for: url) else {
            return try loadUncachedStreamingDOCX(url: url, measurements: measurements)
        }
        measurements.append(measurement(.docxFingerprint, since: startedAt))

        let root: URL
        do {
            root = try cacheRootURL.map {
                try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true)
                return $0
            } ?? DOCXPreparedCache.defaultRoot()
        } catch {
            return try loadUncachedStreamingDOCX(url: url, measurements: measurements)
        }
        let key = DOCXPreparedCache.key(fingerprint: fingerprint, title: title)
        let destination = root.appendingPathComponent(key, isDirectory: true)

        startedAt = ProcessInfo.processInfo.systemUptime
        if FileManager.default.fileExists(atPath: destination.path) {
            do {
                var hitMeasurements = measurements
                hitMeasurements.append(measurement(.docxCacheLookup, since: startedAt))
                let loadStartedAt = ProcessInfo.processInfo.systemUptime
                var entry = try DOCXPreparedCache.load(
                    directory: destination,
                    fingerprint: fingerprint,
                    title: title,
                    measurements: hitMeasurements
                )
                entry.document.loadMeasurements.append(measurement(.docxCacheHitLoad, since: loadStartedAt))
                DOCXPreparedCache.clean(root: root, keeping: key, policy: policy)
                return entry.document
            } catch {
                try? FileManager.default.removeItem(at: destination)
            }
        }
        measurements.append(measurement(.docxCacheLookup, since: startedAt))

        let temporary = root.appendingPathComponent(".building-\(key)-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            startedAt = ProcessInfo.processInfo.systemUptime
            let entries = try validatedDOCXArchiveEntries(zipEntryPaths(in: url))
            try unzip(url: url, to: temporary, entryPaths: entries)
            measurements.append(measurement(.docxArchiveExtraction, since: startedAt))

            startedAt = ProcessInfo.processInfo.systemUptime
            let relationships = try docxStreamingRelationships(
                from: temporary.appendingPathComponent("word/_rels/document.xml.rels")
            )
            measurements.append(measurement(.docxRelationshipParse, since: startedAt))

            startedAt = ProcessInfo.processInfo.systemUptime
            let content = try docxStreamingContent(
                from: temporary.appendingPathComponent("word/document.xml"),
                directory: temporary,
                relationships: relationships,
                mediaReferenceStyle: .relativeToPreparedEntry
            )
            measurements.append(measurement(.docxXMLRender, since: startedAt))
            try? FileManager.default.removeItem(at: temporary.appendingPathComponent("word/document.xml"))
            try? FileManager.default.removeItem(at: temporary.appendingPathComponent("word/_rels", isDirectory: true))

            startedAt = ProcessInfo.processInfo.systemUptime
            let entryBytes = try DOCXPreparedCache.write(
                directory: temporary,
                fingerprint: fingerprint,
                title: title,
                content: content
            )
            if entryBytes > policy.maximumBytes || policy.maximumEntries < 1 {
                measurements.append(measurement(.docxCacheCommit, since: startedAt))
                return try DOCXPreparedCache.load(
                    directory: temporary,
                    fingerprint: fingerprint,
                    title: title,
                    measurements: measurements
                ).document
            }
            do {
                try FileManager.default.moveItem(at: temporary, to: destination)
            } catch {
                if FileManager.default.fileExists(atPath: destination.path),
                   let winner = try? DOCXPreparedCache.load(
                    directory: destination,
                    fingerprint: fingerprint,
                    title: title,
                    measurements: measurements
                   ) {
                    try? FileManager.default.removeItem(at: temporary)
                    measurements.append(measurement(.docxCacheCommit, since: startedAt))
                    var winnerDocument = winner.document
                    winnerDocument.loadMeasurements = measurements
                    DOCXPreparedCache.clean(root: root, keeping: key, policy: policy)
                    return winnerDocument
                }
                throw error
            }
            measurements.append(measurement(.docxCacheCommit, since: startedAt))
            DOCXPreparedCache.clean(root: root, keeping: key, policy: policy)
            return try DOCXPreparedCache.load(
                directory: destination,
                fingerprint: fingerprint,
                title: title,
                measurements: measurements
            ).document
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            if (error as NSError).code == -3 {
                throw error
            }
            return try loadUncachedStreamingDOCX(url: url, measurements: measurements)
        }
    }

    private static func loadUncachedStreamingDOCX(
        url: URL,
        measurements initialMeasurements: [DocumentLoadMeasurement]
    ) throws -> WebReadableDocument {
        var measurements = initialMeasurements
        var startedAt = ProcessInfo.processInfo.systemUptime
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeafReader-DOCX-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let entries = try validatedDOCXArchiveEntries(zipEntryPaths(in: url))
        try unzip(url: url, to: directory, entryPaths: entries)
        measurements.append(measurement(.docxArchiveExtraction, since: startedAt))
        startedAt = ProcessInfo.processInfo.systemUptime
        let relationships = try docxStreamingRelationships(
            from: directory.appendingPathComponent("word/_rels/document.xml.rels")
        )
        measurements.append(measurement(.docxRelationshipParse, since: startedAt))
        startedAt = ProcessInfo.processInfo.systemUptime
        let content = try docxStreamingContent(
            from: directory.appendingPathComponent("word/document.xml"),
            directory: directory,
            relationships: relationships
        )
        measurements.append(measurement(.docxXMLRender, since: startedAt))
        let title = url.deletingPathExtension().lastPathComponent
        return WebReadableDocument(
            html: pageHTML(
                title: title,
                body: content.html.isEmpty ? "<p>Unable to read DOCX content.</p>" : content.html,
                documentStyles: docxReaderStyles,
                profile: .docx
            ),
            htmlFileURL: nil,
            baseURL: directory,
            plainText: content.plainText.joined(separator: "\n\n"),
            plainTextLoader: nil,
            coverImageURL: nil,
            tocItems: content.tocItems,
            diagnostics: [],
            loadMeasurements: measurements
        )
    }

    private static func measurement(_ event: PerformanceEvent, since startedAt: TimeInterval) -> DocumentLoadMeasurement {
        DocumentLoadMeasurement(
            event: event,
            milliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        )
    }
}
