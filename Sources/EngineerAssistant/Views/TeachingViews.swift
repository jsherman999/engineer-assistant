import SwiftUI

/// A demo's expected output, hidden until the student commits to a guess.
///
/// Reading "here's the command, here's what it prints" is passive. Being asked to predict first
/// forces the student to actually model what the command does, and a wrong prediction is the
/// thing they remember. The reveal is one click away — this adds a beat of thought, not a gate.
struct PredictedOutputView: View {
    let expected: String
    @State private var revealed = false

    var body: some View {
        Group {
            if revealed {
                Text(expected)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .textSelection(.enabled)
                    .transition(.opacity)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { revealed = true }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "eye")
                        Text("What do you think this prints?")
                        Text("Reveal").foregroundStyle(Theme.demos)
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.secondary.opacity(0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(Color.secondary.opacity(0.4))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Make a prediction first, then reveal the real output")
            }
        }
    }
}

/// Asks the student to say why their solution worked, and responds to what they say.
///
/// A passing check proves the command ran, not that the student knows why. Saying it back in
/// their own words is where the understanding actually forms — and it gives the instructor a far
/// better signal than a green tick.
struct ExplainBackView: View {
    @EnvironmentObject var session: AppSession
    @State private var answer = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().padding(.vertical, 2)
            Label("In one sentence — why did that work?", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                .font(.caption.bold())
                .foregroundStyle(Theme.recap)

            if let feedback = session.explanationFeedback {
                Text(feedback)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Theme.recap.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .textSelection(.enabled)
                Button("Answer again") {
                    session.explanationFeedback = nil
                    answer = ""
                }
                .font(.caption).buttonStyle(.borderless)
            } else {
                HStack(spacing: 6) {
                    TextField("Your explanation…", text: $answer, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...3)
                        .disabled(session.explanationSending)
                        .onSubmit(submit)
                    Button(action: submit) {
                        if session.explanationSending {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                    }
                    .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || session.explanationSending)
                }
                Text("Optional — but explaining it is what makes it stick.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func submit() {
        session.submitExplanation(answer)
    }
}

/// Lessons due for another look, driven by the gradebook the app already keeps.
struct ReviewView: View {
    @EnvironmentObject var session: AppSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review")
                .font(.title2.bold())
            Text("Coming back to something a few days later is what moves it into long-term memory. These are due.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            let items = session.dueReviewItems()
            if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.largeTitle).foregroundStyle(.green)
                    Text("Nothing due right now.")
                        .foregroundStyle(.secondary)
                    Text("Finish a lesson and it'll come back here in a few days.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(items) { item in
                            row(item)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }
            }
        }
        .padding(20)
        .frame(width: 560, height: 460)
    }

    private func row(_ item: ReviewItem) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.lessonTitle).font(.headline)
                Text(item.courseTitle).font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(item.reason.label)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(color(for: item.reason).opacity(0.18))
                        .foregroundStyle(color(for: item.reason))
                        .clipShape(Capsule())
                    Text(item.daysSinceLastSeen == 0 ? "today" : "\(item.daysSinceLastSeen)d ago")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button("Practice") {
                session.startReview(item)
                dismiss()
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func color(for reason: ReviewItem.Reason) -> Color {
        switch reason {
        case .struggled: return .orange
        case .neededHint: return .yellow
        case .spacedInterval: return Theme.concept
        }
    }
}
