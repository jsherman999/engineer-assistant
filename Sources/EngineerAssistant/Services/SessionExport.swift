import Foundation

/// Renders one session to a self-contained HTML file for sharing or archiving.
enum SessionExport {
    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static func html(for session: InstructorSession) -> String {
        var rows = ""
        for event in session.events {
            let t = timeFormatter.string(from: event.timestamp)
            let body = describe(event)
            rows += "<div class=\"row \(cssClass(event.type))\"><span class=\"ts\">\(t)</span><span class=\"type\">\(event.type.rawValue)</span><pre>\(escape(body))</pre></div>\n"
        }
        let durationStr = session.duration.map { "\(Int($0 / 60)) min" } ?? "—"
        return """
        <!doctype html><html><head><meta charset="utf-8"><title>Session \(escape(session.id))</title>
        <style>
          body { font: 14px -apple-system, sans-serif; margin: 24px; color: #222; }
          h1 { font-size: 18px; } .meta { color: #666; margin-bottom: 16px; }
          .row { display: grid; grid-template-columns: 70px 130px 1fr; gap: 8px; padding: 4px 0; border-top: 1px solid #eee; }
          .ts { color: #999; } .type { color: #555; font-weight: 600; }
          pre { margin: 0; white-space: pre-wrap; font: 12px ui-monospace, monospace; }
          .chat_user pre { color: #0a58ca; } .chat_assistant pre { color: #198754; }
          .shell_stdout pre, .shell_stdin pre { color: #444; }
          .challenge_pass pre { color: #198754; } .challenge_fail pre { color: #b02a37; }
        </style></head><body>
        <h1>Engineer Assistant — Session</h1>
        <div class="meta">\(dateFormatter.string(from: session.startedAt)) · duration \(durationStr) ·
        \(session.chatCount) chats · \(session.challengesPassed) passed / \(session.challengesFailed) failed · \(session.hintsUsed) hints</div>
        \(rows)
        </body></html>
        """
    }

    static func write(_ session: InstructorSession) throws -> URL {
        let url = AppPaths.exportsDir.appendingPathComponent("session-\(session.id).html")
        try html(for: session).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Human-readable one-liner for an event, used by both the export and the timeline.
    static func describe(_ e: LogEvent) -> String {
        switch e.type {
        case .sessionStart: return "session started"
        case .sessionEnd: return "session ended (\(e.string("reason") ?? "?"))"
        case .chatUser: return e.string("text") ?? ""
        case .chatAssistant: return e.string("text") ?? ""
        case .shellStdin, .shellStdout, .shellStderr: return e.string("text") ?? ""
        case .lessonStart: return "started lesson: \(e.string("lesson_title") ?? "?")"
        case .lessonComplete: return "finished lesson: \(e.string("lesson_title") ?? "?")"
        case .challengeAttempt: return "attempt: \(e.string("command") ?? "")"
        case .challengePass: return "PASS (\(e.string("verify_type") ?? "?")): \(e.string("evidence") ?? "")"
        case .challengeFail: return "not yet (\(e.string("verify_type") ?? "?")): \(e.string("reason") ?? "")"
        case .hintUsed: return "hint revealed"
        case .skipUsed: return "skipped \(e.string("from_panel") ?? "")"
        case .courseGenerated: return "generated course: \(e.string("title") ?? e.string("subject") ?? "?")"
        case .agentCommand:
            let mark = (e.bool("allowed") ?? false) ? "" : " [refused]"
            return "agent ran\(mark): \(e.string("command") ?? "") → \(e.string("output") ?? "")"
        }
    }

    static func cssClass(_ type: EventType) -> String { type.rawValue }
}
