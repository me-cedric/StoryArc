public import Foundation

internal import Catalogue
internal import Kavita
public import Persistence
public import StoryArcCore

/// What the library knows about where its publications came from.
///
/// Split out of ``LibraryModel`` because the file grew past the 400-line cap, and this is
/// the seam that was already there: everything here answers a question about a *source*,
/// while the rest of the model answers questions about publications. The registry, its
/// persistence and the folder-to-source matching all live together.
extension LibraryModel {
    /// How many publications a source holds.
    ///
    /// `sources` asks a source's detail screen for its "cached item count". Counted from
    /// what the library actually found rather than remembered separately: two numbers that
    /// can disagree is how a screen ends up claiming a source has titles it cannot open.
    public func itemCount(of sourceID: Source.ID) -> Int {
        publications.count { $0.sourceID == sourceID }
    }

    // Internal, not private: `private` is file-scoped, and the callers now sit
    // in the other half of this type.
    /// The source a folder belongs to, if it is registered as one.
    ///
    /// Matched on the folder's name, the same key ``register(_:)`` uses. The app's own
    /// Documents folder is not a source, so a publication found there is unattributed —
    /// which is the honest answer rather than pretending it belongs to a library the
    /// reader picked.
    func source(of folder: URL) -> UUID? {
        registry.sources.first {
            $0.kind == .localFolder && $0.locator == folder.lastPathComponent
        }?.id
    }

    /// Adds a source the reader configured elsewhere, such as a catalogue.
    ///
    /// Distinct from ``register(_:)``, which adopts a folder the app already found. A
    /// catalogue arrives already confirmed — it answered, and it told us its name — so
    /// there is nothing to match and nothing to probe.
    public func add(_ source: Source) {
        guard registry[source.id] == nil else { return }
        registry = registry.adding(source)
        sourceStore?.save(registry)
    }

    // Internal, not private: `private` is file-scoped, and the callers now sit
    // in the other half of this type.
    /// Records a folder as a source, if it is not one already.
    ///
    /// Matched on the folder's name, which is what a bookmark restores by. A folder picked
    /// twice is one source, and the reader's own name for it survives — `sources` requires
    /// a rename to stick, so re-adding must not overwrite one.
    func register(_ url: URL) {
        let name = url.lastPathComponent
        // The bookmark's key, not the filesystem path. A path is not stable identity on
        // iOS: the app container carries a UUID that changes on reinstall and on restore to
        // a new device, so a path-keyed source is a *new* source every time — which showed
        // up as the same folder listed three times. `FolderBookmarks` keys on the folder's
        // own name, and that is what survives.
        let locator = url.lastPathComponent
        // Connected, not connecting. State is never persisted — it describes a network, and
        // a state read from disk is a claim about the past — so every source loads as
        // `connecting` and something has to answer. For a folder the answer is immediate:
        // it is reachable or it is not, and there is nothing to probe. Left unanswered it
        // sat on "Connecting" forever, which is what a reader saw.
        // Matched on where the folder *is*, not on what it is called. A reader who renames
        // a source keeps its name; matching by name would fail to recognise it on the next
        // launch and add the same folder a second time.
        //
        // The name is still consulted, but only to adopt a source stored before `locator`
        // existed. Without that a migration produces exactly the duplicate the locator was
        // added to prevent — which it did, on a device, before this line.
        let existing = registry.sources.first { $0.kind == .localFolder && $0.locator == locator }
            ?? registry.sources.first {
                $0.kind == .localFolder && $0.locator == nil && $0.displayName == name
            }

        if let existing {
            if existing.locator == nil { registry = registry.locating(existing.id, at: locator) }
            // A registry written by an intermediate build can already hold both: one row
            // that found its locator and one that never had one. The second is an artifact,
            // not a source, so it is discarded rather than tombstoned — a tombstone would
            // hold thirty days of progress retention open for a row nobody added.
            for stale in registry.sources where stale.id != existing.id
                && stale.kind == .localFolder && stale.locator == nil
                && stale.displayName == name {
                registry = registry.discarding(stale.id)
            }
            guard existing.state != .connected else {
                sourceStore?.save(registry)
                return
            }
            registry = registry.marking(existing.id, as: .connected)
        } else {
            registry = registry.adding(
                Source(displayName: name, kind: .localFolder, state: .connected, locator: locator)
            )
        }
        sourceStore?.save(registry)
    }

