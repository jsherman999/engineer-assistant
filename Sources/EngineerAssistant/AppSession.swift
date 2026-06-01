import Foundation
import SwiftUI

@MainActor
final class AppSession: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var currentMode: ChatMode = .ask
    @Published var isSending: Bool = false
    @Published var apiKeyConfigured: Bool = false
    @Published var sessionId: String? = nil
    @Published var lastError: String? = nil

    private let claude = ClaudeClient()
    private let store: EventStore = JSONLEventStore()

    func start() async {
        refreshAPIKeyStatus()
        do {
            let id = try await store.startSession()
            self.sessionId = id
        } catch {
            self.lastError = "Failed to start session: \(error.localizedDescription)"
        }
    }

    func refreshAPIKeyStatus() {
        apiKeyConfigured = !(Keychain.get(KeychainKeys.anthropicAPIKey) ?? "").isEmpty
    }

    func setAPIKey(_ key: String) throws {
        try Keychain.set(key, for: KeychainKeys.anthropicAPIKey)
        refreshAPIKeyStatus()
    }

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        guard let sessionId else { return }

        let userMsg = ChatMessage(role: .user, mode: currentMode, text: trimmed)
        messages.append(userMsg)
        let assistantMsg = ChatMessage(role: .assistant, mode: currentMode, text: "")
        messages.append(assistantMsg)
        let assistantId = assistantMsg.id

        isSending = true
        lastError = nil

        Task {
            await logChatEvent(.chatUser, mode: currentMode, text: trimmed, sessionId: sessionId)

            if currentMode == .course {
                appendChunk(to: assistantId, text: "Course Mode is coming in Phase 2. Switch to Ask Mode to chat now.")
                await logChatEvent(.chatAssistant, mode: .course, text: messages.last?.text ?? "", sessionId: sessionId)
                isSending = false
                return
            }

            let history = messages.dropLast()
            do {
                let stream = claude.streamAskResponse(history: Array(history))
                for try await chunk in stream {
                    appendChunk(to: assistantId, text: chunk.text)
                }
                let finalText = messages.first(where: { $0.id == assistantId })?.text ?? ""
                await logChatEvent(.chatAssistant, mode: .ask, text: finalText, sessionId: sessionId)
            } catch {
                lastError = error.localizedDescription
                appendChunk(to: assistantId, text: "\n\n_Error: \(error.localizedDescription)_")
            }
            isSending = false
        }
    }

    private func appendChunk(to id: UUID, text: String) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].text += text
    }

    private func logChatEvent(_ type: EventType, mode: ChatMode, text: String, sessionId: String) async {
        let event = LogEvent(
            sessionId: sessionId,
            timestamp: Date(),
            type: type,
            courseId: nil,
            lessonIdx: nil,
            payload: [
                "text": AnyCodable(text),
                "mode": AnyCodable(mode.rawValue)
            ]
        )
        do { try await store.append(event) }
        catch { lastError = "Log error: \(error.localizedDescription)" }
    }
}
