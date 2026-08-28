public import Foundation
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
