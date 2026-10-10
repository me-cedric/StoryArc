public import Foundation

public import Kavita
public import Persistence
public import StoryArcCore

/// Where an entry opened from, when it opened from a server reading list.
///
/// `collections-and-reading-lists` task 7.3: a server list never joins ``Shelves/lists``
/// (nothing builds ``ShelfOrigin/server(_:)``), so ``LibraryModel/next(after:)`` cannot see
/// one — it has nothing to walk. This is the app's memory of the one list order a reader is
/// actually inside, carried from ``KavitaListView``'s own row tap to the reader's
/// end-of-book offer, the way Android's `ServerListContext` carries it.
@MainActor
public enum ServerListContext {

    /// One server reading list, in the order ``KavitaListView`` showed it.
    public struct Place: Sendable {
        public let serverId: String
        public let serverAddress: KavitaAddress
        public let listId: Int
        /// The confirmed entries, in display order. A pending entry has none to fetch.
        public let entries: [KavitaReadingListItem]
        /// Where in `entries` the reader opened.
        public var position: Int

        public var next: KavitaReadingListItem? {
            entries.indices.contains(position + 1) ? entries[position + 1] : nil
        }

        public var previous: KavitaReadingListItem? {
            entries.indices.contains(position - 1) ? entries[position - 1] : nil
        }

        /// Whether `publication` is the entry this place is holding open.
        public func holds(_ publication: Publication) -> Bool {
            guard entries.indices.contains(position), let remote = publication.identity.serverIdentifier else {
                return false
            }
            return remote.sourceID.uuidString == serverId && remote.remoteID == "chapter:\(entries[position].chapterId)"
        }

        /// What the next (or previous) entry is called, before it is fetched — so the end
        /// screen can name it the way ``LibraryModel/next(after:)``'s own answer names a
        /// local one.
        public func placeholder(of item: KavitaReadingListItem) -> Publication? {
            guard let sourceID = UUID(uuidString: serverId) else { return nil }
            return Publication(
                identity: PublicationIdentity(
                    serverIdentifier: .init(sourceID: sourceID, remoteID: "chapter:\(item.chapterId)")
                ),
                format: .cbz,
                displayTitle: item.displayName,
                origin: .authoritative
            )
        }
    }

    public private(set) static var current: Place?

    /// Remembered the moment an entry opens from ``KavitaListView``.
    public static func opened(_ place: Place) {
        current = place
    }

    /// Forgets the place, so a publication opened some other way is offered nothing.
    public static func clear() {
        current = nil
    }

    /// What the reader's end screen offers after `publication`, when it is the one
    /// `current` is holding open. `nil` otherwise — including at the end of the list, which
    /// leaves `LibraryModel.next`'s own series fallback to answer instead.
    public static func next(after publication: Publication) -> Publication? {
        guard let place = current, place.holds(publication), let item = place.next else { return nil }
        return place.placeholder(of: item)
    }

    /// The mirror of ``next(after:)``, for the chapter-actions "previous" control.
    public static func previous(before publication: Publication) -> Publication? {
        guard let place = current, place.holds(publication), let item = place.previous else { return nil }
        return place.placeholder(of: item)
    }

    /// What fetching the next or the previous entry found.
    public enum Fetch: Equatable {
        case opened(Publication, URL)
        /// The sentence the failure owes the reader. It names the entry.
        case failed(String)
    }

    /// Fetches `item` the way ``KavitaListView``'s own row does, and advances `current` to
    /// it on success — so asking again walks forward rather than refetching the same chapter.
    ///
    /// - Parameter client: the connection to fetch through. Built from `place.serverAddress`
    ///   when omitted, which is what every production caller does; a test passes one built
    ///   with a stub configuration, the way `KavitaOpenFailureTests` already does.
    public static func fetch(
        _ place: Place,
        _ item: KavitaReadingListItem,
        through client: KavitaClient? = nil
    ) async -> Fetch {
        let opening = await KavitaEntryOpening.attempt(
            item,
            sourceId: place.serverId,
            store: KavitaProgressStore(),
            from: client ?? KavitaClient(address: place.serverAddress)
        )
        guard case let .opened(publication, url) = opening else {
            let reason = String(localized: "kavita.open.failed \(item.displayName)",
                                bundle: .module.inChosenLanguage, locale: .storyArc)
            return .failed(reason)
        }
        if let index = place.entries.firstIndex(where: { $0.chapterId == item.chapterId }) {
            var moved = place
            moved.position = index
            current = moved
        }
        return .opened(publication, url)
    }

    /// Opens the entry an end screen offered, when `offered` is one that ``next(after:)`` or
    /// ``previous(before:)`` answered. The fetch is the list view's own, and so is the seed of
    /// the server's position. `nil` when `offered` names no entry of `current`.
    ///
    /// Tasks 7.3 and 7.14: the offer names a server list's entry before this device has a file
    /// for it, so taking the offer fetches one rather than looking for a file that is not there.
    public static func open(
        _ offered: Publication,
        seeding progress: ProgressStore?,
        through client: KavitaClient? = nil
    ) async -> Fetch? {
        guard let place = current, let remote = offered.identity.serverIdentifier,
              remote.sourceID.uuidString == place.serverId,
              let item = place.entries.first(where: { remote.remoteID == "chapter:\($0.chapterId)" })
        else { return nil }
        let fetched = await fetch(place, item, through: client)
        if case let .opened(publication, _) = fetched {
            await seedKavitaOpen(publication, pagesRead: item.pagesRead, of: item.pagesTotal, into: progress)
        }
        return fetched
    }
}

extension LibraryModel {
    /// What an end-of-publication screen offers after `publication`: the next entry of the
    /// server list the reader is inside, or else the library's own next.
    ///
    /// Task 7.14: the library's next can be a Kavita or OPDS row with no file on this device.
    /// An end screen cannot open that row, so the offer leaves it out.
    public func offeredNext(after publication: Publication) -> Publication? {
        ServerListContext.next(after: publication) ?? next(after: publication).flatMap(openable)
    }

    /// The mirror of ``offeredNext(after:)``, for the chapter actions' "previous" control.
    public func offeredPrevious(before publication: Publication) -> Publication? {
        ServerListContext.previous(before: publication) ?? previous(before: publication).flatMap(openable)
    }

    private func openable(_ publication: Publication) -> Publication? {
        location(of: publication) == nil ? nil : publication
    }
}
