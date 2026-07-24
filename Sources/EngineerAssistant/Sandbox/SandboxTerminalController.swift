import Foundation
import AppKit
import SwiftTerm

enum SandboxError: LocalizedError {
    case noContainerRuntime
    var errorDescription: String? {
        switch self {
        case .noContainerRuntime: return "No container engine is installed for Linux courses."
        }
    }
}

/// Owns the sandboxed PTY-backed terminal view, tees its I/O into the event log, and
/// tracks the last command / exit code / stdout for challenge verification. Backs both
/// macOS courses (sandbox-exec + zsh) and Linux courses (a container engine + bash).
@MainActor
final class SandboxTerminalController: ObservableObject {
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var statusMessage: String? = nil
    @Published private(set) var lastExitCode: Int? = nil
    /// Set when the student pressed Return on a command that can't be undone; the view shows
    /// an explanation and the Return is held until they decide.
    @Published var pendingDangerousCommand: DangerousCommand? = nil
    /// Increments as each command completes, so views that mirror sandbox state (the file tree)
    /// can refresh right away instead of waiting out a poll interval.
    @Published private(set) var completedCommands: Int = 0
    /// Terminal font size, adjustable by the student — the default is small on a big display.
    @Published private(set) var fontSize: CGFloat

    let workingDirectory: URL
    let courseId: String
    let environment: CourseEnvironment
    /// When false (Ask mode), the macOS shell runs unsandboxed with full access; when true
    /// (Course mode), it runs under sandbox-exec with writes confined and network blocked.
    let confined: Bool
    let view: SandboxTerminalProcessView
    /// Typing in the shell counts as student activity for the idle-session timer.
    var onActivity: (() -> Void)?

    private let sessionId: String
    private let eventStore: EventStore
    private let runtime: ContainerRuntime?
    private var parser = ShellTeeParser()
    private var profileURL: URL?
    /// Tail of the serialized chain of pending event-log writes (see `log`).
    private var logTail: Task<Void, Never>?
    /// The command line being typed, reconstructed from keystrokes (see `trackLine`).
    private var lineBuffer: String = ""

    private static let linuxImage = "docker.io/library/ubuntu:latest"
    /// PATH including Homebrew (Apple Silicon + Intel) so host-installed tools resolve.
    private static let macPATH = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

    /// Stdout of the most recently completed command (marker-stripped). Used by the verifier.
    private(set) var lastStdout: String = ""
    /// The most recent command the student ran (macOS only; Linux uses exit markers alone).
    private(set) var lastCommand: String? = nil
    /// Rolling transcript of rendered output, for the `llm_judge` verifier.
    private(set) var transcript: String = ""

    private static let transcriptCap = 20_000

    static func containerName(forCourseId courseId: String) -> String { "ea-\(courseId.lowercased())" }
    private var containerName: String { Self.containerName(forCourseId: courseId) }

    /// File checks for the verifier: host filesystem on macOS, container `exec` on Linux.
    var fileSystem: SandboxFileSystem {
        switch environment {
        case .macos:
            return HostSandboxFileSystem(root: workingDirectory)
        case .linux:
            return ContainerFileSystem(enginePath: runtime?.path ?? "", containerName: containerName)
        }
    }

    init(courseId: String,
         environment: CourseEnvironment,
         workingDirectory: URL,
         sessionId: String,
         eventStore: EventStore,
         runtime: ContainerRuntime?,
         confined: Bool = true,
         fontSize: CGFloat = 11,
         foregroundColor: NSColor = Theme.terminalForegroundNS) throws {
        self.courseId = courseId
        self.environment = environment
        self.confined = confined
        self.sessionId = sessionId
        self.eventStore = eventStore
        self.runtime = runtime
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        self.workingDirectory = workingDirectory
        self.fontSize = fontSize
        self.view = SandboxTerminalProcessView(frame: CGRect(x: 0, y: 0, width: 640, height: 280))
        self.view.coordinator = self
        // Small monospaced font on a dark IDE-style palette.
        self.view.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        self.view.nativeBackgroundColor = Theme.terminalBackgroundNS
        self.view.nativeForegroundColor = foregroundColor
    }

    func start() throws {
        guard !isRunning else { return }
        switch environment {
        case .macos: try startMacOS()
        case .linux: try startLinux()
        }
        isRunning = true
    }

