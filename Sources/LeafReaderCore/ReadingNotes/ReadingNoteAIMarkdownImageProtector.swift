import Foundation

package struct ReadingNoteAIMarkdownImageProtector {
    package struct ImagePlaceholder: Equatable {
        package let placeholder: String
        package let markdown: String
    }

    package struct ProtectedMarkdown {
        package let markdown: String
        package let placeholders: [ImagePlaceholder]

        package var isEmpty: Bool {
            placeholders.isEmpty
        }
    }

    package static func protect(_ markdown: String) -> ProtectedMarkdown {
        var placeholders: [ImagePlaceholder] = []
        var protectedLines: [String] = []
        var imageIndex = 1

        for line in markdown.components(separatedBy: .newlines) {
            if isImageMarkdownLine(line) {
                let placeholder = "[[LEAF_IMAGE_\(imageIndex)]]"
                placeholders.append(ImagePlaceholder(placeholder: placeholder, markdown: line))
                protectedLines.append(placeholder)
                imageIndex += 1
            } else {
                protectedLines.append(line)
            }
        }

        return ProtectedMarkdown(
            markdown: protectedLines.joined(separator: "\n"),
            placeholders: placeholders
        )
    }

    package static func restore(_ markdown: String, protected: ProtectedMarkdown) -> String {
        var restored = markdown
        var missingImages: [String] = []
        for item in protected.placeholders {
            if restored.contains(item.placeholder) {
                restored = restored.replacingOccurrences(of: item.placeholder, with: item.markdown)
            } else {
                missingImages.append(item.markdown)
            }
        }
        guard !missingImages.isEmpty else { return restored }
        let suffix = restored.hasSuffix("\n") || restored.isEmpty ? "" : "\n\n"
        return restored + suffix + missingImages.joined(separator: "\n")
    }

    private static func isImageMarkdownLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("![") else { return false }
        return trimmed.range(of: #"^!\[[^\]]*\]\([^)]+\)$"#, options: .regularExpression) != nil
    }
}
