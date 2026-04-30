import Foundation

enum MarkdownHTMLRenderer {
    private static let inlineCodeRegex = try! NSRegularExpression(pattern: "`([^`]+)`", options: [])
    private static let boldRegex       = try! NSRegularExpression(pattern: "\\*\\*([^*]+)\\*\\*", options: [])
    private static let italicRegex     = try! NSRegularExpression(pattern: "(?<!\\*)\\*([^*]+)\\*(?!\\*)", options: [])
    private static let linkRegex       = try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\((https?://[^)]+)\\)", options: [])
    private static let imageRegex        = try! NSRegularExpression(pattern: "!\\[([^\\]]*)\\]\\(([^)\\s]+)\\)", options: [])
    /// Matches relative src="..." attributes (skips http/https/file/data schemes).
    private static let relativeImgRegex  = try! NSRegularExpression(pattern: #"src="(?!https?://|file://|data:)([^"]+)""#, options: [])
    /// Matches $$inline display$$ (no newline) then $inline$ — tried in that order
    /// so that $$ is consumed as a unit before the single-$ alternative.
    private static let mathSpanRegex     = try! NSRegularExpression(pattern: "\\$\\$[^\\n]+?\\$\\$|\\$[^$\\n]+?\\$", options: [])

    /// Control-character sentinels that can never appear in real Markdown text.
    private static let codePlaceholderOpen  = "\u{0001}CODE\u{0001}"
    private static let codePlaceholderClose = "\u{0002}"
    private static let mathPlaceholderOpen  = "\u{0003}MATH\u{0003}"
    private static let mathPlaceholderClose = "\u{0004}"

    // -------------------------------------------------------------------------
    // HTML shell — built once as static constants so every renderDocument call
    // only allocates the <main> body string, not the surrounding boilerplate.
    // -------------------------------------------------------------------------

    static let htmlPrefix: String = """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <style>
            :root {
              color-scheme: light dark;
              --bg: #f9f9fb;
              --text: #1c1c1e;
              --muted: #636366;
              --line: #e5e5ea;
              --code-bg: rgba(118,118,128,0.10);
              --pre-bg: rgba(0,0,0,0.03);
              --quote-bg: rgba(240,134,74,0.06);
              --quote-line: #f0864a;
              --accent: #f0864a;
            }
            @media (prefers-color-scheme: dark) {
              :root {
                --bg: #111113;
                --text: #f5f5f7;
                --muted: #aeaeb2;
                --line: #2c2c2e;
                --code-bg: rgba(255,255,255,0.09);
                --pre-bg: rgba(255,255,255,0.04);
                --quote-bg: rgba(240,134,74,0.08);
                --quote-line: #ff9a60;
                --accent: #ff9a60;
              }
            }
            html, body {
              margin: 0;
              background: var(--bg);
              color: var(--text);
              font-family: "SF Pro Text", "PingFang SC", "Hiragino Sans GB", -apple-system, sans-serif;
              font-size: 17px;
              line-height: 1.8;
              -webkit-font-smoothing: antialiased;
            }
            main {
              max-width: 860px;
              margin: 0 auto;
              padding: 32px 32px 80px;
            }
            h1, h2, h3, h4, h5, h6 {
              line-height: 1.25;
              margin: 1.5em 0 0.5em;
              font-weight: 700;
              letter-spacing: -0.02em;
              scroll-margin-top: 12px;
            }
            h1 { font-size: 2.0em; margin-top: 0.75em; }
            h2 { font-size: 1.55em; }
            h3 { font-size: 1.28em; }
            h4 { font-size: 1.12em; }
            h1 + h2, h2 + h3 { margin-top: 0.6em; }
            p { margin: 0.85em 0; }
            ul, ol { margin: 0.75em 0 0.9em 1.5em; }
            li + li { margin-top: 0.3em; }
            code {
              font-family: "SF Mono", "Menlo", "Monaco", monospace;
              font-size: 0.85em;
              background: var(--code-bg);
              border-radius: 5px;
              padding: 0.15em 0.4em;
            }
            pre {
              background: var(--pre-bg);
              border: 1px solid var(--line);
              border-radius: 12px;
              padding: 16px 18px;
              overflow-x: auto;
              margin: 1.1em 0 1.2em;
            }
            pre code { padding: 0; background: transparent; font-size: 0.84em; }
            blockquote {
              margin: 1.1em 0;
              padding: 0.7em 1.1em;
              border-left: 3px solid var(--quote-line);
              background: var(--quote-bg);
              border-radius: 0 10px 10px 0;
              color: var(--muted);
            }
            .table-wrap { margin: 1.1em 0 1.2em; overflow-x: auto; }
            table {
              width: 100%;
              min-width: 400px;
              border-collapse: collapse;
              border: 1px solid var(--line);
              border-radius: 10px;
              font-size: 0.93em;
              overflow: hidden;
            }
            th, td { border: 1px solid var(--line); padding: 0.55em 0.8em; vertical-align: top; }
            th { text-align: left; font-weight: 600; background: var(--code-bg); }
            tr:hover td { background: var(--code-bg); }
            hr { border: 0; border-top: 1px solid var(--line); margin: 1.6em 0; }
            a { color: var(--accent); text-decoration: none; }
            a:hover { text-decoration: underline; }
            img { max-width: 100%; height: auto; display: block; margin: 1em auto; border-radius: 8px; }
            .math-block { overflow-x: auto; text-align: center; margin: 1.2em 0; }
            .katex-display { overflow-x: auto; overflow-y: hidden; }
            @media (max-width: 700px) {
              html, body { font-size: 16px; }
              main { padding: 20px 18px 60px; }
            }
          </style>
          <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css" crossorigin="anonymous">
          <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js" crossorigin="anonymous"></script>
          <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/contrib/auto-render.min.js" crossorigin="anonymous" onload="renderMathInElement(document.body,{delimiters:[{left:'$$',right:'$$',display:true},{left:'$',right:'$',display:false}],throwOnError:false})"></script>
        </head>
        <body>
          <main>
        """

    static let htmlSuffix: String = """
          </main>
        </body>
        </html>
        """

    // -------------------------------------------------------------------------
    // Public entry point
    // -------------------------------------------------------------------------

    static func renderDocument(from markdown: String, baseURL: URL? = nil) -> String {
        var body = renderBlocks(from: markdown)
        if let base = baseURL { body = rewriteImagePaths(in: body, baseURL: base) }
        var out = String()
        out.reserveCapacity(htmlPrefix.count + body.count + htmlSuffix.count + 2)
        out.append(htmlPrefix)
        out.append("\n")
        out.append(body)
        out.append("\n")
        out.append(htmlSuffix)
        return out
    }

    // MARK: - Image path rewriter

    /// Replace relative `src="path"` values with inline base64 data URIs.
    ///
    /// `loadHTMLString` runs inside the WKWebView content-process sandbox, so
    /// even absolute `file://` src attributes are blocked.  The only reliable
    /// way to show local images is to embed them as data URIs so the browser
    /// never makes a separate file-system request.
    ///
    /// This function is called on the background thread inside `loadContent`,
    /// so synchronous `Data(contentsOf:)` is fine here.
    private static func rewriteImagePaths(in html: String, baseURL: URL) -> String {
        let nsHTML  = html as NSString
        let range   = NSRange(location: 0, length: nsHTML.length)
        let matches = relativeImgRegex.matches(in: html, options: [], range: range)
        guard !matches.isEmpty else { return html }

        var result = String()
        result.reserveCapacity(html.count + matches.count * 256)
        var cursor = 0
        for match in matches {
            let fullRange = match.range
            if fullRange.location > cursor {
                result.append(nsHTML.substring(with: NSRange(location: cursor,
                                                             length: fullRange.location - cursor)))
            }
            let relPath = nsHTML.substring(with: match.range(at: 1))
            let absURL  = URL(fileURLWithPath: relPath, relativeTo: baseURL).standardized
            if let data = try? Data(contentsOf: absURL) {
                let mime = imageMIMEType(for: absURL.pathExtension.lowercased())
                result.append("src=\"data:\(mime);base64,\(data.base64EncodedString())\"")
            } else {
                // File unreadable — keep original so alt text at least shows.
                result.append("src=\"\(relPath)\"")
            }
            cursor = fullRange.location + fullRange.length
        }
        if cursor < nsHTML.length {
            result.append(nsHTML.substring(with: NSRange(location: cursor,
                                                        length: nsHTML.length - cursor)))
        }
        return result
    }

    private static func imageMIMEType(for ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png":         return "image/png"
        case "gif":         return "image/gif"
        case "webp":        return "image/webp"
        case "svg":         return "image/svg+xml"
        case "bmp":         return "image/bmp"
        case "ico":         return "image/x-icon"
        default:            return "image/png"
        }
    }

    // -------------------------------------------------------------------------
    // Block-level parser
    // -------------------------------------------------------------------------

    private static func renderBlocks(from markdown: String) -> String {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        var html: [String] = []
        var paragraphBuffer: [String] = []
        var codeBuffer: [String] = []
        var listBuffer: [String] = []
        var inCodeBlock    = false
        var inUnorderedList = false
        var inOrderedList  = false
        var inMathBlock    = false
        var mathBuffer:    [String] = []
        // Counter incremented for every heading; used as the HTML `id` value
        // so the TOC panel can jump to a specific heading via scrollIntoView.
        var headingCounter = 0

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let text = paragraphBuffer.joined(separator: " ")
            html.append("<p>\(renderInline(text))</p>")
            paragraphBuffer.removeAll(keepingCapacity: true)
        }

        func flushCodeBlock() {
            guard !codeBuffer.isEmpty else { return }
            let code = escapeHTML(codeBuffer.joined(separator: "\n"))
            html.append("<pre><code>\(code)</code></pre>")
            codeBuffer.removeAll(keepingCapacity: true)
        }

        func flushList() {
            if inUnorderedList { html.append("<ul>\(listBuffer.joined())</ul>") }
            else if inOrderedList { html.append("<ol>\(listBuffer.joined())</ol>") }
            listBuffer.removeAll(keepingCapacity: true)
            inUnorderedList = false
            inOrderedList   = false
        }

        func flushMathBlock() {
            guard inMathBlock else { return }
            let math = mathBuffer.joined(separator: "\n")
            html.append("<div class=\"math-block\">$$\n\(escapeHTML(math))\n$$</div>")
            mathBuffer.removeAll(keepingCapacity: true)
            inMathBlock = false
        }

        var index = 0
        while index < lines.count {
            let raw  = lines[index]
            let line = raw.trimmingCharacters(in: .whitespaces)

            // ── Fenced code block ──────────────────────────────────────────
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                flushParagraph()
                if inUnorderedList || inOrderedList { flushList() }
                if inCodeBlock { flushCodeBlock(); inCodeBlock = false }
                else           { inCodeBlock = true }
                index += 1; continue
            }

            if inCodeBlock { codeBuffer.append(raw); index += 1; continue }

            // ── Math display block ($$...$$) ────────────────────────────────
            if line == "$$" {
                flushParagraph()
                if inUnorderedList || inOrderedList { flushList() }
                if inMathBlock { flushMathBlock() }
                else           { inMathBlock = true }
                index += 1; continue
            }

            if inMathBlock { mathBuffer.append(raw); index += 1; continue }

            // ── Blank line ─────────────────────────────────────────────────
            if line.isEmpty {
                flushParagraph()
                if inUnorderedList || inOrderedList { flushList() }
                index += 1; continue
            }

            // ── Thematic break ─────────────────────────────────────────────
            if line == "---" || line == "***" {
                flushParagraph()
                if inUnorderedList || inOrderedList { flushList() }
                html.append("<hr />")
                index += 1; continue
            }

            // ── ATX heading ────────────────────────────────────────────────
            if let heading = parseHeading(from: line) {
                flushParagraph()
                if inUnorderedList || inOrderedList { flushList() }
                let id = "h-\(headingCounter)"
                headingCounter += 1
                html.append("<h\(heading.level) id=\"\(id)\">\(renderInline(heading.text))</h\(heading.level)>")
                index += 1; continue
            }

            // ── Blockquote ─────────────────────────────────────────────────
            if let quote = parseQuote(from: line) {
                flushParagraph()
                if inUnorderedList || inOrderedList { flushList() }
                html.append("<blockquote><p>\(renderInline(quote))</p></blockquote>")
                index += 1; continue
            }

            // ── Unordered list item ────────────────────────────────────────
            if let item = parseUnorderedListItem(from: line) {
                flushParagraph()
                if inOrderedList { flushList() }
                inUnorderedList = true
                listBuffer.append("<li>\(renderInline(item))</li>")
                index += 1; continue
            }

            // ── Ordered list item ──────────────────────────────────────────
            if let item = parseOrderedListItem(from: line) {
                flushParagraph()
                if inUnorderedList { flushList() }
                inOrderedList = true
                listBuffer.append("<li>\(renderInline(item))</li>")
                index += 1; continue
            }

            // ── GFM table ──────────────────────────────────────────────────
            if isPotentialTableRow(line), index + 1 < lines.count {
                let separatorLine = lines[index + 1].trimmingCharacters(in: .whitespaces)
                if isTableSeparatorRow(separatorLine) {
                    let headers    = splitTableRow(line)
                    let alignments = parseTableAlignmentRow(separatorLine)
                    if !headers.isEmpty, headers.count == alignments.count {
                        flushParagraph()
                        if inUnorderedList || inOrderedList { flushList() }
                        var rows: [[String]] = []
                        index += 2
                        while index < lines.count {
                            let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                            if candidate.isEmpty || !isPotentialTableRow(candidate) { break }
                            var cells = splitTableRow(candidate)
                            if cells.count < headers.count {
                                cells += Array(repeating: "", count: headers.count - cells.count)
                            } else if cells.count > headers.count {
                                cells = Array(cells.prefix(headers.count))
                            }
                            rows.append(cells)
                            index += 1
                        }
                        html.append(renderTable(headers: headers, alignments: alignments, rows: rows))
                        continue
                    }
                }
            }

            // ── Paragraph ──────────────────────────────────────────────────
            if inUnorderedList || inOrderedList { flushList() }
            paragraphBuffer.append(line)
            index += 1
        }

        flushParagraph()
        if inUnorderedList || inOrderedList { flushList() }
        if inCodeBlock { flushCodeBlock() }
        if inMathBlock { flushMathBlock() }

        return html.joined(separator: "\n")
    }

