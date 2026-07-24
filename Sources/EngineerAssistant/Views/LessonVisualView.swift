import SwiftUI

/// Renders a lesson's optional diagram. One entry point, one renderer per `type`, so adding a
/// new kind of diagram is a case here rather than a change to every lesson that wants one.
struct LessonVisualView: View {
    let visual: LessonVisual

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            if let caption = visual.caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var content: some View {
        switch visual.type {
        case "tree":
            PathTreeView(paths: visual.items ?? [])
        case "pipeline":
            PipelineDiagramView(stages: visual.stages ?? [])
        case "permissions":
            PermissionGridView(mode: visual.mode ?? "rw-r--r--", path: visual.path ?? "file")
        case "flow":
            FlowDiagramView(steps: visual.items ?? [])
        default:
            EmptyView()
        }
    }
}

// MARK: - Tree

/// Turns a flat list of paths into an indented tree. Used both for course-authored diagrams and
/// for the live sandbox view, so paths are the only input either one has to produce.
struct PathTreeView: View {
    let paths: [String]
    /// Paths that appeared since the last refresh — briefly tinted so a `mkdir` is visible.
    /// Compared without trailing slashes, since callers pass directories either way.
    var highlighted: Set<String> = []

    private var normalizedHighlights: Set<String> {
        Set(highlighted.map { $0.hasSuffix("/") ? String($0.dropLast()) : $0 })
    }

    private struct Row: Identifiable {
        let id: String
        let depth: Int
        let name: String
        let isDirectory: Bool
    }

    /// Expands `a/b/c.txt` into rows for `a`, `a/b`, and `a/b/c.txt`, deduplicated and sorted so
    /// directories lead each level. A trailing slash marks an explicitly-empty directory.
    private var rows: [Row] {
        var directories = Set<String>()
        var leaves: [String: Bool] = [:] // path -> isDirectory

        for raw in paths {
            let isDir = raw.hasSuffix("/")
            let clean = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !clean.isEmpty else { continue }
            let components = clean.split(separator: "/").map(String.init)
            for i in 0..<components.count {
                let partial = components[0...i].joined(separator: "/")
                if i < components.count - 1 {
                    directories.insert(partial)
                } else {
                    leaves[partial] = isDir
                }
            }
        }
        for dir in directories where leaves[dir] != true { leaves[dir] = true }

        return leaves.keys.sorted().map { path in
            let components = path.split(separator: "/").map(String.init)
            return Row(id: path,
                       depth: components.count - 1,
                       name: components.last ?? path,
                       isDirectory: leaves[path] ?? false)
        }
    }

    var body: some View {
        let highlights = normalizedHighlights
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(rows) { row in
                HStack(spacing: 6) {
                    Image(systemName: row.isDirectory ? "folder.fill" : "doc.text")
                        .font(.caption)
                        .foregroundStyle(row.isDirectory ? Theme.concept : Color.secondary)
                        .frame(width: 14)
                    Text(row.name)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(highlights.contains(row.id) ? Theme.demos : .primary)
                    Spacer(minLength: 0)
                }
                .padding(.leading, CGFloat(row.depth) * 16)
                .padding(.vertical, 1)
                .padding(.horizontal, 4)
                .background(
                    highlights.contains(row.id) ? Theme.demos.opacity(0.16) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 4)
                )
            }
            if rows.isEmpty {
                Text("(empty)").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .animation(.easeOut(duration: 0.25), value: highlighted)
    }
}

// MARK: - Pipeline

/// `a | b | c` as boxes and arrows, where each stage can be opened to see what it emits.
/// Seeing the data change shape between stages is the thing that makes pipes click.
struct PipelineDiagramView: View {
    let stages: [PipelineStage]
    @State private var selected: Int? = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Wraps rather than scrolls: a three-stage pipeline should be readable at once.
            FlowLayout(spacing: 6) {
                ForEach(Array(stages.enumerated()), id: \.offset) { idx, stage in
                    HStack(spacing: 6) {
                        stageBox(idx: idx, stage: stage)
                        if idx < stages.count - 1 {
                            Image(systemName: "arrow.right")
                                .font(.caption.bold())
                                .foregroundStyle(Theme.practice)
                        }
                    }
                }
            }

