import SwiftUI

/// Lists cached courses so the student can reopen one and resume at the saved lesson.
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
        .frame(width: 520, height: 420)
    }

    private func row(for course: Course) -> some View {
        let progress = session.progress(for: course.id)
        let resumeIdx = max(0, min(progress?.lessonIdx ?? 0, course.lessons.count - 1))
        return HStack(alignment: .top) {
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
                }
            }
            Spacer()
            Button(progress == nil ? "Start" : "Resume") {
                session.openCourse(course)
                dismiss()
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
