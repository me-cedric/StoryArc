import Foundation

/// Whether this host keeps a file protection class that a test sets.
///
/// Data protection is an iOS facility, and `StoryArcKit` also builds for macOS so its pure
/// targets can be host-tested. Some macOS hosts keep the class on a file and report it back;
/// the CI runner's volume ignores the set and reports the system default instead. A test
/// that asserts the class is run only where the host can hold it, so it reports as skipped
/// on the runner rather than failing there or passing without looking.
enum HostProtection {
    static let isKept: Bool = {
        let file = URL.temporaryDirectory.appending(path: "protection-probe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        guard (try? Data("probe".utf8).write(to: file)) != nil else { return false }
        let files = FileManager.default
        try? files.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: file.path)
        let kept = (try? files.attributesOfItem(atPath: file.path))?[.protectionKey] as? FileProtectionType
        return kept == .completeUnlessOpen
    }()
}
