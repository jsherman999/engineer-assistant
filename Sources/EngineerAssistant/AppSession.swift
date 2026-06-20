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
    @Published var terminal: SandboxTerminalController? = nil
    @Published var isChecking: Bool = false
    @Published var challengeOutcome: VerifyOutcome? = nil
    @Published var hintRevealed: Bool = false
    @Published var hintText: String? = nil
    @Published var hintLoading: Bool = false
    @Published var containerRuntime: ContainerRuntime? = nil
    @Published var isRegenerating: Bool = false
    @Published var containerStarting: Bool = false
    @Published var containerStartError: String? = nil
    @Published var showLessonChat: Bool = false
    @Published var lessonChat: [ChatMessage] = []
    @Published var lessonChatSending: Bool = false
    /// Bumped whenever saved lesson results change, so result views re-render.
    @Published private(set) var resultsRevision: Int = 0

    private let claude = ClaudeClient()
    private let courseGenerator = CourseGenerator()
    private let courseStore: CourseStore = FileCourseStore()
    private let eventStore: EventStore = JSONLEventStore()
    private let progressStore: ProgressStore = FileProgressStore()
    private let resultsStore: ResultsStore = FileResultsStore()
    private lazy var verifier = Verifier(claude: claude)

    func progress(for courseId: String) -> CourseProgress? {
        progressStore.progress(for: courseId)
    }

    func results(for courseId: String) -> CourseResults? {
        resultsStore.results(for: courseId)
    }

    func allResults() -> [CourseResults] {
        resultsStore.all()
    }

    /// True while Claude is generating a course (initial generation or regenerate).
    var isGeneratingCourse: Bool {
        isRegenerating || (currentMode == .course && isSending && activeCourse == nil)
    }

    func start() async {
        refreshAPIKeyStatus()
        containerRuntime = ContainerRuntime.detect()
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
        let resumeIdx = progressStore.progress(for: course.id)?.lessonIdx ?? 0
        currentLessonIdx = max(0, min(resumeIdx, course.lessons.count - 1))
        resetChallengeState()
        startTerminalIfSupported(for: course)
        let idx = currentLessonIdx
        Task {
            guard let sessionId else { return }
            await logLessonStart(course: course, idx: idx, sessionId: sessionId)
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
        saveProgress(course: course)
        Task {
            await logLessonComplete(course: course, idx: currentLessonIdx, sessionId: sessionId, finished: false)
        }
        activeCourse = nil
        currentLessonIdx = 0
    }

    private func saveProgress(course: Course) {
        let completed = currentLessonIdx >= course.lessons.count - 1
        progressStore.set(CourseProgress(lessonIdx: currentLessonIdx, completed: completed), for: course.id)
    }

    private func startTerminalIfSupported(for course: Course) {
        terminal?.stop()
        terminal = nil
        containerStarting = false
        containerStartError = nil
        guard let sessionId else { return }

        if course.environment == .linux {
            // Without an engine we leave the terminal nil and the player shows install guidance.
            guard let runtime = containerRuntime else { return }
            // The engine's binary exists but its service may be down; start it before launching
            // the container so the student doesn't see a raw "XPC connection error".
            containerStarting = true
            Task {
                let (ready, message) = await runtime.ensureServiceRunning()
                containerStarting = false
                guard ready else {
                    containerStartError = message
                    return
                }
                startController(for: course, sessionId: sessionId, runtime: runtime)
            }
            return
        }

        startController(for: course, sessionId: sessionId, runtime: nil)
    }

    private func startController(for course: Course, sessionId: String, runtime: ContainerRuntime?) {
        do {
            let controller = try SandboxTerminalController(
                course: course,
                sessionId: sessionId,
                eventStore: eventStore,
                runtime: runtime
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
        saveProgress(course: course)
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
        if let course = activeCourse { saveProgress(course: course) }
    }

    private func resetChallengeState() {
        challengeOutcome = nil
        hintRevealed = false
        hintText = nil
        hintLoading = false
        isChecking = false
        lessonChat = []
        showLessonChat = false
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
            transcript: terminal.transcript,
            fileSystem: terminal.fileSystem
        )
        let command = terminal.lastCommand ?? ""
        let idx = currentLessonIdx

        Task {
            await logChallengeAttempt(course: course, idx: idx, command: command, sessionId: sessionId)
            let outcome = await verifier.verify(challenge.verify, context: context)
            challengeOutcome = outcome
            isChecking = false
            recordResult(course: course, idx: idx, outcome: outcome, command: command)
            if outcome.passed {
                await logChallengeResult(.challengePass, course: course, idx: idx, verify: challenge.verify, detail: outcome.detail, sessionId: sessionId)
            } else {
                await logChallengeResult(.challengeFail, course: course, idx: idx, verify: challenge.verify, detail: outcome.detail, sessionId: sessionId)
            }
        }
    }

    /// Saves a structured per-lesson result for later review by the student or instructor.
    private func recordResult(course: Course, idx: Int, outcome: VerifyOutcome, command: String) {
        guard idx < course.lessons.count else { return }
        let attemptNum = resultsStore.results(for: course.id)?.currentAttempt ?? 1
        let record = LessonAttempt(
            id: UUID().uuidString,
            attempt: attemptNum,
            lessonIdx: idx,
            lessonTitle: course.lessons[idx].title,
            passed: outcome.passed,
            detail: outcome.detail,
            command: command,
            hintUsed: hintRevealed,
            timestamp: Date()
        )
        resultsStore.record(record, courseId: course.id, subject: course.subject, title: course.title, lessonCount: course.lessons.count)
        resultsRevision += 1
    }

    /// Restarts a course from the first lesson, keeping prior results as a new attempt.
    func retakeCourse(_ course: Course) {
        resultsStore.startNewAttempt(courseId: course.id, subject: course.subject, title: course.title, lessonCount: course.lessons.count)
        progressStore.set(CourseProgress(lessonIdx: 0, completed: false), for: course.id)
        resultsRevision += 1
        openCourse(course)
    }

    /// Clears the saved results for one lesson so it can be re-taken cleanly.
    func clearLessonResults(courseId: String, lessonIdx: Int) {
        resultsStore.clearLesson(courseId: courseId, lessonIdx: lessonIdx)
        resultsRevision += 1
    }

    /// Purges a course and everything tied to it: cached JSON, progress, results, and sandbox.
    func deleteCourse(_ course: Course) {
        if activeCourse?.id == course.id {
            terminal?.stop()
            terminal = nil
            activeCourse = nil
            currentLessonIdx = 0
            resetChallengeState()
        }
        try? courseStore.delete(course)
        progressStore.remove(courseId: course.id)
        resultsStore.remove(courseId: course.id)
        StudentSandbox.shared.remove(forCourseId: course.id)
        courses = courseStore.listAll()
        resultsRevision += 1
    }

    func revealHint() {
        guard let course = activeCourse, let sessionId, currentLessonIdx < course.lessons.count else { return }
        hintRevealed = true
        hintLoading = true
        hintText = nil
        let lesson = course.lessons[currentLessonIdx]
        let idx = currentLessonIdx
        let transcript = terminal?.transcript ?? ""
        Task {
            var text: String
            do {
                text = try await claude.hint(lessonTitle: lesson.title, concept: lesson.conceptMd, task: lesson.challenge.task, transcript: transcript)
            } catch {
                text = Self.fallbackHint(for: lesson.challenge)
            }
            hintText = text
            hintLoading = false
            await logHintUsed(course: course, idx: idx, text: text, sessionId: sessionId)
        }
    }

    static func fallbackHint(for challenge: Challenge) -> String {
        switch challenge.verify.type {
        case .exitCode:
            return "Your last command needs to finish with exit code \(challenge.verify.exitCode ?? 0). Check its output for errors."
        case .stdoutRegex:
            return "Run a command whose output matches /\(challenge.verify.value ?? "")/."
        case .fileExists:
            return "Create the file at \(challenge.verify.path ?? "the given path") inside this sandbox."
        case .fileContains:
            return "Make sure \(challenge.verify.path ?? "the file") contains \"\(challenge.verify.value ?? "")\"."
        case .llmJudge:
            return "Re-read the task and make sure your shell session clearly accomplishes it."
        }
    }

    func sendLessonQuestion(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !lessonChatSending,
              let course = activeCourse, let sessionId,
              currentLessonIdx < course.lessons.count else { return }
        let idx = currentLessonIdx
        let lesson = course.lessons[idx]

        lessonChat.append(ChatMessage(role: .user, mode: .ask, text: trimmed))
        let assistant = ChatMessage(role: .assistant, mode: .ask, text: "")
        lessonChat.append(assistant)
        let assistantId = assistant.id
        lessonChatSending = true

        let preamble = "Lesson: \(lesson.title)\nConcept: \(lesson.conceptMd)\nChallenge: \(lesson.challenge.task)"
        let history = Array(lessonChat.dropLast())

        Task {
            await logChatEvent(.chatUser, mode: .ask, text: trimmed, sessionId: sessionId, courseId: course.id, lessonIdx: idx)
            do {
                for try await chunk in claude.streamAskResponse(history: history, contextPreamble: preamble) {
                    appendLessonChunk(to: assistantId, text: chunk.text)
                }
                let finalText = lessonChat.first(where: { $0.id == assistantId })?.text ?? ""
                await logChatEvent(.chatAssistant, mode: .ask, text: finalText, sessionId: sessionId, courseId: course.id, lessonIdx: idx)
            } catch {
                appendLessonChunk(to: assistantId, text: "\n\n_Error: \(error.localizedDescription)_")
            }
            lessonChatSending = false
        }
    }

    private func appendLessonChunk(to id: UUID, text: String) {
        guard let idx = lessonChat.firstIndex(where: { $0.id == id }) else { return }
        lessonChat[idx].text += text
    }

    func regenerateActiveCourse() {
        guard let course = activeCourse, let sessionId, !isRegenerating else { return }
        isRegenerating = true
        let subject = course.subject
        Task {
            do {
                let result = try await courseGenerator.generate(subject: subject, forceRefresh: true)
                await logCourseGenerated(course: result.course, wasCached: false, sessionId: sessionId)
                courses = courseStore.listAll()
                isRegenerating = false
                openCourse(result.course)
            } catch {
                lastError = "Regenerate failed: \(error.localizedDescription)"
                isRegenerating = false
            }
        }
    }

    private func appendChunk(to id: UUID, text: String) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].text += text
    }

    private func logChatEvent(_ type: EventType, mode: ChatMode, text: String, sessionId: String, courseId: String?, lessonIdx: Int? = nil) async {
        let event = LogEvent(
            sessionId: sessionId,
            timestamp: Date(),
            type: type,
            courseId: courseId,
            lessonIdx: lessonIdx,
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

    private func logHintUsed(course: Course, idx: Int, text: String, sessionId: String) async {
        let event = LogEvent(
            sessionId: sessionId,
            timestamp: Date(),
            type: .hintUsed,
            courseId: course.id,
            lessonIdx: idx,
            payload: ["hint_text": AnyCodable(text)]
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
