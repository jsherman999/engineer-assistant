import SwiftUI

/// A run of markdown: plain text, or a parsed pipe-table whose cells should be column-aligned.
enum MarkdownBlock: Equatable {
    case text(String)
    case table([[String]])   // rows of cells; row 0 is the header
}

/// Splits markdown into text and pipe-table blocks. A table is a `| … |` row immediately
/// followed by a `|---|---|` separator, then any following `| … |` rows.
enum MarkdownTable {
    static func split(_ text: String) -> [MarkdownBlock] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var textBuf: [String] = []

        func flushText() {
            let s = textBuf.joined(separator: "\n")
            if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { blocks.append(.text(s)) }
            textBuf = []
        }

        var i = 0
        while i < lines.count {
            if isRow(lines[i]), i + 1 < lines.count, isSeparator(lines[i + 1]) {
                flushText()
                var rows: [[String]] = [cells(lines[i])]
                i += 2 // skip header + separator
                while i < lines.count, isRow(lines[i]) {
                    rows.append(cells(lines[i]))
                    i += 1
                }
                blocks.append(.table(rows))
                continue
            }
            textBuf.append(lines[i])
            i += 1
        }
        flushText()
        return blocks
    }

    private static func isRow(_ line: String) -> Bool {
        line.contains("|") && !line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func isSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.contains("-") && t.allSatisfy { "-:| ".contains($0) }
    }

    static func cells(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

/// Renders a parsed pipe-table with columns aligned to their content widths.
struct TableGrid: View {
    let rows: [[String]]
    var font: Font = .callout

    private var columnCount: Int { rows.map(\.count).max() ?? 0 }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                GridRow {
                    ForEach(0..<columnCount, id: \.self) { col in
                        Text(col < row.count ? row[col] : "")
                            .font(rowIdx == 0 ? font.weight(.semibold) : font)
                            .foregroundStyle(rowIdx == 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                            .textSelection(.enabled)
                            .gridColumnAlignment(.leading)
                    }
                }
                if rowIdx == 0 {
                    Divider().gridCellColumns(columnCount)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
