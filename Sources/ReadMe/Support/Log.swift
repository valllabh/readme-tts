import Foundation
import ReadMeCore

// Append only file log at ~/Library/Logs/ReadMe/ReadMe-<day>.log, mirrored to
// NSLog for Console.app. One file per day; on every write, files from other
// days are deleted, so at most one day of logs exists on disk. DEBUG entries
// carry pipeline content (chunks, polish in and out) and are written only
// while Debug Mode is on, keeping spoken text out of the log in normal use.
final class Log {
    static let shared = Log()

    private let dir: URL
    private let queue = DispatchQueue(label: "app.readme.log")
    private let stampFormatter: DateFormatter
    private let dayFormatter: DateFormatter
    private var openDay = ""

    // The notification lets a live viewer refresh without polling the disk.
    static let didAppend = Notification.Name("app.readme.log.didAppend")

    private init() {
        dir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/ReadMe")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        stampFormatter = DateFormatter()
        stampFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
    }

    var fileURL: URL {
        dir.appendingPathComponent("ReadMe-\(dayFormatter.string(from: Date())).log")
    }

    static func info(_ message: String) {
        shared.write("INFO", message)
    }

    static func error(_ message: String) {
        shared.write("ERROR", message)
    }

    // Content carrying trace, captured only in Debug Mode.
    static func debug(_ message: String) {
        guard Preferences.debugMode else { return }
        shared.write("DEBUG", message)
    }

    static func clear() {
        shared.queue.async {
            try? FileManager.default.removeItem(at: shared.fileURL)
            NotificationCenter.default.post(name: didAppend, object: nil)
        }
    }

    private func write(_ level: String, _ message: String) {
        NSLog("ReadMe [\(level)] \(message)")
        queue.async {
            let url = self.fileURL
            let day = self.dayFormatter.string(from: Date())
            if day != self.openDay {
                self.openDay = day
                self.deleteOldLogs(keeping: url)
            }
            let line = "\(self.stampFormatter.string(from: Date())) [\(level)] \(message)\n"
            if let data = line.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                } else {
                    // Owner only: logs are diagnostic but still private.
                    FileManager.default.createFile(
                        atPath: url.path,
                        contents: data,
                        attributes: [.posixPermissions: 0o600]
                    )
                }
            }
            NotificationCenter.default.post(name: Self.didAppend, object: nil)
        }
    }

    // No more than one day of logs: anything that is not today's file goes,
    // including the pre rotation ReadMe.log and ReadMe.old.log names.
    private func deleteOldLogs(keeping current: URL) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent != current.lastPathComponent {
            try? fm.removeItem(at: file)
        }
    }
}
