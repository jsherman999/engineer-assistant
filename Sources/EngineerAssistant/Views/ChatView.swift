import SwiftUI

struct ChatView: View {
    @EnvironmentObject var session: AppSession
    @State private var input: String = ""

    var body: some View {
        VStack(spacing: 0) {
            modePicker
            Divider()
            HStack(spacing: 0) {
                chatColumn
                // Ask mode: a live sandbox shell beside the chat for trying the commands.
                if session.currentMode == .ask, let term = session.askTerminal {
                    Divider()
                    SandboxTerminalView(controller: term)
                        .frame(minWidth: 340, idealWidth: 440, maxWidth: 560)
                }
            }
        }
    }

    private var chatColumn: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            inputBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var modePicker: some View {
        HStack {
            Picker("Mode", selection: $session.currentMode) {
                ForEach(ChatMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
            .disabled(session.isSending)
            Spacer()
            if let err = session.lastError {
                Text(err)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(8)
        .background(Theme.headerTint.opacity(0.07))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.headerTint.opacity(0.25)).frame(height: 1)
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(session.messages) { msg in
                        MessageBubble(message: msg).id(msg.id)
                    }
                }
                .padding(12)
            }
            .onChange(of: session.messages.last?.text) { _, _ in
                if let last = session.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder, text: $input, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...6)
                .disabled(session.isSending || !session.apiKeyConfigured)
                .onSubmit(send)
            Button(action: send) {
                if session.isSending {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "paperplane.fill")
                }
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.isSending || !session.apiKeyConfigured)
        }
        .padding(10)
        .background(.regularMaterial)
    }

    private var placeholder: String {
        if !session.apiKeyConfigured {
            return "Open Settings to add your Anthropic API key…"
        }
        switch session.currentMode {
        case .ask: return "Ask anything about MacOS, Linux, sysadmin, or coding…"
        case .course: return "What topic do you want a course on?"
        }
    }

    private func send() {
        let text = input
        input = ""
        session.send(text)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 60) }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(message.role == .user ? "You" : "Claude")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(message.mode.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(message.text.isEmpty ? "…" : message.text)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(message.role == .user ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            if message.role == .assistant { Spacer(minLength: 60) }
        }
    }
}
