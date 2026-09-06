public import Foundation

public import StoryArcCore

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

extension KavitaOrigin {
    /// ADR-0006's first identity rule, built from what the browser already knows.
    ///
    /// Of the five things an origin holds, only two name the publication: the server it
    /// came from and the chapter itself. A library and a series say where it sits on that
    /// server, which moves when the server is reorganised.
    ///
    /// Nil when ``sourceId`` is not an identifier. The store scopes a server identity to
    /// the source's own id, and inventing one would file two servers' chapter 42 as one
    /// publication — data loss in the one store this app promises never to lose, and
    /// strictly worse than leaving them as two records.
    public var serverIdentifier: PublicationIdentity.ServerIdentifier? {
        UUID(uuidString: sourceId).map {
            PublicationIdentity.ServerIdentifier(sourceID: $0, remoteID: String(chapterId))
        }
    }
}

/// One thing waiting to reach a server that was not there when it happened.
///
/// A position, a deliberate mark, an append to one of the server's reading lists, or the
/// order a reader gave one of those lists. They are held together because they are the same
/// promise — "this reaches the server when the server comes back" — and a second queue
/// would be a second thing to forget to flush.
public struct KavitaUnsent: Sendable, Equatable, Codable {
    public let origin: KavitaOrigin
    public let page: Int
    /// Nil for a position. True or false for a mark the reader made deliberately.
    public let mark: Bool?
    /// Set when this is an append to one of the server's reading lists, or an order for one.
    public let listID: Int?
    /// The chapters of ``listID``, in the order this device wants them.
    ///
    /// Set only for a reorder. `collections-and-reading-lists` makes a reading list's order
    /// its meaning, so the order a reader made is written down before anything is sent: a
    /// send that fails must cost them nothing.
    public let order: [Int]?

    /// What makes two held items the same thing.
    ///
    /// The chapter alone is not enough: a position, a mark and a list append can all be
    /// waiting for the same chapter, and they are three different promises. An order is a
    /// fourth, and it belongs to the list rather than to a chapter — one list has one
    /// wanted order, and the latest one the reader made is the one that is true.
    ///
    /// An order names its server as well as its list. Every Kavita numbers its first reading
    /// list 1, so two servers holding a list of the same number is the ordinary case, and a
    /// key without the server would file both orders as one and lose the first.
    public var key: String {
        guard order == nil else {
            return "order:\(origin.sourceId):\(listID.map(String.init) ?? "-")"
        }
        return "\(origin.chapterId):\(listID.map(String.init) ?? "-"):\(mark.map(String.init) ?? "-")"
    }

    public init(
        origin: KavitaOrigin,
        page: Int,
        mark: Bool? = nil,
        listID: Int? = nil,
        order: [Int]? = nil
    ) {
        self.origin = origin
        self.page = page
        self.mark = mark
        self.listID = listID
        self.order = order
    }

    /// A queue written before marks existed has no `mark` field, and it means "a position".
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        origin = try container.decode(KavitaOrigin.self, forKey: .origin)
        page = try container.decode(Int.self, forKey: .page)
        mark = try container.decodeIfPresent(Bool.self, forKey: .mark)
        listID = try container.decodeIfPresent(Int.self, forKey: .listID)
        order = try container.decodeIfPresent([Int].self, forKey: .order)
    }

    private enum CodingKeys: String, CodingKey {
        case origin, page, mark, listID, order
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

    /// The publication one chapter was read as, if this device has ever opened it.
    ///
    /// The inverse of ``remember(_:for:)``, and what a pull needs: a server reports progress
    /// against a chapter id, and the local store keys on the publication the reader opened.
    /// Without this the two never meet and a merge silently matches nothing, which is worse
    /// than not merging at all — it looks like synchronisation and is not.
    ///
    /// Nil for a chapter this device has not opened. `reading-progress` still wants that
    /// position, but it belongs to a publication the library does not hold yet, and
    /// inventing an identity for it would be inventing a reading.
    public func publication(forChapter chapterId: Int) -> String? {
        links().first { $0.value.chapterId == chapterId }?.key
    }

    /// Keeps a position that could not be sent. One per chapter: the latest page wins.
    public func hold(_ unsent: KavitaUnsent) {
        write(self.unsent().filter { $0.key != unsent.key } + [unsent])
    }

    /// Everything still waiting for a server.
    public func unsent() -> [KavitaUnsent] {
        guard let data = defaults.data(forKey: waiting),
              let stored = try? JSONDecoder().decode([KavitaUnsent].self, from: data)
        else { return [] }
        return stored
    }

    /// Drops the records that reached the server.
    ///
    /// Matched whole rather than by key. A flush reads what is waiting, sends it, and comes
    /// back later; anything the reader wrote down while it ran carries the same key and is a
    /// different promise, so dropping by key would throw away an edit nothing had sent.
    public func sent(_ delivered: [KavitaUnsent]) {
        write(unsent().filter { !delivered.contains($0) })
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
