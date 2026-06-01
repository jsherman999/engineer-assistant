import SwiftUI

@main
struct EngineerAssistantApp: App {
    @StateObject private var session: AppSession

    init() {
        _session = StateObject(wrappedValue: AppSession())
    }

    var body: some Scene {
        WindowGroup("Engineer Assistant") {
            RootView()
                .environmentObject(session)
                .frame(minWidth: 900, minHeight: 600)
                .task { await session.start() }
        }
    }
}
