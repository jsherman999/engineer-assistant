import SwiftUI
import AppKit

/// A demo command on the dark terminal block, with a copy button that puts the bare command
/// (no `$ ` prompt) on the clipboard so it can be pasted straight into the terminal.
private struct DemoCommandRow: View {
    let command: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("$ \(command)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.green)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(copied ? .green : Color(white: 0.85))
            }
            .buttonStyle(.borderless)
            .help("Copy command")
        }
        .padding(8)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct CoursePlayerView: View {
    @EnvironmentObject var session: AppSession
    let course: Course
    @State private var nextPulse = false

    private var challengePassed: Bool { session.challengeOutcome?.passed == true }

    var lesson: Lesson? {
        guard session.currentLessonIdx < course.lessons.count else { return nil }
        return course.lessons[session.currentLessonIdx]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            // IDE split: course narrative (left) | live terminal (right) | optional Ask sidebar.
            HStack(spacing: 0) {
                leftPanel
                Divider()
                rightPanel
                if session.showLessonChat {
                    Divider()
                    LessonChatSidebar().frame(width: 320)
                }
            }
            .frame(maxHeight: .infinity)
            Divider()
            controls
        }
    }

    private var leftPanel: some View {
        Group {
            if let lesson {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            lessonTitle(lesson).id("lessonTop")
                            section("Concept", Theme.concept) { conceptText(lesson.conceptMd) }
                            section("Demos", Theme.demos) { demosList(lesson.demos) }
                            section("Practice", Theme.practice) { practiceText(lesson.practicePrompt) }
                            section("Challenge", Theme.challenge) { challengeBlock(lesson.challenge) }
                            Spacer(minLength: 16)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // Start each lesson (and a freshly opened course) at the top, not scrolled down.
                    .onChange(of: session.currentLessonIdx) { _, _ in
                        proxy.scrollTo("lessonTop", anchor: .top)
                    }
                    .onAppear { proxy.scrollTo("lessonTop", anchor: .top) }
                }
            } else {
                Text("No lessons.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 320)
        .background(Theme.workspace)
    }

    @ViewBuilder
    private var rightPanel: some View {
        Group {
            if let terminal = session.terminal {
                SandboxTerminalView(controller: terminal)
            } else if session.containerStarting {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Starting \(session.containerRuntime?.displayName ?? "container engine")…")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Bringing up the container service for this Linux course. This can take a few seconds the first time.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.workspace)
            } else if let startError = session.containerStartError {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.orange)
                    Text("Couldn't start the container engine.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text(startError)
                        .font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.workspace)
            } else if course.environment == .linux {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "shippingbox").font(.title2).foregroundStyle(.secondary)
                    Text("Linux courses need a container engine.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Install Apple's `container` (recommended on macOS 26+) or `brew install podman`, then reopen this course.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.workspace)
            } else {
                Text("Terminal unavailable.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.workspace)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 360)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.title).font(.title2.bold())
                    Text(course.description).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    session.regenerateActiveCourse()
                } label: {
                    if session.isRegenerating {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .help("Discard the cached course and generate a fresh one for this subject")
                .disabled(session.isRegenerating)
                envBadge
            }
            HStack(spacing: 12) {
                Text("~\(course.estimatedMinutes) min").font(.caption).foregroundStyle(.secondary)
                if !course.prerequisites.isEmpty {
                    Text("Prereqs: \(course.prerequisites.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Theme.headerTint.opacity(0.07))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.headerTint.opacity(0.25)).frame(height: 1)
        }
    }

    private var envBadge: some View {
        Text(course.environment == .macos ? "macOS" : "Linux")
            .font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(course.environment == .macos ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
            .clipShape(Capsule())
    }

    private func lessonTitle(_ lesson: Lesson) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(Theme.headerTint).frame(width: 4, height: 22)
            Text(lesson.title).font(.title3.bold())
        }
    }

    private func section<Content: View>(_ name: String, _ accent: Color, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(accent.opacity(0.85)).frame(width: 3)
            VStack(alignment: .leading, spacing: 10) {
                Text(name.uppercased())
                    .font(.caption.bold()).tracking(0.8)
                    .foregroundStyle(accent)
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.18), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func conceptText(_ md: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownTable.split(md).enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let t):
                    if let attributed = try? AttributedString(markdown: t, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(attributed).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(t).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .table(let rows):
                    TableGrid(rows: rows, font: .callout)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func demosList(_ demos: [Demo]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(demos.enumerated()), id: \.offset) { _, demo in
                VStack(alignment: .leading, spacing: 4) {
                    DemoCommandRow(command: demo.command)
                    if !demo.expectedOutput.isEmpty {
                        Text(demo.expectedOutput)
                            .font(.system(.callout, design: .monospaced))
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .textSelection(.enabled)
                    }
                    Text(demo.explanation).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func practiceText(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).textSelection(.enabled)
            if session.terminal != nil {
                Text("Try it in the sandboxed shell below.")
                    .font(.caption).foregroundStyle(.tertiary).italic()
            }
        }
    }

    private func challengeBlock(_ challenge: Challenge) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(challenge.task).textSelection(.enabled)
            if let starter = challenge.starterState, !starter.isEmpty {
                Text("Starter state: \(starter)").font(.caption).foregroundStyle(.secondary)
            }
            Text("Verify: \(verifyDescription(challenge.verify))")
                .font(.caption).foregroundStyle(.secondary).italic()

            HStack(spacing: 10) {
                Button {
                    session.checkCurrentChallenge()
                } label: {
                    if session.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Check Challenge", systemImage: "checkmark.circle")
                    }
                }
                .disabled(session.isChecking || session.terminal == nil)

                if let outcome = session.challengeOutcome {
                    Label(outcome.passed ? "Passed" : "Not yet",
                          systemImage: outcome.passed ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .foregroundStyle(outcome.passed ? .green : .orange)
                        .font(.callout)
                }
            }

            if let outcome = session.challengeOutcome {
                Text(outcome.detail)
                    .font(.caption).foregroundStyle(.secondary)
                if !outcome.passed {
                    if session.hintRevealed {
                        if session.hintLoading {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Thinking of a hint…").font(.caption).foregroundStyle(.secondary)
                            }
                        } else if let hint = session.hintText {
                            Text("Hint: \(hint)")
                                .font(.caption).foregroundStyle(.blue).italic()
                                .textSelection(.enabled)
                        }
                    } else {
                        Button("Show hint") { session.revealHint() }
                            .font(.caption).buttonStyle(.borderless)
                    }
                }
            }

            savedResult
        }
    }

    @ViewBuilder
    private var savedResult: some View {
        // Reading resultsRevision keeps this fresh after a check or a clear.
        let _ = session.resultsRevision
        if let results = session.results(for: course.id),
           let latest = results.latest(lessonIdx: session.currentLessonIdx, attempt: results.currentAttempt) {
            Divider().padding(.vertical, 2)
            HStack(spacing: 8) {
                Label(latest.passed ? "Saved: passed" : "Saved: not yet",
                      systemImage: latest.passed ? "checkmark.seal" : "clock.arrow.circlepath")
                    .font(.caption).foregroundStyle(latest.passed ? .green : .secondary)
                Text("attempt \(latest.attempt)").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("Clear this lesson's results") {
                    session.clearLessonResults(courseId: course.id, lessonIdx: session.currentLessonIdx)
                }
                .font(.caption).buttonStyle(.borderless)
            }
        }
    }

    private func verifyDescription(_ v: VerifyCheck) -> String {
        switch v.type {
        case .exitCode: return "exit code == \(v.exitCode ?? 0)"
        case .stdoutRegex: return "stdout matches /\(v.value ?? "")/"
        case .fileExists: return "file exists: \(v.path ?? "?")"
        case .fileContains: return "file \(v.path ?? "?") contains \"\(v.value ?? "")\""
        case .llmJudge: return "LLM judges: \(v.value ?? "")"
        }
    }

    private var lessonBadge: some View {
        Text("Lesson \(session.currentLessonIdx + 1) of \(course.lessons.count)")
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Capsule().fill(Theme.headerTint.gradient))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                session.previousLesson()
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(session.currentLessonIdx == 0)

            Button(role: .destructive) {
                session.exitCourse()
            } label: {
                Label("Exit Course", systemImage: "xmark")
            }

            Spacer()

            Button {
                session.showLessonChat.toggle()
            } label: {
                Label("Ask Claude", systemImage: "bubble.left.and.text.bubble.right")
            }
            .help("Ask Claude a question about this lesson")

            lessonBadge

            Button {
                session.nextLesson()
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(session.currentLessonIdx >= course.lessons.count - 1)
            .tint(challengePassed ? .green : nil)
            .opacity(nextPulse ? 0.5 : 1.0)
            // After a passing check, gently blink Next to draw attention (until you move on).
            .onChange(of: session.challengeOutcome?.passed) { _, passed in
                let canAdvance = session.currentLessonIdx < course.lessons.count - 1
                if passed == true && canAdvance {
                    withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) { nextPulse = true }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { nextPulse = false }
                }
            }
        }
        .padding(12)
        .background(Theme.bar)
    }
}

/// Lesson-scoped chat: questions are answered with the current lesson as context and
/// logged with `course_id` + `lesson_idx` so the dashboard can separate them from
/// free-form Ask Mode.
private struct LessonChatSidebar: View {
    @EnvironmentObject var session: AppSession
    @State private var input: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ask Claude").font(.headline)
                Spacer()
                Button {
                    session.showLessonChat = false
                } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
            }
            .padding(10)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if session.lessonChat.isEmpty {
                            Text("Ask anything about this lesson — Claude sees the concept and challenge.")
                                .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                        }
                        ForEach(session.lessonChat) { msg in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(msg.role == .user ? "You" : "Claude")
                                    .font(.caption2.bold()).foregroundStyle(.secondary)
                                Text(msg.text.isEmpty ? "…" : msg.text)
                                    .font(.callout).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(msg.role == .user ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .id(msg.id)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: session.lessonChat.last?.text) { _, _ in
                    if let last = session.lessonChat.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()
            HStack(spacing: 6) {
                TextField("Question about this lesson…", text: $input, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .disabled(session.lessonChatSending || !session.apiKeyConfigured)
                    .onSubmit(sendQuestion)
                Button(action: sendQuestion) {
                    if session.lessonChatSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.lessonChatSending || !session.apiKeyConfigured)
            }
            .padding(8)
        }
        .background(.regularMaterial)
    }

    private func sendQuestion() {
        let text = input
        input = ""
        session.sendLessonQuestion(text)
    }
}
