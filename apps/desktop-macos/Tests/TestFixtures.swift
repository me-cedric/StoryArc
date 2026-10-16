import Foundation

/// A defaults suite of its own for one test, removed when the test ends.
struct ScratchDefaults {
    let defaults: UserDefaults
    let name: String

    init(prefix: String) throws {
        name = "\(prefix)\(UUID().uuidString)"
        guard let suite = UserDefaults(suiteName: name) else { throw ScratchError.noSuite(name) }
        defaults = suite
    }

    func remove() {
        defaults.removePersistentDomain(forName: name)
    }

    enum ScratchError: Error { case noSuite(String) }
}

/// Files the tests read, from the test bundle rather than from the checkout.
///
/// `project.yml` copies `packages/test-fixtures/comics` and the app's entitlements file into
/// the bundle. A test hosted in the sandboxed app that opens a path under `~/Documents`
/// waits on a privacy prompt, so nothing here names a path in the repository.
enum TestFixtures {
    private final class Marker {}

    static var bundle: Bundle { Bundle(for: Marker.self) }

    /// `packages/test-fixtures/comics`, as copied into the bundle.
    static var comics: URL {
        bundle.bundleURL.appending(path: "Contents/Resources/comics", directoryHint: .isDirectory)
    }

    /// `App/StoryArcMac.entitlements`, as copied into the bundle.
    static var entitlements: URL {
        bundle.bundleURL.appending(path: "Contents/Resources/StoryArcMac.entitlements")
    }

    /// One comic fixture, copied to a fresh temporary folder the test owns.
    ///
    /// A reader writes progress and covers next to nothing, but a test that renames or
    /// deletes must never touch the bundle, so it works on a copy.
    static func copy(_ name: String) throws -> URL {
        let folder = URL.temporaryDirectory.appending(path: "fixture-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appending(path: name)
        try FileManager.default.copyItem(at: comics.appending(path: name), to: target)
        return target
    }
}