    private func startMacOS() throws {
        // Our minimal zshrc (short prompt + shell-integration markers) lives in the working
        // dir, used as ZDOTDIR in both modes.
        try Self.writeZshrc(to: workingDirectory)

        guard confined else { return try startMacOSUnrestricted() }

        let profile = SandboxProfile.macOSProfile(sandboxDir: workingDirectory.path)
        let profileURL = workingDirectory.appendingPathComponent(".sandbox.sb")
        try profile.write(to: profileURL, atomically: true, encoding: .utf8)
        self.profileURL = profileURL

        view.startProcess(
            executable: "/usr/bin/sandbox-exec",
            args: ["-f", profileURL.path, "/bin/zsh", "-i"],
            environment: [
                "HOME=\(workingDirectory.path)",
                "ZDOTDIR=\(workingDirectory.path)",
                // Homebrew on PATH so host-installed tools resolve; the sandbox allows read/exec
                // so they run, but network and writes outside the sandbox dir stay blocked.
                "PATH=\(Self.macPATH)",
                "TERM=xterm-256color",
                "LANG=en_US.UTF-8"
            ],
            currentDirectory: workingDirectory.path
        )
        statusMessage = "Sandboxed zsh — writes confined to \(workingDirectory.lastPathComponent)/; network allowed."
    }

    /// Ask mode: a full, unsandboxed shell in the user's real home with network and package
    /// installs allowed — a real Terminal for learning about this Mac. ZDOTDIR still points at
    /// our short-prompt zshrc so the prompt stays clean.
    private func startMacOSUnrestricted() throws {
        let home = NSHomeDirectory()
        view.startProcess(
            executable: "/bin/zsh",
            args: ["-i"],
            environment: [
                "HOME=\(home)",
                "ZDOTDIR=\(workingDirectory.path)",
                "PATH=\(Self.macPATH)",
                "TERM=xterm-256color",
                "LANG=en_US.UTF-8"
            ],
            currentDirectory: home
        )
        statusMessage = "Full shell — your Mac, unrestricted (network and installs allowed)."
    }

    private func startLinux() throws {
        guard let runtime else { throw SandboxError.noContainerRuntime }
        // Seed a .bashrc, then `exec bash -i` so the interactive shell reads it. This gets the
        // same shell integration macOS has: PROMPT_COMMAND emits the EAX exit-code marker
        // (reading $? FIRST so the code is the user command's), and a DEBUG trap emits the EAC
        // command marker so `lastCommand` is populated on Linux too — without it every Linux
        // challenge attempt was recorded with a blank command. PS1 is the clean
        // `student<N>:<dir>$` used for macOS courses instead of `root@ea-<uuid>:~#`.
        // The rc file travels as base64 so quoting survives the `bash -c` round-trip.
        let label = workingDirectory.lastPathComponent
        let bashrc = """
        PS1='\(label):\\w\\$ '
        PROMPT_COMMAND='printf "\\001EAX:%d\\001" $?'
        ea_debug() {
          case "$BASH_COMMAND" in
            *EAX*|ea_debug) return ;;
          esac
          printf '\\001EAC:%s\\001' "$BASH_COMMAND"
        }
        trap ea_debug DEBUG
        """
        let b64 = Data(bashrc.utf8).base64EncodedString()
        let bootstrap = "printf '%s' '\(b64)' | base64 -d > /root/.bashrc; exec bash -i"

        view.startProcess(
            executable: runtime.path,
            args: [
                "run", "--rm", "-it",
                "--name", containerName,
                "-w", "/root",
                Self.linuxImage,
                "bash", "-c", bootstrap
            ],
            environment: [
                "HOME=\(NSHomeDirectory())",
                "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
                "TERM=xterm-256color",
                "LANG=en_US.UTF-8"
            ],
            currentDirectory: nil
        )
        statusMessage = "\(runtime.displayName): launching Linux container (\(Self.linuxImage))… first run pulls the image. If it fails, run `\(runtime.engine.readinessHint)`."
    }

    /// Zoom the terminal. The default is deliberately small to fit a lot of output, which is
    /// hard to read across a room or on a scaled display.
    func adjustFontSize(by delta: CGFloat) {
        let next = min(max(fontSize + delta, 8), 24)
        guard next != fontSize else { return }
        fontSize = next
        view.font = NSFont.monospacedSystemFont(ofSize: next, weight: .regular)
    }

