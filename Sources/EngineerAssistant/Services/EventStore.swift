import Foundation

protocol EventStore {
    func startSession() async throws -> String
    func endSession(_ id: String, reason: String) async throws
    func append(_ event: LogEvent) async throws
    /// Writes a `session_end` without awaiting. Needed on app termination, which does not wait
    /// for outstanding async work — an awaited write would simply never land.
    nonisolated func endSessionSynchronously(_ id: String, reason: String)
}

actor JSONLEventStore: EventStore {
    private let fileURL: URL

    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }

    private let encoder = JSONLEventStore.makeEncoder()

    init(fileURL: URL = AppPaths.eventsFile) {
        self.fileURL = fileURL
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
    }

    nonisolated func endSessionSynchronously(_ id: String, reason: String) {
        let event = LogEvent(
            sessionId: id, timestamp: Date(), type: .sessionEnd,
            courseId: nil, lessonIdx: nil, payload: ["reason": AnyCodable(reason)]
        )
        try? Self.appendLine(event, to: fileURL, encoder: Self.makeEncoder())
    }

    /// The one place a line is written, shared by the actor-isolated and synchronous paths.
    private static func appendLine(_ event: LogEvent, to url: URL, encoder: JSONEncoder) throws {
        let line = try encoder.encode(event) + Data([0x0a])
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    func startSession() async throws -> String {
        let id = UUID().uuidString
        try await write(LogEvent(
            sessionId: id,
            timestamp: Date(),
            type: .sessionStart,
            courseId: nil,
            lessonIdx: nil,
            payload: [:]
        ))
        return id
    }

    func endSession(_ id: String, reason: String) async throws {
        try await write(LogEvent(
            sessionId: id,
            timestamp: Date(),
            type: .sessionEnd,
            courseId: nil,
            lessonIdx: nil,
            payload: ["reason": AnyCodable(reason)]
        ))
    }

    func append(_ event: LogEvent) async throws {
        try await write(event)
    }

    private func write(_ event: LogEvent) async throws {
        try Self.appendLine(event, to: fileURL, encoder: encoder)
    }
}
