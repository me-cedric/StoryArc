public import Foundation

/// What a sync keeps on this device between runs: this install's id, and the conflicted copies
/// it merged but could not delete.
///
/// `library-sync` task 3.1: each record in the document names the device that last changed it.
/// The id is made once per install and never leaves it except in the document. Android's
/// `LibrarySyncState` keeps the same two values.
///
/// `@unchecked Sendable`: it holds a `UserDefaults`, which is documented as safe to use from
/// any thread but is not marked so.
public struct LibrarySyncState: @unchecked Sendable {
    private let defaults: UserDefaults
    private let deviceKey = "app.storyarc.sync.deviceId"
    private let mergedCopiesKey = "app.storyarc.sync.mergedCopies"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// This install's id, made on first use.
    public func deviceID() -> String {
        if let held = defaults.string(forKey: deviceKey) { return held }
        let made = UUID().uuidString
        defaults.set(made, forKey: deviceKey)
        return made
    }

    /// Conflicted copies already merged, as `name@version`.
    public func mergedCopies() -> Set<String> {
        Set(defaults.stringArray(forKey: mergedCopiesKey) ?? [])
    }

    public func saveMergedCopies(_ copies: Set<String>) {
        defaults.set(copies.sorted(), forKey: mergedCopiesKey)
    }
}
