import SwiftUI

struct RootView: View {
    @EnvironmentObject var session: AppSession
    @State private var showingSettings = false
    @State private var showingLibrary = false
    @State private var showingInstructor = false

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
