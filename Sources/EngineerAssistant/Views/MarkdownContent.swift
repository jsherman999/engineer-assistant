import SwiftUI

/// A block of course markdown. Block-level structure (headings, fenced code, lists, tables)
/// must be laid out explicitly — `AttributedString`'s inline-only markdown flattens code blocks
/// into run-on text, which is what made the Concept panel unreadable.
enum MarkdownContentBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(String)          // verbatim — newlines and indentation preserved
    case bullets([String])
    case table([[String]])
}

enum MarkdownContent {
    static func parse(_ text: String) -> [MarkdownContentBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MarkdownContentBlock] = []
        var para: [String] = []
        var bullets: [String] = []

        func flushPara() {
            let s = para.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { blocks.append(.paragraph(s)) }
            para = []
        }
        func flushBullets() {
            if !bullets.isEmpty { blocks.append(.bullets(bullets)); bullets = [] }
        }
        func flushAll() { flushPara(); flushBullets() }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {                       // fenced code (verbatim)
                flushAll()
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                i += 1 // skip closing fence
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }

            if line.contains("|"), i + 1 < lines.count, isSeparatorRow(lines[i + 1]) {  // pipe table
                flushAll()
                var rows: [[String]] = [MarkdownTable.cells(line)]
                i += 2
                while i < lines.count, lines[i].contains("|"), !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(MarkdownTable.cells(lines[i])); i += 1
                }
                blocks.append(.table(rows))
                continue
            }

            if let (level, headingText) = heading(trimmed) {     // # heading
                flushAll()
                blocks.append(.heading(level: level, text: headingText))
                i += 1; continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {  // bullet list
                flushPara()
                bullets.append(String(trimmed.dropFirst(2)))
                i += 1; continue
            }

            if trimmed.isEmpty {                                 // paragraph break
                flushAll()
                i += 1; continue
            }

            flushBullets()
            para.append(line)
            i += 1
        }
        flushAll()
        return blocks
    }

    private static func heading(_ trimmed: String) -> (Int, String)? {
        var level = 0
        var idx = trimmed.startIndex
        while idx < trimmed.endIndex, trimmed[idx] == "#", level < 6 {
            level += 1
            idx = trimmed.index(after: idx)
        }
        guard level > 0, idx < trimmed.endIndex, trimmed[idx] == " " else { return nil }
        return (level, String(trimmed[trimmed.index(after: idx)...]).trimmingCharacters(in: .whitespaces))
    }

    private static func isSeparatorRow(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.contains("-") && t.allSatisfy { "-:| ".contains($0) }
    }
}

/// Renders course markdown with real block layout: aligned code blocks (small mono), headings,
/// bullets, tables, and inline-styled paragraphs — all in a small system font.
struct MarkdownContentView: View {
    let text: String
    var baseFont: Font = .callout

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownContent.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: MarkdownContentBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(text)
                .font(headingFont(level)).bold()
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph(let s):
            inlineText(s).font(baseFont).frame(maxWidth: .infinity, alignment: .leading)
        case .code(let code):
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").font(baseFont)
                        inlineText(item).font(baseFont).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        case .table(let rows):
            TableGrid(rows: rows, font: baseFont)
        }
    }

    private func inlineText(_ s: String) -> Text {
        if let attributed = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(s)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title3
        case 2: return .headline
        default: return .subheadline
        }
    }
}
