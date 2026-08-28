public import Foundation

/// Which server chapter a publication came from.
///
/// The reader knows nothing about Kavita and should not: it opens a file. This is the note
/// the browser leaves behind so that, when the reader closes, the app can tell the server
/// where they got to.
public struct KavitaOrigin: Sendable, Equatable, Codable {
    public let sourceId: String
    public let libraryId: Int
    public let seriesId: Int
    public let volumeId: Int
    public let chapterId: Int

    public init(sourceId: String, libraryId: Int, seriesId: Int, volumeId: Int, chapterId: Int) {
        self.sourceId = sourceId
        self.libraryId = libraryId
        self.seriesId = seriesId
        self.volumeId = volumeId
        self.chapterId = chapterId
    }
}

/// One position waiting to reach a server that was not there when it was read.
public struct KavitaUnsent: Sendable, Equatable, Codable {
    public let origin: KavitaOrigin
    public let page: Int

    public init(origin: KavitaOrigin, page: Int) {
        self.origin = origin
        self.page = page
    }
}

/// The link between a local publication and its Kavita chapter, and what has not been sent.
///
/// `kavita-server` requires a position to be "retried on the next successful connection if
/// it fails", which needs somewhere durable to keep it: a reader who finishes a chapter on
/// a train has closed the app long before the server is reachable again.
///
/// `@unchecked Sendable` because `UserDefaults` is documented as thread-safe but is not
/// marked so. Held rather than passed per call: the flush runs off the main actor, and a
/// store that could not cross that boundary would push the decision into every caller.
public struct KavitaProgressStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let origins = "app.storyarc.kavita.origins"
    private let waiting = "app.storyarc.kavita.unsent"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Notes where a publication came from, replacing any earlier note for the same one.
    public func remember(_ origin: KavitaOrigin, for publicationId: String) {
        var all = links()
        all[publicationId] = origin
        guard let data = try? JSONEncoder().encode(all) else { return }
        defaults.set(data, forKey: origins)
    }

    /// Where a publication came from, or nil when it did not come from a Kavita server.
    public func origin(of publicationId: String) -> KavitaOrigin? { links()[publicationId] }

    /// Keeps a position that could not be sent. One per chapter: the latest page wins.
    public func hold(_ unsent: KavitaUnsent) {
        let kept = self.unsent().filter { $0.origin.chapterId != unsent.origin.chapterId }
        write(kept + [unsent])
    }

    /// Everything still waiting for a server.
    public func unsent() -> [KavitaUnsent] {
        guard let data = defaults.data(forKey: waiting),
              let stored = try? JSONDecoder().decode([KavitaUnsent].self, from: data)
        else { return [] }
        return stored
    }

    /// Drops the positions that reached the server.
    public func sent(_ delivered: [KavitaUnsent]) {
        let chapters = Set(delivered.map(\.origin.chapterId))
        write(unsent().filter { !chapters.contains($0.origin.chapterId) })
    }

    private func links() -> [String: KavitaOrigin] {
        guard let data = defaults.data(forKey: origins),
              let stored = try? JSONDecoder().decode([String: KavitaOrigin].self, from: data)
        else { return [:] }
        return stored
    }

    private func write(_ value: [KavitaUnsent]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: waiting)
    }
}
