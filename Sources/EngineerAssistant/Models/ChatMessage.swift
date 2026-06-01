import Foundation

enum ChatRole: String, Codable {
    case user
    case assistant
}

enum ChatMode: String, Codable, CaseIterable, Identifiable {
    case ask
    case course
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .ask: return "Ask"
        case .course: return "Course"
        }
    }
}

struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    let role: ChatRole
    let mode: ChatMode
    var text: String
    let timestamp: Date

    init(id: UUID = UUID(), role: ChatRole, mode: ChatMode, text: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.mode = mode
        self.text = text
        self.timestamp = timestamp
    }
}