    func stop() {
        view.terminate()
        switch environment {
        case .macos:
            if let url = profileURL { try? FileManager.default.removeItem(at: url) }
            profileURL = nil
        case .linux:
            forceRemoveContainer()
        }
        isRunning = false
        statusMessage = "Shell stopped."
    }

    func reset() {
        view.terminate()
        switch environment {
        case .macos:
            let contents = (try? FileManager.default.contentsOfDirectory(at: workingDirectory, includingPropertiesForKeys: nil)) ?? []
            for url in contents { try? FileManager.default.removeItem(at: url) }
        case .linux:
            forceRemoveContainer()
        }
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

    /// Logs the student's keystrokes and decides whether they reach the shell. Returns false to
    /// swallow the Return that would run a destructive command, holding it until the student
    /// confirms in `pendingDangerousCommand`.
    func ingestInput(_ data: ArraySlice<UInt8>) -> Bool {
        onActivity?()
        log(.shellStdin, data: Data(data))
        return trackLine(data)
    }

    /// Rebuilds the current command line from keystrokes so it can be checked before Return
    /// reaches the shell. Deliberately simple: it understands typing, backspace, and Ctrl-C/U,
    /// which is enough for the line shapes the guard cares about. Anything it mis-tracks fails
    /// open (the command runs) rather than blocking a legitimate command.
    private func trackLine(_ data: ArraySlice<UInt8>) -> Bool {
        for byte in data {
            switch byte {
            case 0x0d, 0x0a: // Return
                let line = lineBuffer
                lineBuffer = ""
                if pendingDangerousCommand == nil, let danger = DestructiveCommandGuard.evaluate(line) {
                    pendingDangerousCommand = danger
                    return false
                }
            case 0x7f, 0x08: // Backspace / Delete
                if !lineBuffer.isEmpty { lineBuffer.removeLast() }
            case 0x03, 0x15: // Ctrl-C, Ctrl-U
                lineBuffer = ""
            case 0x20...0x7e: // Printable ASCII
                lineBuffer.append(Character(UnicodeScalar(byte)))
            default:
                break // Arrow keys, escapes, UTF-8 continuation bytes: ignored.
            }
        }
        return true
    }

    /// Student chose to run it anyway — send the Return that was held back.
    func confirmPendingCommand() {
        guard let pending = pendingDangerousCommand else { return }
        pendingDangerousCommand = nil
        logGuardDecision(pending, ranAnyway: true)
        view.send(txt: "\r")
    }

    /// Student backed out — clear the line in the shell so the command can't run by accident.
    func cancelPendingCommand() {
        guard let pending = pendingDangerousCommand else { return }
        pendingDangerousCommand = nil
        logGuardDecision(pending, ranAnyway: false)
        lineBuffer = ""
        view.send(txt: "\u{15}") // Ctrl-U clears the line
    }

    private func logGuardDecision(_ command: DangerousCommand, ranAnyway: Bool) {
        let event = LogEvent(
            sessionId: sessionId,
            timestamp: Date(),
            type: .destructiveBlocked,
            courseId: courseId,
            lessonIdx: nil,
            payload: [
                "command": AnyCodable(command.command),
                "headline": AnyCodable(command.headline),
                "ran_anyway": AnyCodable(ranAnyway)
            ]
        )
        let store = self.eventStore
        Task { try? await store.append(event) }
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
                completedCommands += 1
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

    private func forceRemoveContainer() {
        guard let runtime else { return }
        let path = runtime.path
        let name = containerName
        Task.detached { _ = await ProcessRunner.run(path, ["rm", "-f", name]) }
    }

    /// Appends a PTY chunk to the event log. Chunks are chained onto `logTail` rather than
    /// dispatched independently: `Task.detached` per chunk would let two writes race and land
    /// out of order, which scrambles the instructor's terminal replay. Only `text` is stored —
    /// the previous `bytes_b64` copy doubled the size of a log that never rotates.
    private func log(_ type: EventType, data: Data) {
        let event = LogEvent(
            sessionId: sessionId,
            timestamp: Date(),
            type: type,
            courseId: courseId,
            lessonIdx: nil,
            payload: ["text": AnyCodable(String(decoding: data, as: UTF8.self))]
        )
        let store = self.eventStore
        let previous = logTail
        logTail = Task {
            await previous?.value
            try? await store.append(event)
        }
    }

    /// Writes a `.zshrc` into the macOS sandbox (its HOME/ZDOTDIR) defining the prompt and
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
