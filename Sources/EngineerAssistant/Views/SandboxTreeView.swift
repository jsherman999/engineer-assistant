import SwiftUI

/// Live view of what's actually in the student's sandbox, beside the terminal.
///
/// `mkdir`, `touch`, and `rm` are abstract until you watch the tree change as you type them.
/// New entries flash green for a moment so the effect of the last command is obvious. Polling
/// (rather than FSEvents) keeps this working identically for the container case, where the
/// filesystem lives inside a Linux VM.
struct SandboxTreeView: View {
    let fileSystem: SandboxFileSystem
    /// Bumped by the owner whenever a command finishes, so the tree refreshes promptly instead
    /// of waiting out the poll interval.
    let refreshToken: Int

    @State private var paths: [String] = []
    @State private var recentlyAdded: Set<String> = []
    @State private var isCollapsed = false
    @State private var pollTask: Task<Void, Never>?

    private static let pollInterval: Duration = .milliseconds(1500)
    private static let maxDepth = 3
    private static let limit = 200

    var body: some View {
        VStack(spacing: 0) {
            header
            if !isCollapsed {
                ScrollView {
                    PathTreeView(paths: paths, highlighted: recentlyAdded)
                        .padding(8)
                }
            }
        }
        .background(Theme.workspace)
        .task(id: refreshToken) { await refresh() }
        .onAppear(perform: startPolling)
        .onDisappear { pollTask?.cancel() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.caption2)
                .foregroundStyle(Theme.concept)
            Text("YOUR FILES")
                .font(.caption2.bold()).tracking(1)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(paths.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isCollapsed.toggle() }
            } label: {
                Image(systemName: isCollapsed ? "chevron.up" : "chevron.down")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .help(isCollapsed ? "Show files" : "Hide files")
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Theme.bar)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
    }

    private func refresh() async {
        let latest = await fileSystem.listTree(maxDepth: Self.maxDepth, limit: Self.limit)
        guard latest != paths else { return }
        let added = Set(latest).subtracting(paths)
        paths = latest
        guard !added.isEmpty else { return }

        // Highlight what just appeared, then let it settle back.
        recentlyAdded = added
        Task {
            try? await Task.sleep(for: .seconds(2))
            recentlyAdded.subtract(added)
        }
    }
}
