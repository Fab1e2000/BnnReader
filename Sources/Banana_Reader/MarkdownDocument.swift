import Foundation

/// A heading entry in the document's table of contents.
///
/// `id` is the 0-based heading index and corresponds to the HTML element
/// `id="h-\(id)"` written by `MarkdownHTMLRenderer`, so calling
///     `document.getElementById('h-\(entry.id)').scrollIntoView(...)`
/// reliably jumps to the correct heading.
struct TOCEntry: Identifiable, Sendable {
    let id: Int
    let level: Int    // 1–6
    let text: String  // heading text without leading `#` markers
}

/// Stateless utilities for extracting document structure from raw Markdown.
enum MarkdownDocument {

    /// Walk *markdown* and return every ATX heading as a `TOCEntry`.
    ///
    /// The heading counter is kept in sync with `MarkdownHTMLRenderer`:
    /// the N-th heading in the source always gets `id = N` (0-based), which
    /// maps to `id="h-N"` in the rendered HTML.
    ///
    /// Lines inside fenced code blocks are correctly ignored so that `#` inside
    /// a code sample is never treated as a heading.
    static func extractTOC(_ markdown: String) -> [TOCEntry] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        var toc: [TOCEntry] = []
        var headingCounter = 0
        var inCodeBlock = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inCodeBlock.toggle()
                continue
            }
            if inCodeBlock { continue }

            if let heading = headingAttributes(of: trimmed) {
                toc.append(TOCEntry(id: headingCounter, level: heading.level, text: heading.text))
                headingCounter += 1
            }
        }

        return toc
    }

    // MARK: - Private

    private static func headingAttributes(of line: String) -> (level: Int, text: String)? {
        var level = 0
        for ch in line { if ch == "#" { level += 1 } else { break } }
        guard level >= 1, level <= 6 else { return nil }
        let afterHashes = line.dropFirst(level)
        guard afterHashes.hasPrefix(" ") else { return nil }
        let text = afterHashes.dropFirst().trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (level, text)
    }
}
