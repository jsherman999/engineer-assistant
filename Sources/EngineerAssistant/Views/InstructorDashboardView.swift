import SwiftUI
import AppKit

struct InstructorDashboardView: View {
    enum Mode: String, CaseIterable, Identifiable { case sessions = "Sessions", results = "Course Results"; var id: String { rawValue } }

    @State private var mode: Mode = .sessions
    @State private var sessions: [InstructorSession] = []
    @State private var selected: InstructorSession.ID?

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(8)
            Divider()
            switch mode {
            case .sessions: sessionsView
            case .results: CourseResultsBrowser()
            }
        }
    }

    private var sessionsView: some View {
        NavigationSplitView {
            List(sessions, selection: $selected) { session in
                sessionRow(session).tag(session.id)
            }
            .navigationTitle("Sessions")
            .frame(minWidth: 220)
        } detail: {
            if let id = selected, let session = sessions.first(where: { $0.id == id }) {
                SessionDetailView(session: session)
            } else if sessions.isEmpty {
                Text("No recorded sessions yet.").foregroundStyle(.secondary)
            } else {
                Text("Select a session.").foregroundStyle(.secondary)
            }
        }
        .onAppear {
            sessions = EventLogReader.loadSessions()
            selected = selected ?? sessions.first?.id
        }
    }

    private func sessionRow(_ s: InstructorSession) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(s.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline.bold())
            HStack(spacing: 8) {
                if let d = s.duration {
                    Text("\(Int(d / 60))m").font(.caption).foregroundStyle(.secondary)
                }
                Text("\(s.chatCount) chats").font(.caption).foregroundStyle(.secondary)
                if s.challengesPassed + s.challengesFailed > 0 {
                    Text("✓\(s.challengesPassed) ✗\(s.challengesFailed)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SessionDetailView: View {
    let session: InstructorSession
    @State private var tab: Tab = .timeline
    @State private var filter: Filter = .all
    @State private var exportNote: String?

    enum Tab: String, CaseIterable, Identifiable { case timeline = "Timeline", transcript = "Transcript", terminal = "Terminal"; var id: String { rawValue } }
    enum Filter: String, CaseIterable, Identifiable { case all = "All", chat = "Chat", shell = "Shell", lessons = "Lessons"; var id: String { rawValue } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Picker("View", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(8)

            switch tab {
            case .timeline: timeline
            case .transcript: transcript
            case .terminal: terminal
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(session.startedAt.formatted(date: .complete, time: .standard)).font(.headline)
                Text("\(durationText) · \(session.chatCount) chats · \(session.challengesPassed) passed / \(session.challengesFailed) failed · \(session.hintsUsed) hints · \(session.coursesTouched) courses")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Button {
                    exportSession()
                } label: {
                    Label("Export HTML", systemImage: "square.and.arrow.up")
                }
                if let exportNote { Text(exportNote).font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .padding(12)
    }

    private var durationText: String {
        session.duration.map { "\(Int($0 / 60)) min" } ?? "in progress"
    }

    // MARK: - Timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12).padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(filteredEvents.enumerated()), id: \.offset) { _, event in
                        HStack(alignment: .top, spacing: 8) {
                            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption.monospaced()).foregroundStyle(.tertiary).frame(width: 70, alignment: .leading)
                            Text(event.type.rawValue).font(.caption.bold()).foregroundStyle(color(for: event.type)).frame(width: 130, alignment: .leading)
                            Text(SessionExport.describe(event)).font(.caption).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private var filteredEvents: [LogEvent] {
        session.events.filter { event in
            switch filter {
            case .all: return true
            case .chat: return event.type == .chatUser || event.type == .chatAssistant
            case .shell: return [.shellStdin, .shellStdout, .shellStderr].contains(event.type)
            case .lessons: return [.lessonStart, .lessonComplete, .challengeAttempt, .challengePass, .challengeFail, .hintUsed, .skipUsed, .courseGenerated].contains(event.type)
            }
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(Array(chatEvents.enumerated()), id: \.offset) { _, event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.type == .chatUser ? "Student" : "Claude")
                            .font(.caption.bold()).foregroundStyle(.secondary)
                        Text(event.string("text") ?? "").textSelection(.enabled)
                            .padding(8)
                            .background(event.type == .chatUser ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(12)
        }
    }

    private var chatEvents: [LogEvent] {
        session.events.filter { $0.type == .chatUser || $0.type == .chatAssistant }
    }

    // MARK: - Terminal reconstruction

    private var terminal: some View {
        ScrollView {
            Text(reconstructedTerminal.isEmpty ? "No shell activity in this session." : reconstructedTerminal)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .background(Color.black.opacity(0.9))
        .foregroundStyle(Color(red: 0.85, green: 1.0, blue: 0.85))
    }

    private var reconstructedTerminal: String {
        session.events
            .filter { [.shellStdin, .shellStdout, .shellStderr].contains($0.type) }
            .compactMap { $0.string("text") }
            .joined()
    }

    private func color(for type: EventType) -> Color {
        switch type {
        case .chatUser: return .blue
        case .chatAssistant: return .green
        case .challengePass: return .green
        case .challengeFail: return .orange
        case .shellStdin, .shellStdout, .shellStderr: return .secondary
        default: return .primary
        }
    }

    private func exportSession() {
        do {
            let url = try SessionExport.write(session)
            NSWorkspace.shared.open(url)
            exportNote = "Saved to exports/"
        } catch {
            exportNote = "Export failed: \(error.localizedDescription)"
        }
    }
}

/// Per-course gradebook driven by the full course list, so the instructor can review
/// results and delete a course's history or the course itself.
private struct CourseResultsBrowser: View {
    @EnvironmentObject var session: AppSession
    @State private var selected: String?
    @State private var pendingHistoryDelete: Course?
    @State private var pendingCourseDelete: Course?

    var body: some View {
        // Reading resultsRevision refreshes the list/detail after a delete.
        let _ = session.resultsRevision
        NavigationSplitView {
            List(session.courses, id: \.id, selection: $selected) { course in
                courseRow(course).tag(course.id)
            }
            .navigationTitle("Courses")
            .frame(minWidth: 220)
        } detail: {
            if let id = selected, let course = session.courses.first(where: { $0.id == id }) {
                CourseResultsDetail(
                    course: course,
                    results: session.results(for: course.id),
                    onDeleteHistory: { pendingHistoryDelete = course },
                    onDeleteCourse: { pendingCourseDelete = course }
                )
            } else if session.courses.isEmpty {
                Text("No courses yet.").foregroundStyle(.secondary)
            } else {
                Text("Select a course.").foregroundStyle(.secondary)
            }
        }
        .alert("Delete course history?", isPresented: historyAlertBinding, presenting: pendingHistoryDelete) { course in
            Button("Delete History", role: .destructive) { session.deleteCourseHistory(courseId: course.id) }
            Button("Cancel", role: .cancel) {}
        } message: { course in
            Text("All saved lesson results for “\(course.title)” will be permanently removed. The course itself is kept.")
        }
        .alert("Delete course?", isPresented: courseAlertBinding, presenting: pendingCourseDelete) { course in
            Button("Delete Course", role: .destructive) {
                session.deleteCourse(courseId: course.id)
                if selected == course.id { selected = nil }
            }
            Button("Cancel", role: .cancel) {}
        } message: { course in
            Text("“\(course.title)” and its saved progress and results will be permanently removed.")
        }
    }

    private var historyAlertBinding: Binding<Bool> {
        Binding(get: { pendingHistoryDelete != nil }, set: { if !$0 { pendingHistoryDelete = nil } })
    }

    private var courseAlertBinding: Binding<Bool> {
        Binding(get: { pendingCourseDelete != nil }, set: { if !$0 { pendingCourseDelete = nil } })
    }

    private func courseRow(_ course: Course) -> some View {
        let results = session.results(for: course.id)
        return VStack(alignment: .leading, spacing: 2) {
            Text(course.title).font(.subheadline.bold())
            if let results {
                Text("✓ \(results.passedCount)/\(course.lessons.count) · attempt \(results.currentAttempt)")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("\(course.lessons.count) lessons · no results yet")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct CourseResultsDetail: View {
    let course: Course
    let results: CourseResults?
    let onDeleteHistory: () -> Void
    let onDeleteCourse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(course.title).font(.headline)
                    if let results, !results.attempts.isEmpty {
                        Text("Attempt \(results.currentAttempt) · \(results.passedCount)/\(course.lessons.count) lessons passed · \(results.attempts.count) total checks")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("\(course.lessons.count) lessons · no results yet")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    Button(role: .destructive, action: onDeleteHistory) {
                        Label("Delete History", systemImage: "trash")
                    }
                    .disabled(results?.attempts.isEmpty ?? true)
                    Button(role: .destructive, action: onDeleteCourse) {
                        Label("Delete Course", systemImage: "trash.fill")
                    }
                }
            }
            .padding(12)
            Divider()
            if let results, !results.attempts.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(sortedAttempts(results)) { a in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: a.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(a.passed ? .green : .orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Lesson \(a.lessonIdx + 1): \(a.lessonTitle)").font(.caption.bold())
                                    Text("attempt \(a.attempt) · \(a.timestamp.formatted(date: .abbreviated, time: .shortened))\(a.hintUsed ? " · used hint" : "")")
                                        .font(.caption2).foregroundStyle(.tertiary)
                                    if !a.command.isEmpty {
                                        Text("$ \(a.command)").font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                                    }
                                    Text(a.detail).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                }
            } else {
                Text("No saved lesson results yet.")
                    .foregroundStyle(.secondary)
                    .padding(12)
                Spacer()
            }
        }
    }

    private func sortedAttempts(_ results: CourseResults) -> [LessonAttempt] {
        results.attempts.sorted { $0.timestamp > $1.timestamp }
    }
}
