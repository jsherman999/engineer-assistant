import SwiftUI

/// What the student has actually done, shown to the student.
///
/// All of this already existed, but only behind the instructor's PIN. Seeing your own record —
/// what you've passed, where you needed help, what's due — is a reflection tool, and it makes
/// the review schedule legible instead of arbitrary.
struct StudentProgressView: View {
    @EnvironmentObject var session: AppSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Progress").font(.title2.bold())

            let all = session.allResults()
            if all.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.largeTitle).foregroundStyle(.secondary)
                    Text("Nothing recorded yet.").foregroundStyle(.secondary)
                    Text("Finish a lesson challenge and it'll show up here.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                totals(all)
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(all, id: \.courseId) { result in
                            if let course = session.courses.first(where: { $0.id == result.courseId }) {
                                courseCard(course: course, results: result)
                            }
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
        .frame(width: 620, height: 520)
    }

    private func totals(_ all: [CourseResults]) -> some View {
        let passed = all.reduce(0) { $0 + $1.passedCount }
        let checks = all.reduce(0) { $0 + $1.attempts.count }
        let hints = all.reduce(0) { $0 + $1.attempts.filter(\.hintUsed).count }
        return HStack(spacing: 18) {
            metric("\(passed)", "lessons passed", .green)
            metric("\(checks)", "challenges attempted", Theme.concept)
            metric("\(hints)", "hints used", .yellow)
            metric("\(session.dueReviewItems().count)", "due for review", Theme.practice)
            Spacer()
        }
        .padding(10)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func metric(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func courseCard(course: Course, results: CourseResults) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(course.title).font(.headline)
                Spacer()
                Text("\(results.passedCount)/\(course.lessons.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            // One dot per lesson: the whole course's state in a single glance.
            HStack(spacing: 4) {
                ForEach(course.lessons.indices, id: \.self) { idx in
                    let latest = results.latest(lessonIdx: idx, attempt: results.currentAttempt)
                    Circle()
                        .fill(color(for: latest))
                        .frame(width: 10, height: 10)
                        .help("Lesson \(idx + 1): \(course.lessons[idx].title)")
                }
                if course.finalChallenge != nil {
                    Image(systemName: results.finalChallengePassed ? "rosette" : "flag.checkered")
                        .font(.caption2)
                        .foregroundStyle(results.finalChallengePassed ? .green : .secondary)
                }
                Spacer()
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func color(for attempt: LessonAttempt?) -> Color {
        guard let attempt else { return .secondary.opacity(0.3) }
        if attempt.passed { return attempt.hintUsed ? .yellow : .green }
        return .orange
    }
}
