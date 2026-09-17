import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var typeSafeKey: String = ""
    @State private var typeSafeConfigured: Bool = TypeSafeClient.isConfigured
    @State private var saveError: String?
    @State private var pinResetNote: String?

    private var hasPendingEdits: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !typeSafeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
                Text("TypeSafe API Key (optional)")
                    .font(.headline)
                Text("Screens generated courses for challenges the sandbox can't support, before they're saved. Without a key, courses generate exactly as before.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("apikey_… (optional)", text: $typeSafeKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    if typeSafeConfigured {
                        Label("Course screening on", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green).font(.caption)
                    } else {
                        Label("Course screening off", systemImage: "minus.circle")
                            .foregroundStyle(.secondary).font(.caption)
                    }
                    Spacer()
                    Button("Clear") {
                        Keychain.delete(KeychainKeys.typeSafeAPIKey)
                        typeSafeConfigured = false
                    }
                    .disabled(!typeSafeConfigured)
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
                    .disabled(!hasPendingEdits)
            }
        }
        .padding(20)
        .frame(width: 460, height: 580)
    }

    /// Saves whichever keys were actually typed, so either can be set without clearing the other.
    private func save() {
        let anthropic = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let typeSafe = typeSafeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if !anthropic.isEmpty {
                try session.setAPIKey(anthropic)
                apiKey = ""
            }
            if !typeSafe.isEmpty {
                try Keychain.set(typeSafe, for: KeychainKeys.typeSafeAPIKey)
                typeSafeKey = ""
                typeSafeConfigured = true
            }
            dismiss()
        } catch {
            saveError = "Could not save key: \(error.localizedDescription)"
        }
    }
}
