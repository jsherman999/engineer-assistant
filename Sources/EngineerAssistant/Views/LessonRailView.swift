import SwiftUI

/// Vertical progress rail down the side of the course player.
///
/// Replaces the "Lesson 3 of 5" capsule, which told the student where they were but not what
/// had happened: which lessons they passed, which they only skipped past, and which needed a
/// hint. Each stop is clickable, so reviewing an earlier lesson doesn't mean pressing Previous
/// repeatedly.
struct LessonRailView: View {
    let course: Course
    let currentIdx: Int
    let results: CourseResults?
    let onSelect: (Int) -> Void

    private enum Status {
        case passed, hinted, attempted, untouched

        var symbol: String {
            switch self {
            case .passed: return "checkmark.circle.fill"
            case .hinted: return "lightbulb.circle.fill"
            case .attempted: return "circle.dotted"
            case .untouched: return "circle"
            }
        }

        var color: Color {
            switch self {
            case .passed: return .green
            case .hinted: return .yellow
            case .attempted: return .orange
            case .untouched: return .secondary
            }
        }

        var label: String {
            switch self {
            case .passed: return "passed"
            case .hinted: return "passed with a hint"
            case .attempted: return "tried, not passed yet"
            case .untouched: return "not attempted"
            }
        }
    }

    private func status(_ idx: Int) -> Status {
        guard let results, let latest = results.latest(lessonIdx: idx, attempt: results.currentAttempt) else {
            return .untouched
        }
        if latest.passed { return latest.hintUsed ? .hinted : .passed }
        return .attempted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(course.lessons.indices, id: \.self) { idx in
                    stop(idx)
                }
                if course.finalChallenge != nil {
                    finalStop
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 10)
        }
        .frame(width: 190)
        .background(Theme.bar)
    }

    private func stop(_ idx: Int) -> some View {
        let state = status(idx)
        let isCurrent = idx == currentIdx
        return Button {
            onSelect(idx)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                // Marker column: the icon plus the connector down to the next stop.
                VStack(spacing: 0) {
                    Image(systemName: state.symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(state.color)
                    if idx < course.lessons.count - 1 || course.finalChallenge != nil {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.25))
                            .frame(width: 1.5)
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Lesson \(idx + 1)")
                        .font(.caption2.bold())
                        .foregroundStyle(isCurrent ? Theme.headerTint : .secondary)
                    Text(course.lessons[idx].title)
                        .font(.caption)
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 12)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .background(
                isCurrent ? Theme.headerTint.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
        .help("\(course.lessons[idx].title) — \(state.label)")
        .fixedSize(horizontal: false, vertical: true)
    }

    private var finalStop: some View {
        let passed = results?.finalChallengePassed ?? false
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: passed ? "rosette" : "flag.checkered")
                .font(.system(size: 13))
                .foregroundStyle(passed ? .green : .secondary)
                .frame(width: 16)
            Text("Final Challenge")
                .font(.caption.bold())
                .foregroundStyle(passed ? .green : .secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.top, 4)
    }
}
