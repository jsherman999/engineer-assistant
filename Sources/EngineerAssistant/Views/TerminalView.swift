import SwiftUI

struct TerminalView: View {
    @ObservedObject var controller: MacOSTerminalController
    @State private var input: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            output
            inputBar
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

    private var output: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(controller.entries) { entry in
                        line(for: entry).id(entry.id)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black)
            .onChange(of: controller.entries.count) { _, _ in
                if let last = controller.entries.last {
                    withAnimation(.linear(duration: 0.1)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 6) {
            Text("$")
                .font(.system(.body, design: .monospaced)).bold()
                .foregroundStyle(.secondary)
            TextField("type a command", text: $input)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .focused($focused)
                .onSubmit(run)
                .disabled(!controller.isRunning)
            Button("Run") { run() }
                .keyboardShortcut(.return)
                .disabled(!controller.isRunning || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(8)
        .background(.regularMaterial)
    }

    private func line(for entry: TerminalEntry) -> some View {
        let color: Color = {
            switch entry.kind {
            case .stdin: return Color(red: 0.55, green: 0.85, blue: 1.0)
            case .stdout: return Color(red: 0.85, green: 1.0, blue: 0.85)
            case .stderr: return Color(red: 1.0, green: 0.7, blue: 0.7)
            case .info: return Color(red: 1.0, green: 0.95, blue: 0.6)
            }
        }()
        let prefix: String = {
            switch entry.kind {
            case .stdin: return "$ "
            case .stdout, .stderr: return ""
            case .info: return "# "
            }
        }()
        return Text("\(prefix)\(entry.text)")
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(color)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func run() {
        let cmd = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return }
        input = ""
        controller.send(cmd)
        focused = true
    }
}
