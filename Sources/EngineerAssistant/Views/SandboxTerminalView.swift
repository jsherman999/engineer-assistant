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
            Text(controller.statusMessage ?? "Terminal")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button {
                controller.reset()
            } label: {
                Label("Reset Sandbox", systemImage: "arrow.counterclockwise")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(.regularMaterial)
    }
}

private struct TerminalHost: NSViewRepresentable {
    let view: SandboxTerminalProcessView

    func makeNSView(context: Context) -> SandboxTerminalProcessView { view }
    func updateNSView(_ nsView: SandboxTerminalProcessView, context: Context) {}
}