    /// Renames a source.
    ///
    /// The identifier does not move, so everything referring to the source follows — which
    /// is what `sources` means by a name appearing "everywhere the source is referenced".
    /// A blank name is refused by the registry rather than checked here.
    ///
    /// The folder on disk keeps its own name. This renames the *source*, and a reader who
    /// calls a folder "Comics" has not asked to rename the directory.
    public func rename(_ source: Source, to name: String) {
        registry = registry.renaming(source.id, to: name)
        sourceStore?.save(registry)
    }

    /// Removes a source and the folder behind it.
    ///
    /// Nothing could do this before: `sources` requires removal and there was no way to
    /// reach it, so a reader who picked the wrong folder was stuck with it.
    ///
    /// The bookmark goes, the folder goes, and the registry keeps a tombstone — so reading
    /// progress survives the thirty days the requirement promises rather than being
    /// cascaded away. Files on disk are never touched: this removes a *library*, not a
    /// reader's comics.
    public func remove(_ source: Source) {
        guard let folder = folders.first(where: { $0.lastPathComponent == source.locator })
        else { return }

        folder.stopAccessingSecurityScopedResource()
        // The bookmark is keyed by the folder's own name, which a rename never changes.
        bookmarks?.remove(named: folder.lastPathComponent)
        folders.removeAll { $0 == folder }
        registry = registry.removing(source.id, at: Date())
        sourceStore?.save(registry)

        // The publications it contributed go with it, and the rest of the shelf stays.
        publications.removeAll { $0.sourceID == source.id }
        rebuild()
    }
}

/// Collections and reading lists, and the reader's edits to them.
///
/// On ``LibraryModel`` because a grouping is a set of publication identities and the model
/// is what turns an identity back into a publication. A separate model would have to be
/// handed the library to be useful, which is the same thing with an extra hop.
extension LibraryModel {
    /// Every publication the reader has finished, for a reading list's progress line.
    ///
    /// A set rather than a predicate, because a list of forty entries would otherwise ask
    /// the progress store forty times while drawing one screen.
    public var finishedPublications: Set<String> {
        Set(progress.filter { $0.value.isFinished }.keys)
    }

    public func create(collection name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        shelves = shelves.adding(PublicationCollection(name: trimmed))
        shelvesStore?.save(shelves)
    }

    public func create(list name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        shelves = shelves.adding(ReadingList(name: trimmed))
        shelvesStore?.save(shelves)
    }

    public func add(_ members: Set<String>, toCollection id: UUID) {
        shelves = shelves.adding(members, to: id)
        shelvesStore?.save(shelves)
    }

    public func append(_ entries: [String], toList id: UUID) {
        shelves = shelves.appending(entries, to: id)
        shelvesStore?.save(shelves)
    }

    public func remove(_ entry: String, fromList id: UUID) {
        shelves = shelves.removing(entry, fromList: id)
        shelvesStore?.save(shelves)
    }

    public func move(_ entry: String, to destination: Int, inList id: UUID) {
        shelves = shelves.moving(entry, to: destination, inList: id)
        shelvesStore?.save(shelves)
    }

    public func delete(collection id: UUID) {
        shelves = shelves.deleting(collection: id)
        shelvesStore?.save(shelves)
    }

    public func delete(list id: UUID) {
        shelves = shelves.deleting(list: id)
        shelvesStore?.save(shelves)
    }
}

extension LibraryModel {
    /// What to offer when a publication is finished.
    ///
    /// A reading list wins over a series. `collections-and-reading-lists`: when a reader
    /// finishes an entry in a list, "the next entry in list order is offered, regardless of
    /// series or source" — a crossover read in publication order is exactly a case where
    /// the series' own next issue is the wrong answer.
    ///
    /// The first list containing it decides, when a publication is in several. Any rule
    /// here is arbitrary; this one is at least the reader's own order, since the lists are
    /// in the order they made them.
    ///
    /// Falls back to the series, which is what `comic-reader` asks for and what a reader
    /// who keeps no lists will always get.
    public func next(after publication: Publication) -> Publication? {
        for list in shelves.lists where list.entries.contains(publication.id) {
            guard let nextID = list.next(after: publication.id) else { continue }
            // An entry whose publication is gone does not stop the flow: the spec says an
            // unavailable entry "does not break the ordering or the next flow", so the
            // search carries on past it.
            if let found = publications.first(where: { $0.id == nextID }) { return found }
        }
        return LibraryIndex.next(after: publication, in: publications)
    }
}

