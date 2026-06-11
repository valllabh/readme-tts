import Foundation

// Append only file log at ~/Library/Logs/ReadMe/ReadMe.log so issues can be
// diagnosed after the fact. Also mirrored to NSLog for Console.app.
final class Log {
    static let shared = Log()

    let fileURL: URL

    private let queue = DispatchQueue(label: "app.readme.log")
    private let maxBytes: UInt64 = 2_000_000
    private let formatter: DateFormatter

    private init() {
        let dir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/ReadMe")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("ReadMe.log")
        formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }

    static func info(_ message: String) {
        shared.write("INFO", message)
    }

    static func error(_ message: String) {
        shared.write("ERROR", message)
    }

    private func write(_ level: String, _ message: String) {
        NSLog("ReadMe [\(level)] \(message)")
        queue.async {
            self.rotateIfNeeded()
            let line = "\(self.formatter.string(from: Date())) [\(level)] \(message)\n"
            if let data = line.data(using: .utf8) {
                if let handle = try? FileHandle(forWritingTo: self.fileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                } else {
                    // Owner only: logs are diagnostic but still private.
                    FileManager.default.createFile(
                        atPath: self.fileURL.path,
                        contents: data,
                        attributes: [.posixPermissions: 0o600]
                    )
                }
            }
        }
    }

    private func rotateIfNeeded() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes?[.size] as? UInt64) ?? 0
        guard size > maxBytes else { return }
        let old = fileURL.deletingPathExtension().appendingPathExtension("old.log")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: fileURL, to: old)
    }
}
