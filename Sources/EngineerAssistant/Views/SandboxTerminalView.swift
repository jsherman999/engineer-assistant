import SwiftUI

/// SwiftUI host for the sandboxed PTY terminal, with a status bar and Reset control.
struct SandboxTerminalView: View {
    @ObservedObject var controller: SandboxTerminalController

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            TerminalHost(view: controller.view)
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

private struct TerminalHost: NSViewRepresentable {
    let view: SandboxTerminalProcessView

    func makeNSView(context: Context) -> SandboxTerminalProcessView { view }
    func updateNSView(_ nsView: SandboxTerminalProcessView, context: Context) {}
}
