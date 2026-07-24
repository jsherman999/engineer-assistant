import SwiftUI

/// One recorded chunk of terminal output with the wall-clock time it was emitted.
struct ReplayFrame: Equatable {
    let timestamp: Date
    let text: String
}

/// Asciinema-style playback of a recorded shell session: the instructor can watch the terminal
/// fill in at the pace the student actually worked, scrub to any point, or jump to the end.
/// Long pauses are capped so a session where the student went to lunch stays watchable.
struct TerminalReplayView: View {
    let frames: [ReplayFrame]

    @State private var position: Int = 0
    @State private var isPlaying = false
    @State private var speed: Double = 1
    @State private var timer: Timer?

    private static let maxGap: TimeInterval = 2

    /// Cumulative playback offset of each frame, with idle gaps clamped to `maxGap`.
    private var offsets: [TimeInterval] {
        var out: [TimeInterval] = []
        var running: TimeInterval = 0
        for (i, frame) in frames.enumerated() {
            if i > 0 {
                running += min(frame.timestamp.timeIntervalSince(frames[i - 1].timestamp), Self.maxGap)
            }
            out.append(running)
        }
        return out
    }

    private var visibleText: String {
        frames.prefix(position).map(\.text).joined()
    }

    var body: some View {
        VStack(spacing: 0) {
            if frames.isEmpty {
                Text("No shell activity in this session.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                controls
                Divider()
                screen
            }
        }
        .onDisappear(perform: stop)
    }

    private var screen: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(visibleText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .id("replayBottom")
            }
            .onChange(of: position) { _, _ in
                proxy.scrollTo("replayBottom", anchor: .bottom)
            }
        }
        .background(Color.black.opacity(0.9))
        .foregroundStyle(Color(red: 0.85, green: 1.0, blue: 0.85))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                isPlaying ? stop() : play()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
            .help(isPlaying ? "Pause" : "Play")

            Button {
                stop()
                position = 0
            } label: {
                Image(systemName: "backward.end.fill")
            }
            .buttonStyle(.borderless)
            .help("Back to start")

            Slider(
                value: Binding(
                    get: { Double(position) },
                    set: { position = Int($0); stop() }
                ),
                in: 0...Double(max(frames.count, 1))
            )
            .frame(minWidth: 140)

            Text("\(position)/\(frames.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Picker("Speed", selection: $speed) {
                Text("0.5×").tag(0.5)
                Text("1×").tag(1.0)
                Text("2×").tag(2.0)
                Text("4×").tag(4.0)
            }
            .pickerStyle(.segmented)
            .frame(width: 190)
            .onChange(of: speed) { _, _ in if isPlaying { play() } }

            Button("End") {
                stop()
                position = frames.count
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func play() {
        timer?.invalidate()
        if position >= frames.count { position = 0 }
        isPlaying = true
        let starts = offsets
        let startedAt = Date()
        let origin = position < starts.count ? starts[position] : 0

        let t = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in
            Task { @MainActor in
                let elapsed = Date().timeIntervalSince(startedAt) * speed + origin
                var next = position
                while next < starts.count, starts[next] <= elapsed { next += 1 }
                position = next
                if position >= frames.count { stop() }
            }
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        isPlaying = false
    }
}
