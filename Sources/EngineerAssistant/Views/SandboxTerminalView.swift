import SwiftUI

/// SwiftUI host for the sandboxed PTY terminal, with a status bar and Reset control.
struct SandboxTerminalView: View {
    @ObservedObject var controller: SandboxTerminalController

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            TerminalHost(view: controller.view)
        }
        .sheet(item: $controller.pendingDangerousCommand) { danger in
            DestructiveCommandSheet(
                danger: danger,
                onCancel: { controller.cancelPendingCommand() },
                onRun: { controller.confirmPendingCommand() }
            )
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(controller.isRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text("TERMINAL")
                .font(.caption2.bold()).tracking(1)
                .foregroundStyle(Theme.terminalBarFg.opacity(0.9))
            Text(controller.statusMessage ?? "")
                .font(.caption).foregroundStyle(Theme.terminalBarFg.opacity(0.6))
                .lineLimit(1).truncationMode(.tail)
            Spacer()
            Button {
                controller.adjustFontSize(by: -1)
            } label: {
                Image(systemName: "textformat.size.smaller").font(.caption)
            }
            .buttonStyle(.borderless)
            .tint(Theme.terminalBarFg)
            .help("Smaller text")
            Button {
                controller.adjustFontSize(by: 1)
            } label: {
                Image(systemName: "textformat.size.larger").font(.caption)
            }
            .buttonStyle(.borderless)
            .tint(Theme.terminalBarFg)
            .help("Larger text")
            Button {
                controller.reset()
            } label: {
                Label("Reset Sandbox", systemImage: "arrow.counterclockwise")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .tint(Theme.terminalBarFg)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Theme.terminalBarBg)
    }
}

/// Shown instead of running a command that can't be undone. Framed as an explanation, not a
/// scolding — the student still gets to run it, but not by accident.
private struct DestructiveCommandSheet: View {
    let danger: DangerousCommand
    let onCancel: () -> Void
    let onRun: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title).foregroundStyle(.orange)
                Text("Hold on a second")
                    .font(.title2.bold())
            }

            Text(danger.command)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.black.opacity(0.85))
                .foregroundStyle(Color(red: 0.98, green: 0.72, blue: 0.55))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Text(danger.headline).font(.headline)
            Text(danger.explanation)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                Button("Cancel — let me rewrite it") { onCancel(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("I understand, run it") { onRun(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
            }
        }
        .padding(22)
        .frame(width: 520, height: 360)
    }
}

private struct TerminalHost: NSViewRepresentable {
    let view: SandboxTerminalProcessView

    func makeNSView(context: Context) -> SandboxTerminalProcessView { view }
    func updateNSView(_ nsView: SandboxTerminalProcessView, context: Context) {}
}
