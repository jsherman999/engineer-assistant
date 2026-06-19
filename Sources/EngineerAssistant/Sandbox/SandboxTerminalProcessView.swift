import AppKit
import SwiftTerm

/// A `LocalProcessTerminalView` that tees the PTY in both directions into the event
/// log and strips shell-integration markers from the rendered output. All three
/// overridden callbacks are delivered on the main queue by SwiftTerm.
final class SandboxTerminalProcessView: LocalProcessTerminalView {
    weak var coordinator: SandboxTerminalController?

    override func send(source: TerminalView, data: ArraySlice<UInt8>) {
        MainActor.assumeIsolated { coordinator?.ingestInput(data) }
        super.send(source: source, data: data)
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        let clean = MainActor.assumeIsolated { coordinator?.ingestOutput(slice) } ?? Array(slice)
        feed(byteArray: clean[...])
    }

    override func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        super.processTerminated(source, exitCode: exitCode)
        MainActor.assumeIsolated { coordinator?.handleProcessTerminated() }
    }
}
