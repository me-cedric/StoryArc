internal import Foundation

public import StoryArcCore

/// What the filter control offers, and how it is turned off.
///
/// Split out of ``LibraryModel`` because that file was within thirty lines of the
/// 400-line cap, and this is a seam that was already there: everything here
/// answers "what can the reader narrow the library by", and every value comes from
/// the publications the library actually holds. A filter that offers a value no
/// publication carries would empty the shelf the moment it was ticked, which is
/// only avoidable from the library itself.
extension LibraryModel {
    /// Clears every filter, keeping the search and the sort.
    ///
    /// `library-browsing`: an empty-looking library must say filters are active
    /// and offer one action to clear them. This is that action. Which groups it
    /// clears lives on the query itself, so a facet added to the query cannot be
    /// forgotten here.
    public func clearFilters() {
        query = query.withoutFilters
    }

    /// Formats actually present, so the filter never offers one that would empty
    /// the library.
    public var availableFormats: [PublicationFormat] {
        Array(Set(publications.map(\.format))).sorted { $0.displayName < $1.displayName }
    }

    /// Languages actually present, as codes. The view names them for the reader —
    /// the model has no business holding "Français".
    ///
    /// Collated like the other three even though a language tag is ASCII: nothing
    /// validates what a `ComicInfo.xml` writes into `<LanguageISO>`, so a mis-tagged
    /// file spelling the language out reaches this list as it is spelled.
    public var availableLanguages: [String] {
        collated(Set(publications.compactMap(\.language)))
    }

    /// Publishers actually present, as the files spell them.
    public var availablePublishers: [String] {
        collated(Set(publications.compactMap(\.publisher)))
    }

    /// Genres actually present, gathered from every publication's list.
    public var availableGenres: [String] {
        collated(Set(publications.flatMap(\.genres)))
    }

    /// Tags actually present. Kept apart from ``availableGenres`` because the
    /// files keep them apart.
    public var availableTags: [String] {
        collated(Set(publications.flatMap(\.tags)))
    }

    /// The decades the library spans, newest first.
    ///
    /// `library-browsing` asks for a year *range*, and ``LibraryQuery/years``
    /// carries an arbitrary one — which is what the tests assert and what a future
    /// control will set. What the menu offers is decades, because a menu cannot ask
    /// for two numbers without becoming a form, and a decade is a range a reader
    /// picks in one tap. Derived from the years actually present, so the filter
    /// never offers a decade the library has nothing in.
    public var availableDecades: [Int] {
        Array(Set(publications.compactMap(\.year).map { $0 - $0 % 10 })).sorted(by: >)
    }

    /// Filter values in the order a reader of the chosen language reads them.
    ///
    /// A bare `sorted()` is Swift's `<` on `String`, which is code point order: *É* is U+00C9
    /// and *Z* is U+005A, so every accented value landed after every unaccented one and a
    /// French reader found *Éditions* past *Zenith*. That is not the wrong collation, it is
    /// none — the shelf, the search results and a reading list all collate and this menu did
    /// not.
    ///
    /// `.caseInsensitive` against ``Locale/storyArc``, which is the same comparison
    /// `LibraryIndex` gives the shelf, so a value is filed in one place wherever it is drawn.
    /// Without ``LibraryIndex/sortKey(_:locale:)``, though: that strips a leading article so a
    /// title files under its first real word, and `library-browsing` asks for it on **titles**.
    /// A publisher named *The Comic Company* is a name, not a title, and filing it under C
    /// would be a behaviour no requirement asks for.
    ///
    /// The raw comparison breaks a tie, and it is not decoration. A case-insensitive collation
    /// calls *marvel* and *Marvel* equal while `Set` holds them as two values in an order that
    /// is not fixed between runs, so the menu could draw them either way round on two launches
    /// of one library. It decides only between values that collate equal.
    ///
    /// The locale is read once per sort rather than once per comparison: ``Locale/storyArc``
    /// builds `Locale.Components` from the reader's choice on every access. Android's
    /// ``LibraryFacets`` builds its `Collator` once for the same reason.
    private func collated(_ values: Set<String>) -> [String] {
        let locale = Locale.storyArc
        return values.sorted {
            let byReader = $0.compare($1, options: [.caseInsensitive], range: nil, locale: locale)
            return byReader == .orderedSame ? $0 < $1 : byReader == .orderedAscending
        }
    }
}