extension LibraryModel {
    /// Marks a publication read or unread, and tells the server it came from.
    ///
    /// `reading-progress` allows a reader to mark a publication read by hand rather than by
    /// turning every page, and `kavita-server` requires that state to reach the server so
    /// its own UI agrees. Both halves happen here, because a mark that only landed locally
    /// would disagree with the shelf the reader is looking at on another device.
    /// The stores are built here rather than passed in. Both are thin wrappers -- one over
    /// `UserDefaults`, one over the keychain -- and threading them through four view
    /// initialisers to reach one menu button would be four parameters carrying nothing.
    func mark(_ publication: Publication, read isRead: Bool) async {
        let kavita = KavitaProgressStore()
        let credentials = CredentialStore()
        try? await progressStore?.mark(publication.identity, finished: isRead)
        await refreshProgress()

        guard let origin = kavita.origin(of: publication.id) else { return }
        let address = registry.sources
            .first { $0.id.uuidString == origin.sourceId }
            .flatMap { KavitaPage(source: $0, credentials: credentials)?.address }
        await KavitaSync.mark(isRead, for: origin, to: address, in: kavita)
    }

    /// Answers the question every network source asks on launch.
    ///
    /// `sources` requires a source's health to be shown. State is never persisted, so a
    /// catalogue or a server loads as `connecting` and stays there unless something asks --
    /// which nothing did, so every network source a reader added read "Connecting…" for
    /// ever, whether it was reachable or not.
    ///
    /// One request each, on appearance. Cheap enough to repeat and honest enough to trust:
    /// a state older than the last time the library was on screen is a claim about the past.
    func probeNetworkSources(credentials: CredentialStore?, pins: CertificatePins) async {
        for source in registry.sources
        where source.kind == .opdsCatalog || source.kind == .kavitaServer {
            let state = await reach(source, credentials: credentials, pins: pins)
            registry = registry.marking(source.id, as: state)
        }
        // Asked at the same moment, because it is the same question — what does this server
        // have — and the add-to menu cannot fetch it for itself without opening a connection
        // every time a reader long-presses a cover.
        serverLists = await ServerShelf.all(in: registry, credentials: credentials)
            .filter(\.isList)
    }

    /// Adds a publication to one of a server's reading lists.
    ///
    /// Returns false when the publication did not come from that server. `kavita-server`
    /// requires the app to explain that "a server list can only contain that server's
    /// publications" rather than silently doing nothing or silently doing the wrong thing.
    @discardableResult
    func add(_ publication: Publication, toServerList list: ServerShelf) async -> Bool {
        let kavita = KavitaProgressStore()
        guard let origin = kavita.origin(of: publication.id),
              origin.sourceId == list.server.id
        else { return false }

        let credentials = CredentialStore()
        let address = registry.sources
            .first { $0.id.uuidString == origin.sourceId }
            .flatMap { KavitaPage(source: $0, credentials: credentials)?.address }
        await KavitaSync.append(list.id, for: origin, to: address, in: kavita)
        return true
    }

    private func reach(
        _ source: Source,
        credentials: CredentialStore?,
        pins: CertificatePins
    ) async -> SourceConnectionState {
        if let page = KavitaPage(source: source, credentials: credentials) {
            do {
                _ = try await KavitaClient(address: page.address, pins: pins).connect()
                return .connected
            } catch KavitaError.keyRejected {
                return .unauthorized(reason: String(localized: "source.state.unauthorized",
                                                    bundle: .module))
            } catch {
                return .unreachable(since: Date())
            }
        }

        if let page = CataloguePage(source: source, credentials: credentials) {
            do {
                _ = try await OpdsClient(pins: pins).feed(at: page.url, credential: page.credential)
                return .connected
            } catch let error as OpdsError {
                if case .unauthorized = error {
                    return .unauthorized(reason: String(localized: "source.state.unauthorized",
                                                        bundle: .module))
                }
                return .unreachable(since: Date())
            } catch {
                return .unreachable(since: Date())
            }
        }

        // Neither page could be built, so the secret this source needs has gone.
        return .unauthorized(reason: String(localized: "source.state.unauthorized",
                                            bundle: .module))
    }
}
