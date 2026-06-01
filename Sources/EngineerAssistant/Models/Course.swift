import Foundation

enum CourseEnvironment: String, Codable {
    case macos
    case linux
}

enum VerifyType: String, Codable {
    case exitCode = "exit_code"
    case stdoutRegex = "stdout_regex"
    case fileExists = "file_exists"
    case fileContains = "file_contains"
    case llmJudge = "llm_judge"
}

struct VerifyCheck: Codable, Equatable {
    let type: VerifyType
    let value: String?
    let path: String?
    let exitCode: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case value
        case path
        case exitCode = "exit_code"
    }
}

struct Demo: Codable, Equatable {
    let command: String
    let expectedOutput: String
    let explanation: String

    enum CodingKeys: String, CodingKey {
        case command
        case expectedOutput = "expected_output"
        case explanation
    }
}

struct Challenge: Codable, Equatable {
    let task: String
    let starterState: String?
    let verify: VerifyCheck

    enum CodingKeys: String, CodingKey {
        case task
        case starterState = "starter_state"
        case verify
    }
}

struct Lesson: Codable, Equatable, Identifiable {
    var id: String { title }
    let title: String
    let conceptMd: String
    let demos: [Demo]
    let practicePrompt: String
    let challenge: Challenge

    enum CodingKeys: String, CodingKey {
        case title
        case conceptMd = "concept_md"
        case demos
        case practicePrompt = "practice_prompt"
        case challenge
    }
}

struct CourseDraft: Codable {
    let title: String
    let description: String
    let estimatedMinutes: Int
    let environment: CourseEnvironment
    let prerequisites: [String]
    let lessons: [Lesson]
    let finalChallenge: Challenge?

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case estimatedMinutes = "estimated_minutes"
        case environment
        case prerequisites
        case lessons
        case finalChallenge = "final_challenge"
    }
}

struct Course: Codable, Identifiable, Equatable {
    let id: String
    let subject: String
    let createdAt: Date
    let title: String
    let description: String
    let estimatedMinutes: Int
    let environment: CourseEnvironment
    let prerequisites: [String]
    let lessons: [Lesson]
    let finalChallenge: Challenge?

    enum CodingKeys: String, CodingKey {
        case id
        case subject
        case createdAt = "created_at"
        case title
        case description
        case estimatedMinutes = "estimated_minutes"
        case environment
        case prerequisites
        case lessons
        case finalChallenge = "final_challenge"
    }

    init(id: String = UUID().uuidString, subject: String, createdAt: Date = Date(), draft: CourseDraft) {
        self.id = id
        self.subject = subject
        self.createdAt = createdAt
        self.title = draft.title
        self.description = draft.description
        self.estimatedMinutes = draft.estimatedMinutes
        self.environment = draft.environment
        self.prerequisites = draft.prerequisites
        self.lessons = draft.lessons
        self.finalChallenge = draft.finalChallenge
    }
}

enum CourseSubject {
    static func slug(for subject: String) -> String {
        let lower = subject.lowercased()
        let allowed = CharacterSet.lowercaseLetters.union(.decimalDigits)
        var out = ""
        var prevDash = false
        for scalar in lower.unicodeScalars {
            if allowed.contains(scalar) {
                out.unicodeScalars.append(scalar)
                prevDash = false
            } else if !prevDash {
                out.append("-")
                prevDash = true
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return String(trimmed.prefix(80))
    }
}
