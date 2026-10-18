import Darwin
import Foundation
import os

/// When the library became usable after a launch, for the cold-launch budget of task 5.9.
///
/// **Off unless the app was launched with `-StoryArcBudgetProbe YES`**, as the phone's frame
/// probe is armed: the argument reaches `UserDefaults` through the argument domain, which only a
/// launch writes, so an app opened from Finder pays one `Bool`. Armed, each event is the time
/// since the kernel started the process, written as a signpost for Instruments and as a line in
/// the container's `tmp/budget/launch.log` for the record.
@MainActor
enum LaunchClock {
    static let isArmed = UserDefaults.standard.bool(forKey: "StoryArcBudgetProbe")
    private static let log = OSLog(subsystem: "com.mecedric.storyarc", category: "budget")
    private static var noted: Set<String> = []

    static var file: URL {
        URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory).appending(path: "tmp/budget/launch.log")
    }

    /// Seconds since the kernel started this process, or `nil` where it does not say.
    static func sinceProcessStart() -> Double? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        let started = Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
        return Date().timeIntervalSince1970 - started
    }

    /// Notes an event once a launch: `window`, `shelf` (publications on screen), `scanned`.
    static func note(_ event: String, count: Int) {
        guard isArmed, !noted.contains(event), let seconds = sinceProcessStart() else { return }
        noted.insert(event)
        os_signpost(.event, log: log, name: "launch", "%{public}s %d %.3f", event, count, seconds)
        let line = String(format: "%@ %@ %d %.3f\n", ISO8601DateFormatter().string(from: Date()), event, count, seconds)
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
