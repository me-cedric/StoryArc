public import Foundation

/// Where a source's continued read stands, kept so a relaunch resumes it instead of starting
/// it over.
///
/// `sources`' *More from a source than the library holds*: a source that holds more than its
/// first slice keeps reading in the background, page by page, and until this store existed
/// that progress lived only in `LibraryModel.partialSources`, an in-memory dictionary. A
/// reader who closed the app mid-read came back to a continuation that had forgotten which
/// page it was on and started again at the top — a server with five thousand series paid
/// for its whole continuation again every launch. Android's `SourceReadProgressStore` is the
/// same store.
///
/// A flat record ([StoredSourceProgress]) rather than `LibraryFeature`'s own
/// `SourceReadProgress`, for the same reason `ScanJournal` keeps its own stored shape: this
/// module sits under every feature, and what is durable is this store's decision, not a
/// mirror of whatever shape a caller happens to hold today.
public struct SourceReadProgressStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "app.storyarc.source-read-progress"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Where this source's continued read stood when it last stopped, or `nil` for a fresh one.
    public func progress(for sourceID: UUID) -> StoredSourceProgress? {
        stored()[sourceID.uuidString]
    }

    /// Records where a source's continued read now stands.
    public func record(_ progress: StoredSourceProgress, for sourceID: UUID) {
        var all = stored()
        all[sourceID.uuidString] = progress
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: key)
    }

    /// Forgets a source's progress. Called when its read finishes, or the source is gone.
    public func clear(for sourceID: UUID) {
        var all = stored()
        guard all.removeValue(forKey: sourceID.uuidString) != nil else { return }
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: key)
    }

    /// Forgets every source's progress. Used by a reset, and by the tests.
    public func reset() {
        defaults.removeObject(forKey: key)
    }

    private func stored() -> [String: StoredSourceProgress] {
        guard let data = defaults.data(forKey: key),
              let all = try? JSONDecoder().decode([String: StoredSourceProgress].self, from: data)
        else { return [:] }
        return all
    }
}

/// What is actually written for one source: how much of it a continuation has merged, how
/// much more there is when the count is known, which page answers next, and the cursor its
/// own kind asks that next page by.
///
/// The three counters are the same fields `LibraryFeature`'s own `SourceReadProgress` holds,
/// kept separate so a change to that type's shape is this store's decision to make, not an
/// accident of a `Codable` conformance reaching it from a feature module this one sits under.
///
/// The two cursors are in no such type, because only a Kavita server continues by a page
/// number. A share continues from the folders its last page had not listed, and a catalogue
/// from the feed link its last page named. A record that kept the counter and dropped the
/// cursor was worse than no record at all: the relaunch resumed at page five and walked the
/// share's root again, counting every row the library already held a second time. Both are
/// optional, so a record an older build wrote still decodes, with neither cursor in it.
public struct StoredSourceProgress: Sendable, Equatable, Codable {
    public let read: Int
    public let total: Int?
    public let nextPage: Int
    /// A partial catalogue's next feed link. `nil` for any other kind, and for an older record.
    public let opdsNext: URL?
    /// A partial share's remaining walk frontier. `nil` for any other kind, and for an older record.
    public let smbQueue: [String]?

    public init(read: Int, total: Int? = nil, nextPage: Int, opdsNext: URL? = nil, smbQueue: [String]? = nil) {
        self.read = read
        self.total = total
        self.nextPage = nextPage
        self.opdsNext = opdsNext
        self.smbQueue = smbQueue
    }
}
