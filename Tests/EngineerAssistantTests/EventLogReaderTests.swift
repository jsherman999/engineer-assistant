import XCTest
@testable import EngineerAssistant

final class EventLogReaderTests: XCTestCase {
    private func writeLog(_ events: [LogEvent]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("log-\(UUID().uuidString).jsonl")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let lines = try events.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func event(_ session: String, _ type: EventType, at: Date, course: String? = nil, payload: [String: AnyCodable] = [:]) -> LogEvent {
        LogEvent(sessionId: session, timestamp: at, type: type, courseId: course, lessonIdx: nil, payload: payload)
    }

    func testGroupsEventsIntoSessionsNewestFirst() throws {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let events = [
            event("s1", .sessionStart, at: t0),
            event("s1", .chatUser, at: t0.addingTimeInterval(1), payload: ["text": AnyCodable("hi"), "mode": AnyCodable("ask")]),
            event("s1", .sessionEnd, at: t0.addingTimeInterval(60), payload: ["reason": AnyCodable("quit")]),
            event("s2", .sessionStart, at: t0.addingTimeInterval(3_600)),
            event("s2", .challengePass, at: t0.addingTimeInterval(3_650), course: "c1", payload: ["verify_type": AnyCodable("file_exists"), "evidence": AnyCodable("ok")]),
        ]
        let url = try writeLog(events)
        defer { try? FileManager.default.removeItem(at: url) }

        let sessions = EventLogReader.loadSessions(from: url)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].id, "s2", "newest session first")
        XCTAssertEqual(sessions[1].id, "s1")

        let s1 = sessions[1]
        XCTAssertEqual(s1.chatCount, 1)
        XCTAssertEqual(s1.duration, 60)
        XCTAssertNotNil(s1.endedAt)

        let s2 = sessions[0]
        XCTAssertEqual(s2.challengesPassed, 1)
        XCTAssertEqual(s2.coursesTouched, 1)
        XCTAssertNil(s2.endedAt, "no session_end yet")
    }

    func testEmptyOrMissingFile() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString).jsonl")
        XCTAssertEqual(EventLogReader.loadSessions(from: missing).count, 0)
    }

    func testExportHTMLContainsContentAndEscapes() throws {
        let t0 = Date(timeIntervalSince1970: 2_000)
        let events = [
            event("s1", .sessionStart, at: t0),
            event("s1", .chatUser, at: t0.addingTimeInterval(1), payload: ["text": AnyCodable("compare a < b & c"), "mode": AnyCodable("ask")]),
        ]
        let session = EventLogReader.sessions(from: events)[0]
        let html = SessionExport.html(for: session)
        XCTAssertTrue(html.contains("Engineer Assistant"))
        XCTAssertTrue(html.contains("a &lt; b &amp; c"), "HTML special chars escaped")
        XCTAssertFalse(html.contains("a < b & c"))
    }
}
