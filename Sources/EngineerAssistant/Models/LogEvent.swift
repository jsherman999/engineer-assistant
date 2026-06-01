import Foundation

enum EventType: String, Codable {
    case sessionStart = "session_start"
    case sessionEnd = "session_end"
    case chatUser = "chat_user"
    case chatAssistant = "chat_assistant"
    case shellStdin = "shell_stdin"
    case shellStdout = "shell_stdout"
    case shellStderr = "shell_stderr"
    case lessonStart = "lesson_start"
    case lessonComplete = "lesson_complete"
    case challengeAttempt = "challenge_attempt"
    case challengePass = "challenge_pass"
    case challengeFail = "challenge_fail"
    case hintUsed = "hint_used"
    case skipUsed = "skip_used"
    case courseGenerated = "course_generated"
}

struct LogEvent: Codable {
    let sessionId: String
    let timestamp: Date
    let type: EventType
    let courseId: String?
    let lessonIdx: Int?
    let payload: [String: AnyCodable]

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case timestamp = "ts"
        case type
        case courseId = "course_id"
        case lessonIdx = "lesson_idx"
        case payload
    }
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { value = NSNull() }
        else if let b = try? c.decode(Bool.self) { value = b }
        else if let i = try? c.decode(Int.self) { value = i }
        else if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self) { value = s }
        else if let a = try? c.decode([AnyCodable].self) { value = a.map(\.value) }
        else if let o = try? c.decode([String: AnyCodable].self) { value = o.mapValues(\.value) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported value") }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case is NSNull: try c.encodeNil()
        case let b as Bool: try c.encode(b)
        case let i as Int: try c.encode(i)
        case let d as Double: try c.encode(d)
        case let s as String: try c.encode(s)
        case let a as [Any]: try c.encode(a.map(AnyCodable.init))
        case let o as [String: Any]: try c.encode(o.mapValues(AnyCodable.init))
        default:
            throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Unsupported value"))
        }
    }
}
