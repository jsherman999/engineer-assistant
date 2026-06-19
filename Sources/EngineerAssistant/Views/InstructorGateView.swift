import SwiftUI

/// PIN gate for the instructor dashboard: first-run setup (with a one-time recovery code),
/// login, and recovery-code reset. Shows the dashboard once unlocked.
struct InstructorGateView: View {
    @Environment(\.dismiss) private var dismiss

    enum Phase { case setup, showRecovery, login, recover, unlocked }
    @State private var phase: Phase = InstructorAuth.isConfigured() ? .login : .setup

    @State private var pin = ""
    @State private var confirmPin = ""
    @State private var recoveryInput = ""
    @State private var generatedRecovery = ""
    @State private var error: String?

    var body: some View {
        Group {
            switch phase {
            case .unlocked: InstructorDashboardView()
            case .setup: form(title: "Create Instructor PIN", content: setupContent)
            case .showRecovery: form(title: "Save Your Recovery Code", content: recoveryDisplay)
            case .login: form(title: "Instructor PIN", content: loginContent)
            case .recover: form(title: "Reset PIN", content: recoverContent)
            }
        }
        .frame(width: 720, height: 540)
    }

    private func form<C: View>(title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
                Button("Close") { dismiss() }
            }
            content()
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            Spacer()
        }
        .padding(24)
    }

    private func setupContent() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set a 4–6 digit PIN. The student won't see the dashboard unless this PIN is entered.")
                .font(.callout).foregroundStyle(.secondary)
            SecureField("New PIN", text: $pin).textFieldStyle(.roundedBorder).frame(width: 200)
            SecureField("Confirm PIN", text: $confirmPin).textFieldStyle(.roundedBorder).frame(width: 200)
            Button("Create PIN") {
                guard InstructorAuth.isValidPIN(pin) else { error = "PIN must be 4–6 digits."; return }
                guard pin == confirmPin else { error = "PINs don't match."; return }
                generatedRecovery = InstructorAuth.setupPIN(pin)
                error = nil; pin = ""; confirmPin = ""
                phase = .showRecovery
            }
            .keyboardShortcut(.return)
        }
    }

    private func recoveryDisplay() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Write this down now. It's the only way to reset the PIN if you forget it — it is not shown again.")
                .font(.callout).foregroundStyle(.secondary)
            Text(generatedRecovery)
                .font(.system(.title, design: .monospaced)).bold()
                .textSelection(.enabled)
                .padding(12)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Button("I've saved it — open dashboard") { phase = .unlocked }
                .keyboardShortcut(.return)
        }
    }

    private func loginContent() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SecureField("PIN", text: $pin).textFieldStyle(.roundedBorder).frame(width: 200)
                .onSubmit(attemptLogin)
            HStack {
                Button("Unlock", action: attemptLogin).keyboardShortcut(.return)
                Button("Forgot PIN?") { error = nil; phase = .recover }
                    .buttonStyle(.borderless)
            }
        }
    }

    private func recoverContent() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Enter your recovery code and a new PIN.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Recovery code (XXXX-XXXX-XXXX)", text: $recoveryInput)
                .textFieldStyle(.roundedBorder).frame(width: 280)
            SecureField("New PIN", text: $pin).textFieldStyle(.roundedBorder).frame(width: 200)
            HStack {
                Button("Reset PIN") {
                    if InstructorAuth.resetPIN(usingRecovery: recoveryInput, newPIN: pin) {
                        error = nil; phase = .unlocked
                    } else {
                        error = "Recovery code invalid or PIN not 4–6 digits."
                    }
                }
                .keyboardShortcut(.return)
                Button("Back") { error = nil; phase = .login }.buttonStyle(.borderless)
            }
        }
    }

    private func attemptLogin() {
        if InstructorAuth.verifyPIN(pin) {
            error = nil; phase = .unlocked
        } else {
            error = "Incorrect PIN."
        }
        pin = ""
    }
}
