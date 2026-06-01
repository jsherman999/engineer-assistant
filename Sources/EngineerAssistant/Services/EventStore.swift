import Foundation

protocol EventStore {
    func startSession() async throws -> String
    func endSession(_ id: String, reason: String) async throws
    func append(_ event: LogEvent) async throws
}

actor JSONLEventStore: EventStore {
    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()

    init(fileURL: URL = AppPaths.eventsFile) {
        self.fileURL = fileURL
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
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
        let data = try encoder.encode(event)
        let line = data + Data([0x0a])
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }
}
