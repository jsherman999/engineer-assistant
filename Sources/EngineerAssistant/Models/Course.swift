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

/// One annotated piece of a command — `-r`, `--color`, a path — with what it means. Renders as
/// clickable tokens under the command so a student can take `tar -xzf` apart without leaving
/// the lesson, instead of memorising it as a magic incantation.
struct CommandPart: Codable, Equatable {
    let token: String
    let meaning: String
}

struct Demo: Codable, Equatable {
    let command: String
    let expectedOutput: String
    let explanation: String
    /// Per-token breakdown of `command`. Optional: older cached courses have none.
    let parts: [CommandPart]?

    enum CodingKeys: String, CodingKey {
        case command
        case expectedOutput = "expected_output"
        case explanation
        case parts
    }
}

/// A diagram a lesson can ask for instead of explaining a structural idea in prose. The player
/// owns the renderers; the course only picks a `type` and supplies its data. Adding a new kind
/// of diagram means adding one renderer here, not changing every lesson.
struct LessonVisual: Codable, Equatable {
    /// "tree" | "pipeline" | "permissions" | "flow"
    let type: String
    let caption: String?
    /// `tree`: paths like `notes/todo.txt`. `flow`: ordered step labels.
    let items: [String]?
    /// `pipeline`: each stage of a `a | b | c` command, with what it emits.
    let stages: [PipelineStage]?
    /// `permissions`: a mode like `rwxr-xr--` and the file it belongs to.
    let mode: String?
    let path: String?
}

struct PipelineStage: Codable, Equatable {
    let command: String
    let output: String?
    let note: String?
}

/// A file the sandbox must already contain before the student starts a challenge, so tasks
/// like "fix the broken script" or "count the lines in data.txt" have something to act on.
struct StarterFile: Codable, Equatable {
    let path: String
    let content: String
    /// Set for scripts the student is meant to run (chmod +x on macOS, container `chmod` on Linux).
    let executable: Bool?
}

struct Challenge: Codable, Equatable {
    let task: String
    /// Prose describing the starting point, shown to the student.
    let starterState: String?
    /// Files actually written into the sandbox before the lesson begins.
    let starterFiles: [StarterFile]?
    let verify: VerifyCheck

    enum CodingKeys: String, CodingKey {
        case task
        case starterState = "starter_state"
        case starterFiles = "starter_files"
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
    /// Two or three takeaway lines shown after the challenge — the fifth standard panel.
    let recapMd: String?
    /// Optional diagram rendered next to the concept.
    let visual: LessonVisual?

    enum CodingKeys: String, CodingKey {
        case title
        case conceptMd = "concept_md"
        case demos
        case practicePrompt = "practice_prompt"
        case challenge
        case recapMd = "recap_md"
        case visual
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
