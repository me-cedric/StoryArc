public import Foundation

public import StoryArcCore

/// What a Kavita server said about the publications this device has kept.
///
/// `kavita-server`: "when a downloaded Kavita publication is opened with the server
/// unreachable, the cached server metadata is displayed, not the file's embedded metadata".
/// Nothing was written down before this, on either platform: a chapter's summary, people
/// and subjects were fetched when the series screen appeared and lost when it left, so a
/// download opened without a server had only the file's own `ComicInfo.xml` — the thing the
/// spec says explicitly loses.
///
/// **This is the one Kavita answer that reaches disk.** `sources` records why the rest do
/// not: a catalogue's responses are never cached, because they carry acquisition URLs that
/// can embed a credential and because a caches directory the system may evict mid-browse
/// makes the offline notice necessary anyway. A card carries no URL and no secret — a
/// series name, a chapter name, a summary, names and years — and it is written beside a
/// download the reader deliberately kept, so it lives exactly as long as the file does.
///
/// `@unchecked Sendable` for the reason ``KavitaProgressStore`` gives. Android's
/// `KavitaCardStore` mirrors it.
public struct KavitaCardStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "app.storyarc.kavita.cards"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Writes what the server said, replacing any earlier card for the same publication.
    ///
    /// Replacing rather than merging: a second keep of the same chapter is a fresher answer
    /// from the same server, and half of an old one mixed into it would be a description
    /// nobody ever gave.
    public func save(_ card: KavitaCard) {
        var all = cards()
        all[card.publicationId] = card
        write(all)
    }

    /// What the server said about one publication, or nil when it never said.
    public func card(of publicationId: String) -> KavitaCard? { cards()[publicationId] }

    /// Every card this device holds.
    public func all() -> [KavitaCard] {
        // Sorted by identity, so a list drawn from this does not reshuffle between launches
        // for no reason a reader can see. A dictionary has no order of its own.
        cards().values.sorted { $0.publicationId < $1.publicationId }
    }

    /// The cards belonging to one source.
    ///
    /// `library-browsing` narrows the whole view to one source, and a search of a server's
    /// cache should not answer with another server's downloads.
    public func all(from sourceId: String) -> [KavitaCard] {
        all().filter { $0.sourceId == sourceId }
    }

    /// Forgets one publication's card.
    ///
    /// Called where the download goes. A card describing bytes nobody has is a row that
    /// would appear in an offline search and open nothing.
    public func remove(_ publicationId: String) {
        var all = cards()
        all[publicationId] = nil
        write(all)
    }

    /// Forgets every card one source produced.
    ///
    /// `sources` makes removing a source take its downloads with it, and what was cached
    /// about them is part of what it took.
    public func removeAll(from sourceId: String) {
        write(cards().filter { $0.value.sourceId != sourceId })
    }

    /// Forgets every card. Used by a reset, and by the tests.
    public func reset() { defaults.removeObject(forKey: key) }

    private func cards() -> [String: KavitaCard] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([String: KavitaCard].self, from: data)
        else { return [:] }
        return stored
    }

    private func write(_ value: [String: KavitaCard]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
