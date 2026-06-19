import Foundation

extension LogEvent {
    func string(_ key: String) -> String? { payload[key]?.value as? String }
    func int(_ key: String) -> Int? { payload[key]?.value as? Int }
    func bool(_ key: String) -> Bool? { payload[key]?.value as? Bool }
}

/// One recorded app session, reconstructed from the event log for the instructor view.
struct InstructorSession: Identifiable {
    let id: String
    let startedAt: Date
    let endedAt: Date?
    let events: [LogEvent]

    var duration: TimeInterval? { endedAt.map { $0.timeIntervalSince(startedAt) } }
    var chatCount: Int { events.filter { $0.type == .chatUser }.count }
    var challengesPassed: Int { events.filter { $0.type == .challengePass }.count }
    var challengesFailed: Int { events.filter { $0.type == .challengeFail }.count }
    var hintsUsed: Int { events.filter { $0.type == .hintUsed }.count }
    var coursesTouched: Int { Set(events.compactMap { $0.courseId }).count }
}

enum EventLogReader {
    static func readEvents(from url: URL = AppPaths.eventsFile) -> [LogEvent] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            try? decoder.decode(LogEvent.self, from: Data(line.utf8))
        }
    }

    /// Groups events into sessions, newest first.
    static func sessions(from events: [LogEvent]) -> [InstructorSession] {
        var order: [String] = []
        var grouped: [String: [LogEvent]] = [:]
        for event in events {
            if grouped[event.sessionId] == nil { order.append(event.sessionId) }
            grouped[event.sessionId, default: []].append(event)
        }
        return order.compactMap { id -> InstructorSession? in
            guard let group = grouped[id], !group.isEmpty else { return nil }
            let start = group.first(where: { $0.type == .sessionStart })?.timestamp ?? group.map(\.timestamp).min() ?? group[0].timestamp
            let end = group.first(where: { $0.type == .sessionEnd })?.timestamp
            return InstructorSession(id: id, startedAt: start, endedAt: end, events: group)
        }
        .sorted { $0.startedAt > $1.startedAt }
    }

    static func loadSessions(from url: URL = AppPaths.eventsFile) -> [InstructorSession] {
        sessions(from: readEvents(from: url))
    }
}
