import SwiftUI
import Charts

/// Where a course is actually costing the student effort.
///
/// The gradebook was a flat list of every check, which answers "what happened" but not "where is
/// this course hard". Per-lesson attempt counts make that obvious at a glance: the lesson with
/// six failed checks and two hints is the one whose explanation needs rewriting.
struct CourseInsightsView: View {
    let course: Course
    let results: CourseResults

    private struct LessonStat: Identifiable {
        var id: Int { lessonIdx }
        let lessonIdx: Int
        let title: String
        let passedChecks: Int
        let failedChecks: Int
        let hints: Int
        var totalChecks: Int { passedChecks + failedChecks }
        var shortLabel: String { "L\(lessonIdx + 1)" }
    }

    private var stats: [LessonStat] {
        course.lessons.indices.map { idx in
            let forLesson = results.attempts.filter { $0.lessonIdx == idx }
            return LessonStat(
                lessonIdx: idx,
                title: course.lessons[idx].title,
                passedChecks: forLesson.filter(\.passed).count,
                failedChecks: forLesson.filter { !$0.passed }.count,
                hints: forLesson.filter(\.hintUsed).count
            )
        }
    }

    /// The lesson that took the most tries — usually the one worth looking at first.
    private var hardest: LessonStat? {
        stats.filter { $0.totalChecks > 0 }.max {
            ($0.failedChecks, $0.totalChecks) < ($1.failedChecks, $1.totalChecks)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            summaryStrip

            if stats.contains(where: { $0.totalChecks > 0 }) {
                Text("Checks per lesson")
                    .font(.caption.bold()).foregroundStyle(.secondary)
                Chart {
                    ForEach(stats) { stat in
                        BarMark(
                            x: .value("Lesson", stat.shortLabel),
                            y: .value("Checks", stat.failedChecks)
                        )
                        .foregroundStyle(by: .value("Result", "Not yet"))
                        BarMark(
                            x: .value("Lesson", stat.shortLabel),
                            y: .value("Checks", stat.passedChecks)
                        )
                        .foregroundStyle(by: .value("Result", "Passed"))
                    }
                }
                .chartForegroundStyleScale(["Passed": Color.green, "Not yet": Color.orange])
                .chartLegend(position: .top, alignment: .leading)
                .frame(height: 150)

                if let hardest, hardest.failedChecks > 0 {
                    Label(
                        "Lesson \(hardest.lessonIdx + 1) took the most tries — \(hardest.title)",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption).foregroundStyle(.orange)
                }

                if stats.contains(where: { $0.hints > 0 }) {
                    Text("Hints used")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    Chart(stats) { stat in
                        BarMark(
                            x: .value("Lesson", stat.shortLabel),
                            y: .value("Hints", stat.hints)
                        )
                        .foregroundStyle(Color.yellow)
                    }
                    .frame(height: 90)
                }
            } else {
                Text("No checks recorded yet.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 16) {
            metric("\(results.passedCount)/\(course.lessons.count)", "lessons passed", .green)
            metric("\(results.attempts.count)", "checks run", Theme.concept)
            metric("\(results.attempts.filter(\.hintUsed).count)", "hints", .yellow)
            metric("\(results.currentAttempt)", results.currentAttempt == 1 ? "attempt" : "attempts", .secondary)
            if results.finalChallengePassed {
                Label("capstone passed", systemImage: "rosette")
                    .font(.caption).foregroundStyle(.green)
            }
            Spacer()
        }
    }

    private func metric(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
