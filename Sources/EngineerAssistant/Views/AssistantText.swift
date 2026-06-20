import Foundation

/// A parsed piece of an assistant message: prose, or a run of command/code lines.
enum AssistantSegment: Equatable {
    case prose(String)
    case commands([String])
}

/// Splits an assistant message into prose and command segments. Triple-backtick fences (and
/// their optional language tag) and leading `$ `/`❯ ` prompts are stripped; consecutive
/// command lines group into one block so they render as a single mini-terminal.
enum AssistantText {
    static func segments(_ text: String) -> [AssistantSegment] {
        var result: [AssistantSegment] = []
        var prose: [String] = []
        var commands: [String] = []
        var inFence = false

        func flushProse() {
            let joined = prose.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(.prose(joined))
            }
            prose = []
        }
        func flushCommands() {
            let kept = commands.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if !kept.isEmpty { result.append(.commands(kept)) }
            commands = []
        }

        for rawLine in text.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inFence { flushCommands() } else { flushProse() }
                inFence.toggle()
                continue
            }
            if inFence {
                commands.append(rawLine)
            } else if trimmed.hasPrefix("$ ") || trimmed.hasPrefix("❯ ") {
                flushProse()
                commands.append(String(trimmed.dropFirst(2)))
            } else {
                flushCommands()
                prose.append(rawLine)
            }
        }
        flushProse()
        flushCommands()
        return result
    }
}
