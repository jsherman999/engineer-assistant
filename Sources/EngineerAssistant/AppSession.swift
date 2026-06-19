import Foundation
import SwiftUI

@MainActor
final class AppSession: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var currentMode: ChatMode = .ask
    @Published var isSending: Bool = false
    @Published var apiKeyConfigured: Bool = false
    @Published var sessionId: String? = nil
    @Published var lastError: String? = nil
    @Published var activeCourse: Course? = nil
    @Published var currentLessonIdx: Int = 0
    @Published var courses: [Course] = []
    @Published var terminal: MacOSTerminalController? = nil
    @Published var isChecking: Bool = false
    @Published var challengeOutcome: VerifyOutcome? = nil
    @Published var hintRevealed: Bool = false

    private let claude = ClaudeClient()
    private let courseGenerator = CourseGenerator()
    private let courseStore: CourseStore = FileCourseStore()
    private let eventStore: EventStore = JSONLEventStore()
    private lazy var verifier = Verifier(claude: claude)

    func start() async {
        refreshAPIKeyStatus()
        courses = courseStore.listAll()
        do {
            let id = try await eventStore.startSession()
            self.sessionId = id
        } catch {
            self.lastError = "Failed to start session: \(error.localizedDescription)"
        }
    }

    func refreshAPIKeyStatus() {
        apiKeyConfigured = !(Keychain.get(KeychainKeys.anthropicAPIKey) ?? "").isEmpty
    }

    func setAPIKey(_ key: String) throws {
        try Keychain.set(key, for: KeychainKeys.anthropicAPIKey)
        refreshAPIKeyStatus()
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        guard let sessionId else { return }

        let mode = currentMode
        let userMsg = ChatMessage(role: .user, mode: mode, text: trimmed)
        messages.append(userMsg)
        isSending = true
        lastError = nil

        Task {
            await logChatEvent(.chatUser, mode: mode, text: trimmed, sessionId: sessionId, courseId: nil)
            if mode == .ask {
                await handleAsk(sessionId: sessionId)
            } else {
                await handleCourse(subject: trimmed, sessionId: sessionId)
            }
            isSending = false
        }
    }

    private func handleAsk(sessionId: String) async {
        let assistantMsg = ChatMessage(role: .assistant, mode: .ask, text: "")
        messages.append(assistantMsg)
        let assistantId = assistantMsg.id
        let history = messages.dropLast()
        do {
            let stream = claude.streamAskResponse(history: Array(history))
            for try await chunk in stream {
                appendChunk(to: assistantId, text: chunk.text)
            }
            let finalText = messages.first(where: { $0.id == assistantId })?.text ?? ""
            await logChatEvent(.chatAssistant, mode: .ask, text: finalText, sessionId: sessionId, courseId: nil)
        } catch {
            lastError = error.localizedDescription
            appendChunk(to: assistantId, text: "\n\n_Error: \(error.localizedDescription)_")
        }
    }

    private func handleCourse(subject: String, sessionId: String) async {
        do {
            let result = try await courseGenerator.generate(subject: subject)
            let course = result.course

            await logCourseGenerated(course: course, wasCached: result.wasCached, sessionId: sessionId)

            let summary = result.wasCached
                ? "Loaded cached course: **\(course.title)** — \(course.lessons.count) lessons."
                : "Generated course: **\(course.title)** — \(course.lessons.count) lessons."
            let reply = ChatMessage(role: .assistant, mode: .course, text: summary)
            messages.append(reply)
            await logChatEvent(.chatAssistant, mode: .course, text: summary, sessionId: sessionId, courseId: course.id)

            courses = courseStore.listAll()
            openCourse(course)
        } catch {
            lastError = error.localizedDescription
            let reply = ChatMessage(role: .assistant, mode: .course, text: "Could not generate course: \(error.localizedDescription)")
            messages.append(reply)
        }
    }

    func openCourse(_ course: Course) {
        activeCourse = course
        currentLessonIdx = 0
        resetChallengeState()
        startTerminalIfSupported(for: course)
        Task {
            guard let sessionId else { return }
            await logLessonStart(course: course, idx: 0, sessionId: sessionId)
        }
    }

    func exitCourse() {
        terminal?.stop()
        terminal = nil
        guard let course = activeCourse, let sessionId else {
            activeCourse = nil
            currentLessonIdx = 0
            return
        }
        Task {
            await logLessonComplete(course: course, idx: currentLessonIdx, sessionId: sessionId, finished: false)
        }
        activeCourse = nil
        currentLessonIdx = 0
    }

    private func startTerminalIfSupported(for course: Course) {
        terminal?.stop()
        terminal = nil
        guard course.environment == .macos, let sessionId else { return }
        do {
            let controller = try MacOSTerminalController(
                courseId: course.id,
                sessionId: sessionId,
                eventStore: eventStore
            )
            try controller.start()
            terminal = controller
        } catch {
            lastError = "Sandbox failed to start: \(error.localizedDescription)"
            terminal = nil
        }
    }

    func nextLesson() {
        guard let course = activeCourse, currentLessonIdx < course.lessons.count - 1 else { return }
        let prevIdx = currentLessonIdx
        let nextIdx = currentLessonIdx + 1
        currentLessonIdx = nextIdx
        resetChallengeState()
        Task {
            guard let sessionId else { return }
            await logLessonComplete(course: course, idx: prevIdx, sessionId: sessionId, finished: true)
            await logLessonStart(course: course, idx: nextIdx, sessionId: sessionId)
        }
    }

    func previousLesson() {
        guard currentLessonIdx > 0 else { return }
        currentLessonIdx -= 1
        resetChallengeState()
    }

    private func resetChallengeState() {
        challengeOutcome = nil
        hintRevealed = false
        isChecking = false
    }

    func checkCurrentChallenge() {
        guard let course = activeCourse, let sessionId,
              currentLessonIdx < course.lessons.count else { return }
        let challenge = course.lessons[currentLessonIdx].challenge
        guard let terminal else {
            challengeOutcome = VerifyOutcome(passed: false, detail: "Start the sandbox shell first.")
            return
        }

        isChecking = true
        challengeOutcome = nil
        hintRevealed = false

        let context = VerifyContext(
            lastExitCode: terminal.lastExitCode,
            lastStdout: terminal.lastStdout,
            sandboxDir: terminal.workingDirectory,
            transcript: terminal.transcript
        )
        let command = terminal.lastCommand ?? ""
        let idx = currentLessonIdx

        Task {
            await logChallengeAttempt(course: course, idx: idx, command: command, sessionId: sessionId)
            let outcome = await verifier.verify(challenge.verify, context: context)
            challengeOutcome = outcome
            isChecking = false
            if outcome.passed {
                await logChallengeResult(.challengePass, course: course, idx: idx, verify: challenge.verify, detail: outcome.detail, sessionId: sessionId)
            } else {
                await logChallengeResult(.challengeFail, course: course, idx: idx, verify: challenge.verify, detail: outcome.detail, sessionId: sessionId)
            }
        }
    }

    func revealHint() {
        hintRevealed = true
        guard let course = activeCourse, let sessionId, currentLessonIdx < course.lessons.count else { return }
        let idx = currentLessonIdx
        Task { await logHintUsed(course: course, idx: idx, sessionId: sessionId) }
    }

    private func appendChunk(to id: UUID, text: String) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].text += text
    }

    private func logChatEvent(_ type: EventType, mode: ChatMode, text: String, sessionId: String, courseId: String?) async {
        let event = LogEvent(
            sessionId: sessionId,
            timestamp: Date(),
            type: type,
            courseId: courseId,
            lessonIdx: nil,
            payload: [
                "text": AnyCodable(text),
                "mode": AnyCodable(mode.rawValue)
            ]
        )
        try? await eventStore.append(event)
    }

    private func logCourseGenerated(course: Course, wasCached: Bool, sessionId: String) async {
        let event = LogEvent(
            sessionId: sessionId,
            timestamp: Date(),
            type: .courseGenerated,
            courseId: course.id,
            lessonIdx: nil,
            payload: [
                "subject": AnyCodable(course.subject),
                "title": AnyCodable(course.title),
                "environment": AnyCodable(course.environment.rawValue),
                "lesson_count": AnyCodable(course.lessons.count),
                "was_cached": AnyCodable(wasCached)
            ]
        )
        try? await eventStore.append(event)
    }

    private func logLessonStart(course: Course, idx: Int, sessionId: String) async {
        guard idx < course.lessons.count else { return }
        let event = LogEvent(
            sessionId: sessionId,
            timestamp: Date(),
            type: .lessonStart,
            courseId: course.id,
            lessonIdx: idx,
            payload: ["lesson_title": AnyCodable(course.lessons[idx].title)]
        )
        try? await eventStore.append(event)
    }

    private func logChallengeAttempt(course: Course, idx: Int, command: String, sessionId: String) async {
        let event = LogEvent(
            sessionId: sessionId,
            timestamp: Date(),
            type: .challengeAttempt,
            courseId: course.id,
            lessonIdx: idx,
            payload: ["command": AnyCodable(command)]
        )
        try? await eventStore.append(event)
    }

    private func logChallengeResult(_ type: EventType, course: Course, idx: Int, verify: VerifyCheck, detail: String, sessionId: String) async {
        let detailKey = type == .challengePass ? "evidence" : "reason"
        let event = LogEvent(
            sessionId: sessionId,
            timestamp: Date(),
            type: type,
            courseId: course.id,
            lessonIdx: idx,
            payload: [
                "verify_type": AnyCodable(verify.type.rawValue),
                detailKey: AnyCodable(detail)
            ]
        )
        try? await eventStore.append(event)
    }

    private func logHintUsed(course: Course, idx: Int, sessionId: String) async {
        let event = LogEvent(
            sessionId: sessionId,
            timestamp: Date(),
            type: .hintUsed,
            courseId: course.id,
            lessonIdx: idx,
            payload: ["hint_text": AnyCodable("revealed")]
        )
        try? await eventStore.append(event)
    }

    private func logLessonComplete(course: Course, idx: Int, sessionId: String, finished: Bool) async {
        guard idx < course.lessons.count else { return }
        let event = LogEvent(
            sessionId: sessionId,
            timestamp: Date(),
            type: .lessonComplete,
            courseId: course.id,
            lessonIdx: idx,
            payload: [
                "lesson_title": AnyCodable(course.lessons[idx].title),
                "finished": AnyCodable(finished)
            ]
        )
        try? await eventStore.append(event)
    }
}