    // -------------------------------------------------------------------------
    // Block parsers
    // -------------------------------------------------------------------------

    private static func parseHeading(from line: String) -> (level: Int, text: String)? {
        var level = 0
        for ch in line { if ch == "#" { level += 1 } else { break } }
        guard level >= 1, level <= 6 else { return nil }
        let idx = line.index(line.startIndex, offsetBy: level)
        guard idx < line.endIndex, line[idx] == " " else { return nil }
        let rest = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        return (level, rest)
    }

    private static func parseQuote(from line: String) -> String? {
        guard line.hasPrefix(">") else { return nil }
        return line.dropFirst().trimmingCharacters(in: .whitespaces)
    }

    private static func parseUnorderedListItem(from line: String) -> String? {
        guard line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") else { return nil }
        let payload = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return payload.isEmpty ? nil : payload
    }

    private static func parseOrderedListItem(from line: String) -> String? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let numberPart = line[..<dot]
        guard !numberPart.isEmpty, numberPart.allSatisfy({ $0.isNumber }) else { return nil }
        let afterDot = line.index(after: dot)
        guard afterDot < line.endIndex, line[afterDot] == " " else { return nil }
        return String(line[line.index(after: afterDot)...]).trimmingCharacters(in: .whitespaces)
    }

    // -------------------------------------------------------------------------
    // GFM table helpers
    // -------------------------------------------------------------------------

    private static func isPotentialTableRow(_ line: String) -> Bool { line.contains("|") }

    private static func splitTableRow(_ line: String) -> [String] {
        var row = line.trimmingCharacters(in: .whitespaces)
        if row.hasPrefix("|") { row.removeFirst() }
        if row.hasSuffix("|") { row.removeLast() }
        return row.split(separator: "|", omittingEmptySubsequences: false)
                  .map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableSeparatorCell(_ cell: String) -> Bool {
        let t = cell.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return false }
        var dashes = 0
        for ch in t {
            if ch == "-" { dashes += 1 }
            else if ch == ":" { /* alignment marker */ }
            else { return false }
        }
        return dashes >= 3
    }

    private static func isTableSeparatorRow(_ line: String) -> Bool {
        let cells = splitTableRow(line)
        return !cells.isEmpty && cells.allSatisfy(isTableSeparatorCell)
    }

    private static func parseTableAlignmentRow(_ line: String) -> [String?] {
        splitTableRow(line).map { cell in
            let t = cell.trimmingCharacters(in: .whitespaces)
            let l = t.hasPrefix(":"), r = t.hasSuffix(":")
            if l && r { return "center" }
            if r      { return "right" }
            if l      { return "left" }
            return nil
        }
    }

    private static func renderTable(headers: [String], alignments: [String?], rows: [[String]]) -> String {
        let headerHTML = headers.enumerated().map { i, title in
            let style = alignments[i].map { " style=\"text-align: \($0);\"" } ?? ""
            return "<th\(style)>\(renderInline(title))</th>"
        }.joined()

        let bodyHTML = rows.map { row in
            let rowHTML = row.enumerated().map { i, value in
                let style = alignments[i].map { " style=\"text-align: \($0);\"" } ?? ""
                return "<td\(style)>\(renderInline(value))</td>"
            }.joined()
            return "<tr>\(rowHTML)</tr>"
        }.joined()

        return "<div class=\"table-wrap\"><table><thead><tr>\(headerHTML)</tr></thead><tbody>\(bodyHTML)</tbody></table></div>"
    }

    // -------------------------------------------------------------------------
    // Inline renderer  (inline-code bodies are protected from other regexes)
    // -------------------------------------------------------------------------

    private static func renderInline(_ text: String) -> String {
        // 1. Protect inline code (`...`) — body is never mutated by other passes.
        var codeBodies: [String] = []
        let afterCode = extractInlineCode(in: text, into: &codeBodies)

        // 2. Protect math spans ($...$, $$...$$) from bold/italic/link regex.
        //    Bodies are stored raw; HTML-escaping happens on restore so the
        //    browser DOM decodes entities back to plain LaTeX for KaTeX.
        var mathBodies: [String] = []
        let afterMath = extractMathSpans(in: afterCode, into: &mathBodies)

        // 3. Single-pass HTML escape on the remaining text.
        var out = escapeHTML(afterMath)

        // 4. Inline markup — images before links so ![alt](src) is consumed
        //    before the plain-link regex can match [alt](src).
        out = replaceRegex(boldRegex,   in: out, template: "<strong>$1</strong>")
        out = replaceRegex(italicRegex, in: out, template: "<em>$1</em>")
        out = replaceRegex(imageRegex,  in: out, template: "<img src=\"$2\" alt=\"$1\" loading=\"lazy\" />")
        out = replaceRegex(linkRegex,   in: out, template: "<a href=\"$2\">$1</a>")

        // 5. Restore math spans (HTML-escaped so browser DOM gives KaTeX clean LaTeX).
        if !mathBodies.isEmpty { out = restoreMathSpans(in: out, mathBodies: mathBodies) }

        // 6. Restore inline code spans.
        if !codeBodies.isEmpty { out = restoreInlineCode(in: out, codeBodies: codeBodies) }
        return out
    }

    private static func extractInlineCode(in text: String, into bodies: inout [String]) -> String {
        let nsText = text as NSString
        let range  = NSRange(location: 0, length: nsText.length)
        let matches = inlineCodeRegex.matches(in: text, options: [], range: range)
        guard !matches.isEmpty else { return text }

        var result = String()
        result.reserveCapacity(text.count)
        var cursor = 0
        for match in matches {
            let full = match.range
            if full.location > cursor {
                result.append(nsText.substring(with: NSRange(location: cursor, length: full.location - cursor)))
            }
            let body  = nsText.substring(with: match.range(at: 1))
            let token = "\(codePlaceholderOpen)\(bodies.count)\(codePlaceholderClose)"
            bodies.append(body)
            result.append(token)
            cursor = full.location + full.length
        }
        if cursor < nsText.length {
            result.append(nsText.substring(with: NSRange(location: cursor, length: nsText.length - cursor)))
        }
        return result
    }

    private static func restoreInlineCode(in text: String, codeBodies: [String]) -> String {
        var out = text
        for (i, body) in codeBodies.enumerated() {
            let token = "\(codePlaceholderOpen)\(i)\(codePlaceholderClose)"
            out = out.replacingOccurrences(of: token, with: "<code>\(escapeHTML(body))</code>")
        }
        return out
    }

    private static func extractMathSpans(in text: String, into bodies: inout [String]) -> String {
        let nsText  = text as NSString
        let range   = NSRange(location: 0, length: nsText.length)
        let matches = mathSpanRegex.matches(in: text, options: [], range: range)
        guard !matches.isEmpty else { return text }

        var result = String()
        result.reserveCapacity(text.count)
        var cursor = 0
        for match in matches {
            let full = match.range
            if full.location > cursor {
                result.append(nsText.substring(with: NSRange(location: cursor, length: full.location - cursor)))
            }
            let body  = nsText.substring(with: full)   // includes $ delimiters
            let token = "\(mathPlaceholderOpen)\(bodies.count)\(mathPlaceholderClose)"
            bodies.append(body)
            result.append(token)
            cursor = full.location + full.length
        }
        if cursor < nsText.length {
            result.append(nsText.substring(with: NSRange(location: cursor, length: nsText.length - cursor)))
        }
        return result
    }

    private static func restoreMathSpans(in text: String, mathBodies: [String]) -> String {
        var out = text
        for (i, body) in mathBodies.enumerated() {
            let token = "\(mathPlaceholderOpen)\(i)\(mathPlaceholderClose)"
            // escapeHTML ensures the LaTeX is valid in HTML; the browser DOM
            // decodes HTML entities to give KaTeX the raw LaTeX string.
            out = out.replacingOccurrences(of: token, with: escapeHTML(body))
        }
        return out
    }

    private static func replaceRegex(_ regex: NSRegularExpression, in input: String, template: String) -> String {
        regex.stringByReplacingMatches(in: input,
                                       options: [],
                                       range: NSRange(input.startIndex..., in: input),
                                       withTemplate: template)
    }

    /// Single-pass HTML escape — traverses the string once instead of calling
    /// three separate `replacingOccurrences` passes.
    private static func escapeHTML(_ text: String) -> String {
        var out = String()
        out.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out.append("&amp;")
            case "<": out.append("&lt;")
            case ">": out.append("&gt;")
            default:  out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
