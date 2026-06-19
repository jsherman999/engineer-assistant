import SwiftUI
import AppKit

struct InstructorDashboardView: View {
    @State private var sessions: [InstructorSession] = []
    @State private var selected: InstructorSession.ID?

    var body: some View {
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
