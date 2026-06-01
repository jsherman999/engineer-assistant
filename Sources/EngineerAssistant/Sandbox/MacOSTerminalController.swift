import Foundation
import SwiftUI

struct TerminalEntry: Identifiable, Equatable {
    let id = UUID()
    let kind: Kind
    let text: String
    enum Kind { case stdin, stdout, stderr, info }
}

@MainActor
final class MacOSTerminalController: ObservableObject {
    @Published private(set) var entries: [TerminalEntry] = []
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var statusMessage: String? = nil

    let workingDirectory: URL
    let courseId: String
    private let sessionId: String
    private let eventStore: EventStore
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var profileURL: URL?

    init(courseId: String, sessionId: String, eventStore: EventStore) throws {
        self.courseId = courseId
        self.sessionId = sessionId
        self.eventStore = eventStore
        let dir = AppPaths.sandboxesDir.appendingPathComponent(courseId, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.workingDirectory = dir
    }

    func start() throws {
        guard process == nil else { return }
        let profile = SandboxProfile.macOSProfile(sandboxDir: workingDirectory.path)
        let profileURL = workingDirectory.appendingPathComponent(".sandbox.sb")
        try profile.write(to: profileURL, atomically: true, encoding: .utf8)
        self.profileURL = profileURL

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        proc.arguments = ["-f", profileURL.path, "/bin/zsh"]
        proc.currentDirectoryURL = workingDirectory
        proc.environment = [
            "HOME": workingDirectory.path,
            "ZDOTDIR": workingDirectory.path,
            "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "TERM": "dumb",
            "PS1": "$ ",
            "LANG": "en_US.UTF-8"
        ]

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        let courseId = self.courseId
        let sessionId = self.sessionId
        let store = self.eventStore

        stdout.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.handleOutput(data, kind: .stdout)
            }
            Task.detached {
                await Self.log(.shellStdout, data: data, courseId: courseId, sessionId: sessionId, store: store)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.handleOutput(data, kind: .stderr)
            }
            Task.detached {
                await Self.log(.shellStderr, data: data, courseId: courseId, sessionId: sessionId, store: store)
            }
        }

        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTermination()
            }
        }

        try proc.run()

        process = proc
        stdinPipe = stdin
        stdoutPipe = stdout
        stderrPipe = stderr
        isRunning = true
        statusMessage = "Sandboxed zsh running at \(workingDirectory.lastPathComponent)/  (writes confined here; network blocked)"
        appendInfo("Welcome. This shell is sandboxed: you can read most system files, but you can only write inside this directory. Network is blocked.")
    }

    func send(_ command: String) {
        guard let stdin = stdinPipe else { return }
        let line = command + "\n"
        guard let data = line.data(using: .utf8) else { return }
        do {
            try stdin.fileHandleForWriting.write(contentsOf: data)
        } catch {
            appendInfo("Failed to send command: \(error.localizedDescription)")
            return
        }
        appendInput(command)
        let courseId = self.courseId
        let sessionId = self.sessionId
        let store = self.eventStore
        Task.detached {
            await Self.log(.shellStdin, data: data, courseId: courseId, sessionId: sessionId, store: store)
        }
    }

    func reset() {
        stop()
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: workingDirectory, includingPropertiesForKeys: nil)
            for url in contents {
                try? FileManager.default.removeItem(at: url)
            }
            try start()
            entries.removeAll()
            appendInfo("Sandbox reset.")
        } catch {
            statusMessage = "Reset failed: \(error.localizedDescription)"
        }
    }

    func stop() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        if let url = profileURL { try? FileManager.default.removeItem(at: url) }
        profileURL = nil
        isRunning = false
        statusMessage = "Shell stopped."
    }

    private func handleOutput(_ data: Data, kind: TerminalEntry.Kind) {
        let text = String(data: data, encoding: .utf8) ?? ""
        if text.isEmpty { return }
        entries.append(TerminalEntry(kind: kind, text: text))
    }

    private func handleTermination() {
        isRunning = false
        statusMessage = "Shell exited."
        appendInfo("Shell exited.")
    }

    private func appendInput(_ command: String) {
        entries.append(TerminalEntry(kind: .stdin, text: command))
    }

    private func appendInfo(_ text: String) {
        entries.append(TerminalEntry(kind: .info, text: text))
    }

    private static func log(_ type: EventType, data: Data, courseId: String, sessionId: String, store: EventStore) async {
        let event = LogEvent(
            sessionId: sessionId,
            timestamp: Date(),
            type: type,
            courseId: courseId,
            lessonIdx: nil,
            payload: [
                "bytes_b64": AnyCodable(data.base64EncodedString()),
                "text": AnyCodable(String(data: data, encoding: .utf8) ?? "")
            ]
        )
        try? await store.append(event)
    }
}
