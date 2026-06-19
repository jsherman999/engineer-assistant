import Foundation

enum AppPaths {
    static let appSupportDirName = "EngineerAssistant"

    static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent(appSupportDirName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var eventsFile: URL {
        appSupport.appendingPathComponent("events.jsonl")
    }

    static var progressFile: URL {
        appSupport.appendingPathComponent("progress.json")
    }

    static var coursesDir: URL {
        let dir = appSupport.appendingPathComponent("courses", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var sandboxesDir: URL {
        let dir = appSupport.appendingPathComponent("sandboxes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
