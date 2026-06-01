import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("Anthropic API Key")
                    .font(.headline)
                Text("Stored in the macOS Keychain. Get a key at console.anthropic.com.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("sk-ant-…", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                if let err = saveError {
                    Text(err).foregroundStyle(.red).font(.caption)
                }
                HStack {
                    if session.apiKeyConfigured {
                        Label("Key is set", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        Label("No key set", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                    Spacer()
                    Button("Clear") {
                        Keychain.delete(KeychainKeys.anthropicAPIKey)
                        session.refreshAPIKeyStatus()
                    }
                    .disabled(!session.apiKeyConfigured)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.return)
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460, height: 260)
    }

    private func save() {
        do {
            try session.setAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            apiKey = ""
            dismiss()
        } catch {
            saveError = "Could not save key: \(error.localizedDescription)"
        }
    }
}
