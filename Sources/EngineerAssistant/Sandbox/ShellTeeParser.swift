import Foundation

enum TeeEvent: Equatable {
    case started(command: String)
    case finished(exitCode: Int, output: String)
}

struct TeeParsed: Equatable {
    let display: [UInt8]
    let events: [TeeEvent]
}

/// Parses a PTY byte stream, extracting shell-integration markers emitted by the
/// sandbox's zsh `preexec`/`precmd` hooks and stripping them from the rendered
/// output so they stay invisible. Markers (all ASCII, so UTF-8 safe to scan):
///   command start:  `\u{01}EAC:<command>\u{01}`
///   command end:    `\u{01}EAX:<-?digits>\u{01}`
/// `display` is the marker-free byte stream to feed the terminal; `events` report
/// each command's text and exit code, with the command's own stdout accumulated
/// between its start and end markers.
struct ShellTeeParser {
    private var buffer: [UInt8] = []
    private var currentOutput: [UInt8] = []

    private static let soh: UInt8 = 0x01
    private static let upperE: UInt8 = 0x45
    private static let upperA: UInt8 = 0x41
    private static let upperC: UInt8 = 0x43
    private static let upperX: UInt8 = 0x58
    private static let colon: UInt8 = 0x3A
    private static let minus: UInt8 = 0x2D

    private enum MarkerResult {
        case marker(TeeEvent, consumed: Int)
        case incomplete
        case invalid
    }

    mutating func consume(_ bytes: ArraySlice<UInt8>) -> TeeParsed {
        buffer.append(contentsOf: bytes)
        var display: [UInt8] = []
        var events: [TeeEvent] = []

        while true {
            guard let i = buffer.firstIndex(of: Self.soh) else {
                display.append(contentsOf: buffer)
                currentOutput.append(contentsOf: buffer)
                buffer.removeAll()
                break
            }
            if i > 0 {
                display.append(contentsOf: buffer[0..<i])
                currentOutput.append(contentsOf: buffer[0..<i])
                buffer.removeFirst(i)
            }
            switch Self.parseMarker(buffer) {
            case .marker(let event, let consumed):
                switch event {
                case .started:
                    currentOutput.removeAll()
                    events.append(event)
                case .finished(let code, _):
                    let output = String(decoding: currentOutput, as: UTF8.self)
                    events.append(.finished(exitCode: code, output: output))
                    currentOutput.removeAll()
                }
                buffer.removeFirst(consumed)
            case .incomplete:
                return TeeParsed(display: display, events: events) // keep partial marker for next read
            case .invalid:
                display.append(Self.soh)
                currentOutput.append(Self.soh)
                buffer.removeFirst(1)
            }
        }

        return TeeParsed(display: display, events: events)
    }

    /// Parses a marker at the start of `b` (b[0] is known to be SOH).
    private static func parseMarker(_ b: [UInt8]) -> MarkerResult {
        guard b.count >= 2 else { return .incomplete }
        guard b[1] == upperE else { return .invalid }
        guard b.count >= 3 else { return .incomplete }
        guard b[2] == upperA else { return .invalid }
        guard b.count >= 4 else { return .incomplete }
        let type = b[3]
        guard type == upperC || type == upperX else { return .invalid }
        guard b.count >= 5 else { return .incomplete }
        guard b[4] == colon else { return .invalid }

        var idx = 5
        if type == upperC {
            while idx < b.count, b[idx] != soh { idx += 1 }
            guard idx < b.count else { return .incomplete }
            let cmd = String(decoding: b[5..<idx], as: UTF8.self)
            return .marker(.started(command: cmd), consumed: idx + 1)
        } else {
            let numStart = idx
            if idx < b.count, b[idx] == minus { idx += 1 }
            var sawDigit = false
            while idx < b.count, b[idx] >= 0x30, b[idx] <= 0x39 { idx += 1; sawDigit = true }
            guard idx < b.count else { return .incomplete }
            guard b[idx] == soh, sawDigit, let n = Int(String(decoding: b[numStart..<idx], as: UTF8.self)) else {
                return .invalid
            }
            return .marker(.finished(exitCode: n, output: ""), consumed: idx + 1)
        }
    }
}
