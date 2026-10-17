import Foundation

/// What a walk measured, written beside the run for the conformance record of task 3.16.
///
/// One line per measurement in the container's `tmp/conformance/wave3.log`, as
/// `<scenario>: <what was seen>`. The record quotes these lines; a walk's pass or failure is
/// the test's own result, and this holds the values a pass alone does not show (a dialect,
/// a duration, an outcome the scenario allows two ways).
enum ConformanceLog {
    static var file: URL {
        URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory).appending(path: "tmp/conformance/wave3.log")
    }

    static func note(_ scenario: String, _ seen: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(scenario): \(seen)\n"
        let folder = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: file)
        }
    }
}
