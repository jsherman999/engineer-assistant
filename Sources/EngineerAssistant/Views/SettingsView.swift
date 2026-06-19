import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var saveError: String?
    @State private var pinResetNote: String?

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

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Linux container engine").font(.headline)
                if let rt = session.containerRuntime {
                    Label("\(rt.displayName) detected", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green).font(.caption)
                } else {
                    Text("None detected — Linux courses are disabled. Install Apple's `container` (macOS 26+) or `brew install podman`.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Instructor dashboard").font(.headline)
                HStack {
                    Text(InstructorAuth.isConfigured() ? "PIN is set (open with ⌘⇧I)." : "No PIN set yet (⌘⇧I to set one).")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset PIN") {
                        for key in [KeychainKeys.instructorPinHash, KeychainKeys.instructorPinSalt,
                                    KeychainKeys.recoveryCodeHash, KeychainKeys.recoveryCodeSalt] {
                            Keychain.delete(key)
                        }
                        pinResetNote = "Instructor PIN cleared. Press ⌘⇧I to set a new one."
                    }
                    .disabled(!InstructorAuth.isConfigured())
                }
                if let pinResetNote {
                    Text(pinResetNote).font(.caption2).foregroundStyle(.secondary)
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
        .frame(width: 460, height: 460)
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
