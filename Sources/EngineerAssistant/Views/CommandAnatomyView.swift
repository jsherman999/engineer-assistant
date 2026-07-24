import SwiftUI
import AppKit

/// A demo command whose flags and arguments can be taken apart in place.
///
/// `tar -xzf archive.tar.gz` is four separate ideas wearing one costume. Annotated tokens get an
/// underline and reveal their meaning on click, so the student learns the pieces instead of
/// memorising the whole string. Falls back to a plain command row when the course supplied no
/// breakdown, so older cached courses still render.
struct CommandAnatomyView: View {
    let command: String
    let parts: [CommandPart]?

    @State private var selectedToken: String?
    @State private var copied = false

    private var meanings: [String: String] {
        Dictionary(parts?.map { ($0.token, $0.meaning) } ?? [], uniquingKeysWith: { first, _ in first })
    }

    private var tokens: [String] {
        command.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            commandRow
            if let selectedToken, let meaning = meanings[selectedToken] {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(selectedToken)
                        .font(.system(.caption, design: .monospaced).bold())
                        .foregroundStyle(Theme.demos)
                    Text(meaning)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 4)
                .transition(.opacity)
            } else if !meanings.isEmpty {
                Text("Click any underlined part to see what it does.")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: selectedToken)
    }

    private var commandRow: some View {
        HStack(alignment: .top, spacing: 8) {
            FlowLayout(spacing: 0) {
                Text("$ ")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Theme.codePrompt)
                ForEach(Array(tokens.enumerated()), id: \.offset) { idx, token in
                    tokenView(token, isLast: idx == tokens.count - 1)
                }
            }
            copyButton
        }
        .padding(8)
        .background(Theme.codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private func tokenView(_ token: String, isLast: Bool) -> some View {
        let annotated = meanings[token] != nil
        let isSelected = selectedToken == token
        Text(token + (isLast ? "" : " "))
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(annotated ? (isSelected ? Theme.demos : Theme.codeForeground) : Theme.codeForeground)
            .overlay(alignment: .bottom) {
                if annotated {
                    Rectangle()
                        .fill(isSelected ? Theme.demos : Theme.demos.opacity(0.5))
                        .frame(height: isSelected ? 2 : 1)
                        .padding(.trailing, isLast ? 0 : 4)
                        .offset(y: 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard annotated else { return }
                selectedToken = isSelected ? nil : token
            }
            .help(meanings[token] ?? "")
    }

    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .foregroundStyle(copied ? Theme.codePrompt : Theme.codeControl)
        }
        .buttonStyle(.borderless)
        .help("Copy command")
    }
}
