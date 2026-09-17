import SwiftUI

/// Sysadmin helper: narrows a real log down to the few things worth looking at.
///
/// The funnel itself is the lesson, so the counts are shown rather than hidden — going from
/// 261,205 lines to 152 distinct problems to one that matters is the skill being taught, and a
/// student who only sees the answer learns nothing about how it was found.
struct LogTriageView: View {
    @EnvironmentObject var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var customPath: String = ""
    @State private var selected: LogProblem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            picker
            if let error = session.logTriageError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let result = session.logTriage {
                funnel(result)
                Divider()
                problemList(result)
            } else if session.logTriageScanning {
                ProgressView("Reading the log…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                placeholder
            }
            Divider()
            HStack {
                privacyNote
                Spacer()
                Button("Close") { dismiss() }
            }
        }
        .padding(18)
        .frame(width: 760, height: 620)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Log Triage").font(.title2.bold())
            Text("A real log has tens of thousands of lines and maybe three that matter. This finds them the way an administrator would: match the problem words, collapse the repeats, then judge what's left.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var picker: some View {
        HStack(spacing: 8) {
            ForEach(LogTriage.readablePaths(), id: \.self) { path in
                Button((path as NSString).lastPathComponent) {
                    selected = nil
                    session.triageLog(at: path)
                }
                .disabled(session.logTriageScanning || session.logTriageRanking)
            }
            TextField("or a path…", text: $customPath)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .onSubmit { runCustom() }
            Button("Scan") { runCustom() }
                .disabled(customPath.trimmingCharacters(in: .whitespaces).isEmpty
                          || session.logTriageScanning || session.logTriageRanking)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text("Pick a log to triage.").foregroundStyle(.secondary)
            Text("`/var/log/install.log` is usually the biggest and the most interesting.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The reduction, stated plainly. This is the part worth learning.
    private func funnel(_ result: TriageResult) -> some View {
        HStack(spacing: 0) {
            stage("\(result.totalLines.formatted())",
                  result.readTruncated ? "lines read (last 8 MB)" : "lines in the file", Theme.concept)
            arrow
            stage("\(result.matchedLines.formatted())", "mention a problem", Theme.practice)
            arrow
            stage("\(result.problems.count)\(result.truncated ? "+" : "")", "distinct problems", Theme.demos)
            if session.logTriageRanking {
                arrow
                VStack(spacing: 3) {
                    ProgressView().controlSize(.small)
                    Text("ranking").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            } else if result.ranked {
                arrow
                stage(result.seriousness.map { String(format: "%.0f%%", $0 * 100) } ?? "—",
                      "chance something here is real", Theme.finalChallenge)
            }
        }
        .padding(.vertical, 4)
    }

    private func stage(_ value: String, _ caption: String, _ accent: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(accent)
            Text(caption).font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var arrow: some View {
        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
    }

    @ViewBuilder
    private func problemList(_ result: TriageResult) -> some View {
        if result.problems.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(.green)
                Text("Nothing in this log matches a problem pattern.")
                    .foregroundStyle(.secondary)
                Text("That is a real answer, not a failure — most log lines are the machine saying it is fine.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(result.ranked ? "MOST WORTH A LOOK FIRST" : "MOST RECENT FIRST")
                        .font(.caption2.bold()).tracking(0.8).foregroundStyle(.secondary)
                    if !result.ranked && TypeSafeClient.isConfigured == false {
                        Text("— add a TypeSafe key in Settings to have these ranked")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if result.truncated {
                        Text("showing the \(LogTriage.maxProblems) most recent kinds")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(result.problems) { problem in
                            row(problem, ranked: result.ranked, tailOnly: result.readTruncated)
                        }
                    }
                }
            }
        }
    }

    private func row(_ problem: LogProblem, ranked: Bool, tailOnly: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(problem.category.label.uppercased())
                    .font(.caption2.bold())
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(color(problem.category).opacity(0.18))
                    .foregroundStyle(color(problem.category))
                    .clipShape(Capsule())
                if problem.occurrences > 1 {
                    Text("×\(problem.occurrences.formatted())")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(tailOnly ? "line \(problem.lastLine.formatted()) of tail"
                              : "line \(problem.lastLine.formatted())")
                    .font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                if ranked && problem.weight > 0.01 {
                    Text(String(format: "%.0f%%", problem.weight * 100))
                        .font(.caption2.bold().monospacedDigit())
                        .foregroundStyle(problem.weight > 0.2 ? Theme.finalChallenge : .secondary)
                }
            }
            Text(problem.example)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(selected == problem ? nil : 2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(7)
        .background(selected == problem ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { selected = (selected == problem ? nil : problem) }
    }

    private func color(_ category: LogCategory) -> Color {
        switch category {
        case .failure: return Theme.practice
        case .resource: return Theme.concept
        case .crash: return Theme.finalChallenge
        case .security: return Theme.challenge
        }
    }

    private var privacyNote: some View {
        Text(TypeSafeClient.isConfigured
             ? "Only the deduplicated problem lines leave this Mac — never the whole log."
             : "Everything here runs locally; nothing leaves this Mac.")
            .font(.caption2).foregroundStyle(.tertiary)
    }

    private func runCustom() {
        let path = customPath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return }
        selected = nil
        session.triageLog(at: path)
    }
}
