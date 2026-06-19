import Foundation
import SwiftTerm

/// Owns the sandboxed PTY-backed terminal view, tees its I/O into the event log,
/// and tracks the last command / exit code / stdout for challenge verification.
@MainActor
final class MacOSTerminalController: ObservableObject {
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var statusMessage: String? = nil
    @Published private(set) var lastExitCode: Int? = nil

    let workingDirectory: URL
    let courseId: String
    let view: SandboxTerminalProcessView

    private let sessionId: String
    private let eventStore: EventStore
    private var parser = ShellTeeParser()
    private var profileURL: URL?

    /// Stdout of the most recently completed command (marker-stripped). Used by the verifier.
    private(set) var lastStdout: String = ""
    /// The most recent command the student ran (from the preexec marker).
    private(set) var lastCommand: String? = nil
    /// Rolling transcript of rendered output, for the `llm_judge` verifier.
    private(set) var transcript: String = ""

    private static let transcriptCap = 20_000

    init(courseId: String, sessionId: String, eventStore: EventStore) throws {
        self.courseId = courseId
        self.sessionId = sessionId
        self.eventStore = eventStore
        let dir = AppPaths.sandboxesDir.appendingPathComponent(courseId, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.workingDirectory = dir
        self.view = SandboxTerminalProcessView(frame: CGRect(x: 0, y: 0, width: 640, height: 280))
        self.view.coordinator = self
    }

    func start() throws {
        guard !isRunning else { return }
        let profile = SandboxProfile.macOSProfile(sandboxDir: workingDirectory.path)
        let profileURL = workingDirectory.appendingPathComponent(".sandbox.sb")
        try profile.write(to: profileURL, atomically: true, encoding: .utf8)
        self.profileURL = profileURL
        try Self.writeZshrc(to: workingDirectory)

        view.startProcess(
            executable: "/usr/bin/sandbox-exec",
            args: ["-f", profileURL.path, "/bin/zsh", "-i"],
            environment: [
                "HOME=\(workingDirectory.path)",
                "ZDOTDIR=\(workingDirectory.path)",
                "PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                "TERM=xterm-256color",
                "LANG=en_US.UTF-8"
            ],
            currentDirectory: workingDirectory.path
        )
        isRunning = true
        statusMessage = "Sandboxed zsh — writes confined to \(workingDirectory.lastPathComponent)/, network blocked."
    }

    func stop() {
        view.terminate()
        if let url = profileURL { try? FileManager.default.removeItem(at: url) }
        profileURL = nil
        isRunning = false
        statusMessage = "Shell stopped."
    }

    func reset() {
        view.terminate()
        let contents = (try? FileManager.default.contentsOfDirectory(at: workingDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in contents { try? FileManager.default.removeItem(at: url) }
        parser = ShellTeeParser()
        lastExitCode = nil
        lastStdout = ""
        lastCommand = nil
        transcript = ""
        view.getTerminal().resetToInitialState()
        isRunning = false
        do {
            try start()
        } catch {
            statusMessage = "Reset failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Tee callbacks (invoked on the main queue by SandboxTerminalProcessView)

    func ingestInput(_ data: ArraySlice<UInt8>) {
        log(.shellStdin, data: Data(data))
    }

    /// Parses PTY output, records exit code / stdout, logs the clean text, and returns
    /// the marker-stripped bytes to render.
    func ingestOutput(_ data: ArraySlice<UInt8>) -> [UInt8] {
        let parsed = parser.consume(data)
        if !parsed.display.isEmpty {
            let text = String(decoding: parsed.display, as: UTF8.self)
            transcript += text
            if transcript.count > Self.transcriptCap {
                transcript = String(transcript.suffix(Self.transcriptCap))
            }
            log(.shellStdout, data: Data(parsed.display))
        }
        for event in parsed.events {
            switch event {
            case .started(let cmd):
                lastCommand = cmd
            case .finished(let code, let output):
                lastExitCode = code
                lastStdout = output
            }
        }
        return parsed.display
    }

    func handleProcessTerminated() {
        // Ignore stale terminations from a process we already replaced (e.g. during reset).
        guard !(view.process?.running ?? false) else { return }
        isRunning = false
        statusMessage = "Shell exited."
    }

    // MARK: - Helpers

    private func log(_ type: EventType, data: Data) {
        let courseId = self.courseId
        let sessionId = self.sessionId
        let store = self.eventStore
        Task.detached {
            let event = LogEvent(
                sessionId: sessionId,
                timestamp: Date(),
                type: type,
                courseId: courseId,
                lessonIdx: nil,
                payload: [
                    "bytes_b64": AnyCodable(data.base64EncodedString()),
                    "text": AnyCodable(String(decoding: data, as: UTF8.self))
                ]
            )
            try? await store.append(event)
        }
    }

    /// Writes a `.zshrc` into the sandbox (its HOME/ZDOTDIR) that defines the prompt and
    /// the preexec/precmd hooks emitting the markers `ShellTeeParser` consumes.
    private static func writeZshrc(to dir: URL) throws {
        let zshrc = """
        PROMPT='%~ %# '
        preexec() { printf '\\001EAC:%s\\001' "$1" }
        precmd()  { printf '\\001EAX:%d\\001' $? }
        """
        try zshrc.write(to: dir.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
    }
}