/// Whether StoryArc has fetched a publication and is keeping it, as a filter group.
///
/// `library-browsing` lists **download state** among the facets, and its *Filtering offline*
/// scenario asks that filtering to "Downloaded" show "only publications readable without a
/// network … regardless of source state".
///
/// **This is not the availability axis wearing a second name**, though the two are close
/// enough that one of them would otherwise have been redundant.
/// ``LibraryAvailability/onThisDevice`` keeps everything that opens from a file URL — a
/// folder the reader picked as much as a download the app fetched — because that axis asks
/// *will this open on a plane*. This asks the narrower question `offline-downloads` owns:
/// did **this app** fetch it, and is it keeping it. A file a folder scan found answers yes
/// to the first and no to the second, and the difference is not academic — the card can be
/// pulled, the bookmark can stale, the grant can lapse, which is what
/// ``LibraryModel/unavailableFolders`` exists for. Only a copy in the app's own storage
/// carries `offline-downloads`' promise, which is the same line ``LibraryModel/isOnDevice``
/// draws for the mark on a cover.
///
/// So the group admits a subset of what the axis admits, and *Filtering offline*'s clause
/// stays true of it — everything downloaded is readable without a network — while the two
/// controls answer different questions. The spec's own Open Question said as much before
/// either existed: what blocked download state was that "the library is assembled from a
/// scan that never consults" the record of downloaded files. The axis never needed that
/// record. This does.
///
/// Held beside the library's screens rather than on ``LibraryQuery``, exactly as
/// ``LibraryAvailability`` is: the query is the value both platforms encode, and a case
/// added to it is a change to `StoryArcCore` and to Android's mirror of it. Android keeps
/// the same three answers in `DownloadFilter.kt`.
public enum DownloadFilter: String, CaseIterable, Sendable {
    /// No opinion. Named for what the reader sees rather than for the group being empty:
    /// the menu row reads "Downloaded or not", which is what this shows.
    case either
    /// Only what the app fetched and is keeping.
    case downloaded
    /// Only what it has not. The question before a journey, rather than during one.
    case notDownloaded

    /// Whether the group is narrowing anything.
    ///
    /// What the filter badge counts and what "Clear filters" has to undo. A group that
    /// counted while it was off would make the badge disagree with the shelf.
    public var isActive: Bool { self != .either }

    /// Whether a publication survives the group.
    ///
    /// The whole rule, in one place, so both platforms can assert the same three cases
    /// rather than read them off a menu.
    public func keeps(isDownloaded: Bool) -> Bool {
        switch self {
        case .either: true
        case .downloaded: isDownloaded
        case .notDownloaded: !isDownloaded
        }
    }

    /// The shelf as this group leaves it.
    ///
    /// Applied over an already-sorted list rather than inside the query, so ticking the
    /// group costs one pass and never a re-sort — the same arrangement
    /// ``LibraryAvailability`` uses, and for the same reason.
    public func narrow(
        _ publications: [Publication],
        isDownloaded: (Publication) -> Bool
    ) -> [Publication] {
        guard isActive else { return publications }
        return publications.filter { keeps(isDownloaded: isDownloaded($0)) }
    }

    /// Where the choice is written down.
    ///
    /// `library-browsing` promises that "active filters are still applied" after leaving
    /// the library and returning. Every other facet gets that from `LibraryQuery` being
    /// saved; this one is not on the query, so it carries its own key beside
    /// ``LibraryAvailability/storageKey`` in the same `UserDefaults`.
    static let storageKey = "app.storyarc.libraryDownloadFilter"
}
