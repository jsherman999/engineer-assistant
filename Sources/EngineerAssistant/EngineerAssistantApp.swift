import SwiftUI
import AppKit

/// Promotes the bare SwiftPM executable to a regular foreground app so its window can
/// become key and receive keyboard input (otherwise keystrokes fall through to the
/// terminal that launched it).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct EngineerAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session: AppSession

    init() {
        _session = StateObject(wrappedValue: AppSession())
    }

    var body: some Scene {
        WindowGroup("Engineer Assistant") {
            RootView()
                .environmentObject(session)
                .frame(minWidth: 1040, minHeight: 640)
                .task { await session.start() }
        }
    }
}