            if let selected, selected < stages.count {
                let stage = stages[selected]
                VStack(alignment: .leading, spacing: 4) {
                    Text("After stage \(selected + 1) — `\(stage.command)`")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    if let note = stage.note, !note.isEmpty {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                    if let output = stage.output, !output.isEmpty {
                        Text(output)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Theme.codeBackground)
                            .foregroundStyle(Theme.codeForeground)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: selected)
    }

    private func stageBox(idx: Int, stage: PipelineStage) -> some View {
        Button {
            selected = (selected == idx) ? nil : idx
        } label: {
            Text(stage.command)
                .font(.system(.caption, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(selected == idx ? Theme.practice.opacity(0.22) : Color.secondary.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(selected == idx ? Theme.practice : Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help("Show what this stage produces")
    }
}

// MARK: - Permissions

/// The `rwxr-xr--` ↔ `754` grid, clickable. Toggling a bit and watching the octal change is far
/// more direct than being told the mapping.
struct PermissionGridView: View {
    let mode: String
    let path: String

    @State private var bits: [Bool] = []

    private static let classes = ["Owner", "Group", "Everyone"]
    private static let flags = ["r", "w", "x"]

    private var octal: String {
        stride(from: 0, to: 9, by: 3).map { start in
            let value = (bits[start] ? 4 : 0) + (bits[start + 1] ? 2 : 0) + (bits[start + 2] ? 1 : 0)
            return String(value)
        }.joined()
    }

    private var symbolic: String {
        (0..<9).map { bits[$0] ? Self.flags[$0 % 3] : "-" }.joined()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(Array(Self.classes.enumerated()), id: \.offset) { classIdx, className in
                    VStack(spacing: 5) {
                        Text(className).font(.caption2.bold()).foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            ForEach(0..<3, id: \.self) { flagIdx in
                                bitButton(index: classIdx * 3 + flagIdx, label: Self.flags[flagIdx])
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Text(symbolic).font(.system(.body, design: .monospaced).bold())
                Text("=").foregroundStyle(.secondary)
                Text(octal).font(.system(.body, design: .monospaced).bold()).foregroundStyle(Theme.challenge)
                Spacer()
                Text("chmod \(octal) \(path)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Text(summary).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onAppear { if bits.isEmpty { bits = Self.parse(mode) } }
    }

    /// Plain-language readout, because "who can do what" is the actual lesson.
    private var summary: String {
        var lines: [String] = []
        for (i, name) in Self.classes.enumerated() {
            var can: [String] = []
            if bits[i * 3] { can.append("read") }
            if bits[i * 3 + 1] { can.append("write") }
            if bits[i * 3 + 2] { can.append("run") }
            lines.append("\(name): \(can.isEmpty ? "nothing" : can.joined(separator: ", "))")
        }
        return lines.joined(separator: " · ")
    }

    private func bitButton(index: Int, label: String) -> some View {
        Button {
            bits[index].toggle()
        } label: {
            Text(bits[index] ? label : "-")
                .font(.system(.body, design: .monospaced).bold())
                .frame(width: 30, height: 30)
                .background(bits[index] ? Theme.challenge.opacity(0.22) : Color.secondary.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(bits[index] ? Theme.challenge : Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help(bits[index] ? "Turn off" : "Turn on")
    }

    /// Accepts `rwxr-xr--`, a leading file-type char (`-rwxr-xr--`), or an octal like `754`.
    static func parse(_ mode: String) -> [Bool] {
        let trimmed = mode.trimmingCharacters(in: .whitespaces)
        if trimmed.count == 3, trimmed.allSatisfy(\.isNumber) {
            return trimmed.flatMap { char -> [Bool] in
                let value = Int(String(char)) ?? 0
                return [value & 4 != 0, value & 2 != 0, value & 1 != 0]
            }
        }
        let symbols = Array(trimmed.count == 10 ? String(trimmed.dropFirst()) : trimmed)
        guard symbols.count == 9 else { return Array(repeating: false, count: 9) }
        return symbols.map { $0 != "-" }
    }
}

// MARK: - Flow

/// Ordered steps as chips with arrows — for sequences like "browser → resolver → server".
struct FlowDiagramView: View {
    let steps: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                HStack(spacing: 6) {
                    Text(step)
                        .font(.caption)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Theme.concept.opacity(0.14))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.concept.opacity(0.35)))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    if idx < steps.count - 1 {
                        Image(systemName: "arrow.right")
                            .font(.caption2.bold()).foregroundStyle(Theme.concept)
                    }
                }
            }
        }
    }
}

// MARK: - Layout helper

/// Wraps subviews onto as many lines as they need. Diagrams have to survive a narrow left panel
/// without introducing a horizontal scroll the student has to discover.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
