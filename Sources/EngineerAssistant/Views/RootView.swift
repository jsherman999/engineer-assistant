import SwiftUI

struct RootView: View {
    @EnvironmentObject var session: AppSession
    @State private var showingSettings = false
    @State private var showingLibrary = false
    @State private var showingInstructor = false
    @State private var showingReview = false

    /// Reading resultsRevision keeps the badge current after a challenge check.
    private var dueCount: Int {
        _ = session.resultsRevision
        return session.dueReviewItems().count
    }

    private var generatingSubject: String? {
        if session.isRegenerating { return session.activeCourse?.subject }
        return session.messages.last(where: { $0.role == .user })?.text
    }

    var body: some View {
        Group {
            if let course = session.activeCourse {
                CoursePlayerView(course: course)
            } else {
                ChatView()
            }
        }
        .overlay {
            if session.isGeneratingCourse {
                CourseGeneratingOverlay(subject: generatingSubject)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.isGeneratingCourse)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingLibrary = true
                } label: {
                    Label("Courses", systemImage: "books.vertical")
                }
                .disabled(session.courses.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingReview = true
                } label: {
                    // Badge the count so review is something the student notices, not something
                    // they have to remember to go looking for.
                    Label("Review\(dueCount > 0 ? " (\(dueCount))" : "")", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                }
                .help("Lessons worth revisiting")
                .disabled(session.courses.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(session)
        }
        .sheet(isPresented: $showingLibrary) {
            CourseLibraryView()
                .environmentObject(session)
        }
        .sheet(isPresented: $showingInstructor) {
            InstructorGateView()
                .environmentObject(session)
        }
        .sheet(isPresented: $showingReview) {
            ReviewView()
                .environmentObject(session)
        }
        .background(
            // Hidden entry to the instructor dashboard (⌘⇧I); no visible control for the student.
            Button("Instructor") { showingInstructor = true }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .opacity(0)
                .accessibilityHidden(true)
        )
        .onAppear {
            if !session.apiKeyConfigured {
                showingSettings = true
            }
        }
    }
}
