import SwiftUI

struct CoursePlayerView: View {
    @EnvironmentObject var session: AppSession
    let course: Course

    var lesson: Lesson? {
        guard session.currentLessonIdx < course.lessons.count else { return nil }
        return course.lessons[session.currentLessonIdx]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let lesson {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        lessonTitle(lesson)
                        section("Concept") { conceptText(lesson.conceptMd) }
                        section("Demos") { demosList(lesson.demos) }
                        section("Practice") { practiceText(lesson.practicePrompt) }
                        section("Challenge") { challengeBlock(lesson.challenge) }
                        Spacer(minLength: 20)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("No lessons.").padding()
            }
            Divider()
            controls
            terminalPanel
        }
    }

    @ViewBuilder
    private var terminalPanel: some View {
        if let terminal = session.terminal {
            Divider()
            SandboxTerminalView(controller: terminal)
                .frame(height: 280)
        } else if course.environment == .linux {
            Divider()
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "shippingbox")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Linux courses need a container engine.")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Install Apple's `container` (recommended on macOS 26+) or `brew install podman`, then reopen this course.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                Spacer()
            }
            .padding(10)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.title).font(.title2.bold())
                    Text(course.description).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                envBadge
            }
            HStack(spacing: 12) {
                Text("Lesson \(session.currentLessonIdx + 1) of \(course.lessons.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Text("~\(course.estimatedMinutes) min").font(.caption).foregroundStyle(.secondary)
                if !course.prerequisites.isEmpty {
                    Text("Prereqs: \(course.prerequisites.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
    }

    private var envBadge: some View {
        Text(course.environment == .macos ? "macOS" : "Linux")
            .font(.caption.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(course.environment == .macos ? Color.blue.opacity(0.15) : Color.green.opacity(0.15))
            .clipShape(Capsule())
    }

    private func lessonTitle(_ lesson: Lesson) -> some View {
        Text(lesson.title).font(.title3.bold())
    }

    private func section<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name).font(.headline).foregroundStyle(.secondary)
            content()
        }
    }

    private func conceptText(_ md: String) -> some View {
        if let attributed = try? AttributedString(markdown: md, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return AnyView(Text(attributed).textSelection(.enabled))
        } else {
            return AnyView(Text(md).textSelection(.enabled))
        }
    }

    private func demosList(_ demos: [Demo]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(demos.enumerated()), id: \.offset) { _, demo in
                VStack(alignment: .leading, spacing: 4) {
                    Text("$ \(demo.command)")
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color.black.opacity(0.85))
                        .foregroundStyle(.green)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
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
                        Text("Hint: \(hintText(challenge))")
                            .font(.caption).foregroundStyle(.blue).italic()
                    } else {
                        Button("Show hint") { session.revealHint() }
                            .font(.caption).buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private func hintText(_ challenge: Challenge) -> String {
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

    private func verifyDescription(_ v: VerifyCheck) -> String {
        switch v.type {
        case .exitCode: return "exit code == \(v.exitCode ?? 0)"
        case .stdoutRegex: return "stdout matches /\(v.value ?? "")/"
        case .fileExists: return "file exists: \(v.path ?? "?")"
        case .fileContains: return "file \(v.path ?? "?") contains \"\(v.value ?? "")\""
        case .llmJudge: return "LLM judges: \(v.value ?? "")"
        }
    }

    private var controls: some View {
        HStack {
            Button {
                session.previousLesson()
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(session.currentLessonIdx == 0)

            Spacer()

            Button(role: .destructive) {
                session.exitCourse()
            } label: {
                Label("Exit Course", systemImage: "xmark")
            }

            Spacer()

            Button {
                session.nextLesson()
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(session.currentLessonIdx >= course.lessons.count - 1)
        }
        .padding(12)
    }
}
