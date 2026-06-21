import SwiftUI

/// Lists cached courses so the student can reopen one and resume at the saved lesson,
/// review saved results, or retake from the start. Deleting courses is instructor-only
/// (see the instructor dashboard).
struct CourseLibraryView: View {
    @EnvironmentObject var session: AppSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your Courses")
                .font(.title2.bold())

            if session.courses.isEmpty {
                Text("No courses yet. Switch to Course Mode in the chat to generate one.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(session.courses) { course in
                            row(for: course)
                        }
                    }
                }
            }

            Spacer()
            HStack {
                Spacer()
                Button("Close") { dismiss() }
            }
        }
        .padding(20)
        .frame(width: 560, height: 480)
    }

    private func row(for course: Course) -> some View {
        // Reading resultsRevision keeps this row fresh after a result/delete/retake change.
        _ = session.resultsRevision
        let progress = session.progress(for: course.id)
        let resumeIdx = max(0, min(progress?.lessonIdx ?? 0, course.lessons.count - 1))
        let results = session.results(for: course.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(course.title).font(.headline)
                    Text(course.description)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(course.environment == .macos ? "macOS" : "Linux")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(Capsule())
                        if let progress, progress.completed {
                            Label("Completed", systemImage: "checkmark.circle.fill")
                                .font(.caption2).foregroundStyle(.green)
                        } else if progress != nil {
                            Text("Resume at lesson \(resumeIdx + 1)/\(course.lessons.count)")
                                .font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Text("\(course.lessons.count) lessons")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        if let results {
                            Text("✓ \(results.passedCount)/\(course.lessons.count) passed · attempt \(results.currentAttempt)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Button(progress == nil ? "Start" : "Resume") {
                        session.openCourse(course)
                        dismiss()
                    }
                    if progress != nil || results != nil {
                        Button("Retake") {
                            session.retakeCourse(course)
                            dismiss()
                        }
                        .font(.caption)
                    }
                }
            }

            if let results, !results.attempts.isEmpty {
                resultsDetail(course: course, results: results)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func resultsDetail(course: Course, results: CourseResults) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(course.lessons.indices, id: \.self) { idx in
                    lessonResultRow(idx: idx, title: course.lessons[idx].title,
                                    latest: results.latest(lessonIdx: idx, attempt: results.currentAttempt))
                }
            }
            .padding(.top, 4)
        } label: {
            Text("Results (attempt \(results.currentAttempt))")
                .font(.caption.bold()).foregroundStyle(.secondary)
        }
    }

    private func lessonResultRow(idx: Int, title: String, latest: LessonAttempt?) -> some View {
        let icon: String
        let color: Color
        let status: String
        if let latest {
            icon = latest.passed ? "checkmark.circle.fill" : "xmark.circle.fill"
            color = latest.passed ? .green : .orange
            status = latest.passed ? "passed" : "not yet"
        } else {
            icon = "circle"
            color = .secondary
            status = "not attempted"
        }
        return HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color).font(.caption)
            Text("Lesson \(idx + 1): \(title)").font(.caption)
            Spacer()
            Text(status).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
