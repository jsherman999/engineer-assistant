import SwiftUI

struct RootView: View {
    @EnvironmentObject var session: AppSession
    @State private var showingSettings = false

    var body: some View {
        ChatView()
            .toolbar {
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
            .onAppear {
                if !session.apiKeyConfigured {
                    showingSettings = true
                }
            }
    }
}
