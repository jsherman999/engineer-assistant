import Foundation
import SwiftUI
import AppKit

@MainActor
final class AppSession: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var currentMode: ChatMode = .ask {
        didSet {
            guard oldValue != currentMode else { return }
            // Ask and Course keep separate transcripts: switching shows the other mode's own
            // (initially empty) screen and preserves the one you left.
            transcripts[oldValue] = messages
            messages = transcripts[currentMode] ?? []
            lastError = nil
        }
    }
    /// Per-mode chat transcripts so Ask and Course never share the same input/output screen.
    private var transcripts: [ChatMode: [ChatMessage]] = [:]
    @Published var isSending: Bool = false
    @Published var apiKeyConfigured: Bool = false
    @Published var sessionId: String? = nil
    @Published var lastError: String? = nil
    @Published var activeCourse: Course? = nil
    @Published var currentLessonIdx: Int = 0
    @Published var courses: [Course] = []
    @Published var terminal: SandboxTerminalController? = nil
    @Published var askTerminal: SandboxTerminalController? = nil
    @Published var isChecking: Bool = false
    @Published var challengeOutcome: VerifyOutcome? = nil
    /// Separate state for the course's capstone `final_challenge`, which is offered alongside
    /// the last lesson's own challenge.
    @Published var isCheckingFinal: Bool = false
    @Published var finalOutcome: VerifyOutcome? = nil
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
    /// Explain-back: the student's own account of why their solution worked, and the response.
    @Published var explanationSending: Bool = false
    @Published var explanationFeedback: String? = nil
    /// Inline help for a command that just failed.
    @Published var errorHelpLoading: Bool = false
    @Published var errorHelpText: String? = nil
    /// Bumped whenever saved lesson results change, so result views re-render.
    @Published private(set) var resultsRevision: Int = 0

    /// Session boundary: quit, or this long without student activity.
    static let idleTimeout: TimeInterval = 30 * 60
    private var lastActivity = Date()
    private var idleTimer: Timer?

    private let claude = ClaudeClient()
    private let courseGenerator = CourseGenerator()
    private let courseStore: CourseStore = FileCourseStore()
    private let eventStore: EventStore = JSONLEventStore()
    private lazy var events = EventLogger(store: eventStore)
    private let progressStore: ProgressStore = FileProgressStore()
    private let resultsStore: ResultsStore = FileResultsStore()
    private let commandRunner = AllowlistedCommandRunner()
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
            startAskTerminal()
            observeAppTermination()
            startIdleTimer()
        } catch {
            self.lastError = "Failed to start session: \(error.localizedDescription)"
        }
    }

    // MARK: - Session boundary (quit or 30 minutes idle)

    /// Closes the open session on quit so the instructor dashboard shows a real duration
    /// instead of leaving every session reading "in progress" forever.
    private func observeAppTermination() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.endSession(reason: "quit") }
        }
    }

    /// Ends the session synchronously — `willTerminate` does not wait for detached work, so the
    /// event has to be on disk before the process goes away.
    private func endSession(reason: String) {
        guard let sessionId else { return }
        self.sessionId = nil
        idleTimer?.invalidate()
        idleTimer = nil
        eventStore.endSessionSynchronously(sessionId, reason: reason)
    }

    /// A session ends after 30 minutes without student activity; the next interaction opens a
    /// fresh one, so a Mac left running overnight doesn't produce one 14-hour "session".
    private func startIdleTimer() {
        idleTimer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIdle() }
        }
        idleTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func checkIdle() {
        guard sessionId != nil, Date().timeIntervalSince(lastActivity) >= Self.idleTimeout else { return }
        endSession(reason: "idle")
    }

    // MARK: - Explain-back

    /// After a pass, the student says in their own words why it worked and Claude responds.
    /// Passing proves the command ran; explaining is what turns that into understanding.
    func submitExplanation(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !explanationSending,
              let course = activeCourse, currentLessonIdx < course.lessons.count else { return }
        noteActivity()
        let lesson = course.lessons[currentLessonIdx]
        explanationSending = true
        explanationFeedback = nil

        Task {
            do {
                explanationFeedback = try await claude.reviewExplanation(
                    task: lesson.challenge.task,
                    concept: lesson.conceptMd,
                    studentAnswer: trimmed
                )
            } catch {
                explanationFeedback = "Couldn't check that right now: \(error.localizedDescription)"
            }
            explanationSending = false
            if let sessionId {
                await events.explainBack(course: course, idx: currentLessonIdx,
                                         answer: trimmed, feedback: explanationFeedback ?? "",
                                         sessionId: sessionId)
            }
        }
    }

    // MARK: - Error as curriculum

    /// True when the last command failed — the moment to offer an explanation.
    var lastCommandFailed: Bool {
        guard let code = terminal?.lastExitCode else { return false }
        return code != 0
    }

    /// Explains the failure the student just hit, without making them leave the terminal.
    func explainLastError() {
        guard let terminal, let code = terminal.lastExitCode, code != 0, !errorHelpLoading else { return }
        noteActivity()
        errorHelpLoading = true
        errorHelpText = nil

        let command = terminal.lastCommand ?? "(unknown command)"
        let output = terminal.lastStdout
        let context = activeCourse.flatMap { course -> String? in
            guard currentLessonIdx < course.lessons.count else { return nil }
            return "\(course.lessons[currentLessonIdx].title) — \(course.lessons[currentLessonIdx].challenge.task)"
        }

        Task {
            do {
                errorHelpText = try await claude.explainError(
                    command: command, output: output, exitCode: code, lessonContext: context
                )
            } catch {
                errorHelpText = "Couldn't explain that right now: \(error.localizedDescription)"
            }
            errorHelpLoading = false
        }
    }

    // MARK: - Review

    /// Lessons due for another look, weakest first.
    func dueReviewItems() -> [ReviewItem] {
        ReviewPlanner.dueItems(in: resultsStore.all(), courses: courses)
    }

    /// Opens a course at the lesson being reviewed.
    func startReview(_ item: ReviewItem) {
        guard let course = courses.first(where: { $0.id == item.courseId }) else { return }
        openCourse(course)
        goToLesson(item.lessonIdx)
    }

    /// Called from every student-initiated action. Reopens a session if the previous one timed
    /// out, so activity after a long break is recorded rather than dropped.
    func noteActivity() {
        lastActivity = Date()
        guard sessionId == nil else { return }
        Task { _ = await ensureSession() }
    }

    /// A persistent, unrestricted macOS shell shown beside Ask-mode chat so the student can try
    /// the commands being described on their real Mac (full network/filesystem access). Course
    /// mode stays sandboxed; only Ask mode is unconfined.
    private func startAskTerminal() {
        guard askTerminal == nil, let sessionId else { return }
        do {
            let controller = try SandboxTerminalController(
                courseId: "ask",
                environment: .macos,
                workingDirectory: StudentSandbox.shared.askDirectory(),
                sessionId: sessionId,
                eventStore: eventStore,
                runtime: nil,
                confined: false,
                fontSize: 10,
                foregroundColor: Theme.terminalGreenNS
            )
            controller.onActivity = { [weak self] in self?.noteActivity() }
            try controller.start()
            askTerminal = controller
        } catch {
            lastError = "Ask sandbox failed to start: \(error.localizedDescription)"
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
        noteActivity()

        let mode = currentMode
        let userMsg = ChatMessage(role: .user, mode: mode, text: trimmed)
        messages.append(userMsg)
        isSending = true
        lastError = nil

        Task {
            // Resolve the session inside the task: after an idle timeout the previous one is
            // closed, and this first message is what opens the next.
            guard let sessionId = await ensureSession() else {
                lastError = "Could not start a session to record this."
                isSending = false
                return
            }
            await events.chat(.chatUser, mode: mode, text: trimmed, sessionId: sessionId, courseId: nil)
            if mode == .ask {
                await handleAsk(sessionId: sessionId)
            } else {
                await handleCourse(subject: trimmed, sessionId: sessionId)
            }
            isSending = false
        }
    }

    /// The current session id, opening a fresh session if the last one timed out.
    private func ensureSession() async -> String? {
        if let sessionId { return sessionId }
        guard let id = try? await eventStore.startSession() else { return nil }
        sessionId = id
        startIdleTimer()
        return id
    }

    private func handleAsk(sessionId: String) async {
        let assistantMsg = ChatMessage(role: .assistant, mode: .ask, text: "")
        messages.append(assistantMsg)
        let assistantId = assistantMsg.id
        let history = Array(messages.dropLast())
        do {
            // Agentic: Claude can run read-only commands (gated by the allowlist) to answer with
            // this Mac's real state. Text streams in as it is written, so the student watches the
            // answer form rather than a spinner.
            try await claude.askAgent(
                history: history,
                runCommand: { [weak self] command in
                    await self?.runAgentCommand(command, assistantId: assistantId, sessionId: sessionId) ?? ""
                },
                onText: { [weak self] chunk in
                    self?.appendChunk(to: assistantId, text: chunk)
                }
            )
            let full = messages.first(where: { $0.id == assistantId })?.text ?? ""
            await events.chat(.chatAssistant, mode: .ask, text: full, sessionId: sessionId, courseId: nil)
        } catch {
            lastError = error.localizedDescription
            appendChunk(to: assistantId, text: "\n\n_Error: \(error.localizedDescription)_")
        }
    }

    /// Runs an agent-proposed command through the read-only allowlist, surfaces it in the chat
    /// bubble so the student sees what ran, logs it for the instructor, and returns the output
    /// to the model.
    private func runAgentCommand(_ command: String, assistantId: UUID, sessionId: String) async -> String {
        let result = await commandRunner.run(command)
        let hasText = !(messages.first(where: { $0.id == assistantId })?.text.isEmpty ?? true)
        let marker = result.allowed ? "$ \(command)" : "$ \(command)  ⚠︎ refused"
        appendChunk(to: assistantId, text: (hasText ? "\n" : "") + marker)
        await events.agentCommand(command: command, output: result.output, allowed: result.allowed, sessionId: sessionId)
        return result.output
    }

    private func handleCourse(subject: String, sessionId: String) async {
        do {
            let result = try await courseGenerator.generate(subject: subject, containerGuidance: containerGuidance())
            let course = result.course

            await events.courseGenerated(course: course, wasCached: result.wasCached, sessionId: sessionId)

            let summary = result.wasCached
                ? "Loaded cached course: **\(course.title)** — \(course.lessons.count) lessons."
                : "Generated course: **\(course.title)** — \(course.lessons.count) lessons."
            let reply = ChatMessage(role: .assistant, mode: .course, text: summary)
            messages.append(reply)
            await events.chat(.chatAssistant, mode: .course, text: summary, sessionId: sessionId, courseId: course.id)

            courses = courseStore.listAll()
            openCourse(course)
        } catch {
            lastError = error.localizedDescription
            let reply = ChatMessage(role: .assistant, mode: .course, text: "Could not generate course: \(error.localizedDescription)")
            messages.append(reply)
        }
    }

    /// Tells the course generator which container CLI is actually installed, so it uses the
    /// right syntax (Apple `container` is NOT Docker — `container image pull`, not `container pull`).
    private func containerGuidance() -> String? {
        switch containerRuntime?.engine {
        case .apple:
            return "Container CLI note: this Mac uses Apple's `container` tool, which is NOT Docker-compatible at the top level. Image commands are subcommands of `container image` — e.g. `container image pull alpine:latest`, `container image list` (alias `container image ls`). Run a container with `container run`. NEVER use `container pull`, `container images`, or any `docker`/`podman` command. In demos, make expected_output match Apple `container`'s real format, which differs from Docker: `container image list` prints only the columns `NAME  TAG  DIGEST` (no IMAGE ID / CREATED / SIZE); `container list` (running containers) prints `ID  IMAGE  OS  ARCH  STATE  ADDR`."
        case .podman:
            return "Container CLI note: this Mac uses Podman (Docker-compatible). Use `podman pull`, `podman images`, `podman run`."
        case .docker:
            return "Container CLI note: this Mac uses Docker. Use `docker pull`, `docker images`, `docker run`."
        case nil:
            return nil
        }
    }

    func openCourse(_ course: Course) {
        noteActivity()
        activeCourse = course
        let resumeIdx = progressStore.progress(for: course.id)?.lessonIdx ?? 0
        currentLessonIdx = max(0, min(resumeIdx, course.lessons.count - 1))
        resetChallengeState()
        startTerminalIfSupported(for: course)
        let idx = currentLessonIdx
        Task {
            guard let sessionId else { return }
            await events.lessonStart(course: course, idx: idx, sessionId: sessionId)
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
            await events.lessonComplete(course: course, idx: currentLessonIdx, finished: false, sessionId: sessionId)
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
                guard ready else {
                    containerStarting = false
                    containerStartError = message
                    return
                }
                // Clear any container the previous run left behind before launching a new one.
                await runtime.forceRemoveContainer(named: SandboxTerminalController.containerName(forCourseId: course.id))
                containerStarting = false
                startController(for: course, sessionId: sessionId, runtime: runtime)
            }
            return
        }

        startController(for: course, sessionId: sessionId, runtime: nil)
    }

    private func startController(for course: Course, sessionId: String, runtime: ContainerRuntime?) {
        do {
            let controller = try SandboxTerminalController(
                courseId: course.id,
                environment: course.environment,
                workingDirectory: StudentSandbox.shared.directory(forCourseId: course.id),
                sessionId: sessionId,
                eventStore: eventStore,
                runtime: runtime
            )
            controller.onActivity = { [weak self] in self?.noteActivity() }
            try controller.start()
            terminal = controller
            seedStarterFiles()
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
        seedStarterFiles()
        saveProgress(course: course)
        Task {
            guard let sessionId else { return }
            await events.lessonComplete(course: course, idx: prevIdx, finished: true, sessionId: sessionId)
            await events.lessonStart(course: course, idx: nextIdx, sessionId: sessionId)
        }
    }

    func previousLesson() {
        guard let course = activeCourse, currentLessonIdx > 0 else { return }
        currentLessonIdx -= 1
        resetChallengeState()
        seedStarterFiles()
        saveProgress(course: course)
        let idx = currentLessonIdx
        Task {
            guard let sessionId else { return }
            await events.lessonStart(course: course, idx: idx, sessionId: sessionId)
        }
    }

    /// Jumps straight to a lesson from the lesson rail.
    func goToLesson(_ idx: Int) {
        guard let course = activeCourse, idx >= 0, idx < course.lessons.count, idx != currentLessonIdx else { return }
        currentLessonIdx = idx
        resetChallengeState()
        seedStarterFiles()
        saveProgress(course: course)
        Task {
            guard let sessionId else { return }
            await events.lessonStart(course: course, idx: idx, sessionId: sessionId)
        }
    }

    /// Records a skip so the instructor can see the student moved on without passing.
    func skipCurrentLesson() {
        guard let course = activeCourse, let sessionId, currentLessonIdx < course.lessons.count else { return }
        let idx = currentLessonIdx
        Task { await events.skipUsed(course: course, idx: idx, panel: "challenge", sessionId: sessionId) }
        if idx < course.lessons.count - 1 {
            nextLesson()
        }
    }

    private func resetChallengeState() {
        challengeOutcome = nil
        finalOutcome = nil
        hintRevealed = false
        hintText = nil
        hintLoading = false
        isChecking = false
        isCheckingFinal = false
        lessonChat = []
        showLessonChat = false
        explanationFeedback = nil
        explanationSending = false
        errorHelpText = nil
        errorHelpLoading = false
    }

    /// Writes the current lesson's `starter_files` into the sandbox so challenges that assume a
    /// starting point ("fix this script", "count the lines in data.txt") are actually solvable.
    /// Runs on every lesson entry; seeding is idempotent because it overwrites by path.
    private func seedStarterFiles() {
        guard let course = activeCourse, currentLessonIdx < course.lessons.count,
              let terminal else { return }
        var files = course.lessons[currentLessonIdx].challenge.starterFiles ?? []
        if isLastLesson, let final = course.finalChallenge?.starterFiles { files += final }
        guard !files.isEmpty else { return }
        let fileSystem = terminal.fileSystem
        Task {
            for file in files {
                await fileSystem.writeFile(file.path, content: file.content, executable: file.executable ?? false)
            }
        }
    }

    var isLastLesson: Bool {
        guard let course = activeCourse else { return false }
        return currentLessonIdx >= course.lessons.count - 1
    }

    func checkCurrentChallenge() {
        guard let course = activeCourse, currentLessonIdx < course.lessons.count else { return }
        runVerification(
            challenge: course.lessons[currentLessonIdx].challenge,
            idx: currentLessonIdx,
            title: course.lessons[currentLessonIdx].title,
            setChecking: { self.isChecking = $0 },
            setOutcome: { self.challengeOutcome = $0 }
        )
    }

    /// Verifies the course's capstone. It is offered alongside the last lesson and recorded
    /// under a synthetic index past the real lessons so it never collides with lesson results.
    func checkFinalChallenge() {
        guard let course = activeCourse, let final = course.finalChallenge else { return }
        runVerification(
            challenge: final,
            idx: course.lessons.count,
            title: "Final Challenge",
            setChecking: { self.isCheckingFinal = $0 },
            setOutcome: { self.finalOutcome = $0 }
        )
    }

    /// Shared verify → record → log path for both the per-lesson challenge and the capstone.
    private func runVerification(challenge: Challenge,
                                 idx: Int,
                                 title: String,
                                 setChecking: @escaping (Bool) -> Void,
                                 setOutcome: @escaping (VerifyOutcome?) -> Void) {
        noteActivity()
        guard let course = activeCourse, let sessionId else { return }
        guard let terminal else {
            setOutcome(VerifyOutcome(passed: false, detail: "Start the sandbox shell first."))
            return
        }

        setChecking(true)
        setOutcome(nil)
        hintRevealed = false

        let context = VerifyContext(
            lastExitCode: terminal.lastExitCode,
            lastStdout: terminal.lastStdout,
            transcript: terminal.transcript,
            fileSystem: terminal.fileSystem
        )
        let command = terminal.lastCommand ?? ""

        Task {
            await events.challengeAttempt(course: course, idx: idx, command: command, sessionId: sessionId)
            let outcome = await verifier.verify(challenge.verify, context: context)
            setOutcome(outcome)
            setChecking(false)
            recordResult(course: course, idx: idx, title: title, outcome: outcome, command: command)
            await events.challengeResult(passed: outcome.passed, course: course, idx: idx,
                                         verify: challenge.verify, detail: outcome.detail,
                                         sessionId: sessionId)
        }
    }

    /// Saves a structured per-lesson result for later review by the student or instructor.
    private func recordResult(course: Course, idx: Int, title: String, outcome: VerifyOutcome, command: String) {
        let attemptNum = resultsStore.results(for: course.id)?.currentAttempt ?? 1
        let record = LessonAttempt(
            id: UUID().uuidString,
            attempt: attemptNum,
            lessonIdx: idx,
            lessonTitle: title,
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
    /// A retake also gets a clean workspace — otherwise the challenges are already solved.
    func retakeCourse(_ course: Course) {
        resultsStore.startNewAttempt(courseId: course.id, subject: course.subject, title: course.title, lessonCount: course.lessons.count)
        progressStore.set(CourseProgress(lessonIdx: 0, completed: false), for: course.id)
        StudentSandbox.shared.allocateFresh(forCourseId: course.id)
        resultsRevision += 1
        openCourse(course)
    }

    /// Clears the saved results for one lesson in the current attempt so it can be re-taken
    /// cleanly. Earlier attempts stay in the gradebook.
    func clearLessonResults(courseId: String, lessonIdx: Int) {
        let attempt = resultsStore.results(for: courseId)?.currentAttempt
        resultsStore.clearLesson(courseId: courseId, lessonIdx: lessonIdx, attempt: attempt)
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

    /// Purges a course by id (instructor dashboard, which works from course ids). Falls back to
    /// removing any residual progress/results/sandbox if the course JSON is already gone.
    func deleteCourse(courseId: String) {
        if let course = courses.first(where: { $0.id == courseId }) {
            deleteCourse(course)
            return
        }
        progressStore.remove(courseId: courseId)
        resultsStore.remove(courseId: courseId)
        StudentSandbox.shared.remove(forCourseId: courseId)
        resultsRevision += 1
    }

    /// Clears all saved results (the gradebook) for a course while keeping the course itself.
    func deleteCourseHistory(courseId: String) {
        resultsStore.remove(courseId: courseId)
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
            await events.hintUsed(course: course, idx: idx, text: text, sessionId: sessionId)
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
            await events.chat(.chatUser, mode: .ask, text: trimmed, sessionId: sessionId, courseId: course.id, lessonIdx: idx)
            do {
                for try await chunk in claude.streamAskResponse(history: history, contextPreamble: preamble) {
                    appendLessonChunk(to: assistantId, text: chunk.text)
                }
                let finalText = lessonChat.first(where: { $0.id == assistantId })?.text ?? ""
                await events.chat(.chatAssistant, mode: .ask, text: finalText, sessionId: sessionId, courseId: course.id, lessonIdx: idx)
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
                let result = try await courseGenerator.generate(subject: subject, forceRefresh: true, containerGuidance: containerGuidance())
                await events.courseGenerated(course: result.course, wasCached: false, sessionId: sessionId)
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

}
