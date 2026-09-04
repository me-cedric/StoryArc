public import Foundation

internal import Formats
internal import Persistence
internal import StoryArcCore

/// The copies the reader brought into the app's own storage.
///
/// `local-library`'s imported copies: a publication imported "is copied into app storage,
/// indexed, and listed under an 'On this device' source". The copying and the record belong
/// to ``DownloadStore`` — see ``ImportedCopies`` for why that store and not a second one —
/// and the listing belongs here, because the library is what turns a file into a row.
///
/// Split out of ``LibraryModel`` for the same reason ``LibrarySources`` was: the file is at
/// its line cap, and this is a seam that was already there.
extension LibraryModel {
    /// Copies a publication into app storage and puts it in the library.
    ///
    /// The copy is indexed the same way a scanned file is, through ``PublicationIndexer``,
    /// so an imported comic carries the same title, series and cover a found one does.
    /// Indexing the *copy* rather than the original is what makes the promise true: from
    /// here on the library reads only bytes the app owns.
    public func importFile(_ url: URL) async {
        guard let store = downloadStore else { return }
        guard let copy = try? store.importing(url, into: store.library()) else {
            // Named, not silent. A reader who picked a file StoryArc cannot read has no
            // way to tell that from a broken app unless the app says which it is.
            importFailure = url.lastPathComponent
            return
        }
        registerImportedSource()
        await index(copy.file)
        rebuild()
    }

    /// Reconciles the library with what has actually been imported.
    ///
    /// Called on every appearance rather than once on launch, because the copies can change
    /// while the library is off screen: Settings is where one is deleted, and a library that
    /// only read the store at startup would keep offering a book whose bytes are gone.
    public func refreshImports() async {
        guard let store = downloadStore else { return }
        let imports = store.imports(in: store.library())
        let files = Set(imports.map { store.location(of: $0).path })

        // Rows whose copy has been deleted go. The record is the authority here, not a
        // filesystem walk: this store is the app's own, so an empty list means the reader
        // deleted their last import rather than that a folder could not be read.
        //
        // **Only the rows this store made, though.** "On this device" also carries what the
        // scan finds in the app's own Documents folder — see ``LibraryModel/source(of:)`` —
        // and the import store has never heard of those. Pruning by the import records alone
        // would sweep the whole Documents shelf off the screen on the next appearance, which
        // is a far worse bug than the one being fixed.
        publications.removeAll { publication in
            guard publication.sourceID == ImportedCopies.sourceID else { return false }
            guard let location = locations[publication.id] else { return true }
            guard !isAppStorage(location) else { return false }
            return !files.contains(location.path)
        }

        // Emptied only when *nothing* is filed under it, by either route.
        guard !imports.isEmpty || holdsAppStorage else {
            forgetImportedSource()
            rebuild()
            return
        }

        registerImportedSource()
        for download in imports {
            let file = store.location(of: download)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            guard !locations.values.contains(file) else { continue }
            await index(file)
        }
        rebuild()
    }

    /// What all the imported copies weigh, for a screen that reports the space used.
    public var importedBytes: Int64 {
        guard let store = downloadStore else { return 0 }
        return store.imports(in: store.library()).reduce(0) { $0 + $1.downloadedBytes }
    }

    private func index(_ file: URL) async {
        guard let publication = try? await PublicationIndexer.index(fileAt: file) else { return }
        adopt(publication, from: ImportedCopies.sourceID)
        // Set again rather than left to ``adopt``: the identity of a PDF or an EPUB can
        // carry a content digest instead of a path, and the reader still has to be handed
        // the file.
        locations[publication.id] = file
    }

    /// Whether the shelf holds anything found in the app's own storage.
    ///
    /// Asked of the shelf rather than of the disk: the row is what the source screen counts,
    /// so the row is what decides whether the source should be listed at all.
    var holdsAppStorage: Bool {
        publications.contains { publication in
            guard publication.sourceID == ImportedCopies.sourceID,
                  let location = locations[publication.id]
            else { return false }
            return isAppStorage(location)
        }
    }

    /// Lists "On this device" when something is filed under it, and stops listing it when
    /// nothing is.
    ///
    /// Called at the end of a folder walk rather than per publication: it is a question about
    /// the whole shelf, and asking it once per file during a ten-thousand-file scan is
    /// quadratic for an answer that cannot change more than twice.
    func reconcileAppStorageSource() {
        if publications.contains(where: { $0.sourceID == ImportedCopies.sourceID }) {
            registerImportedSource()
            return
        }
        // Nothing on the shelf under it, and nothing in the import store either — so the row
        // would be a library holding nothing that the reader never added.
        guard let store = downloadStore, !store.imports(in: store.library()).isEmpty else {
            forgetImportedSource()
            return
        }
        registerImportedSource()
    }

    /// Puts "On this device" in the registry, if it is not there already.
    ///
    /// Added the moment there is something in it rather than at launch: `sources` requires
    /// the empty state to name the four source types, and a fifth row for a source holding
    /// nothing would be a source the reader never added.
    func registerImportedSource() {
        guard registry[ImportedCopies.sourceID] == nil else { return }
        registry = registry.adding(
            Source(
                id: ImportedCopies.sourceID,
                displayName: String(
                    localized: "source.onThisDevice", bundle: .module, locale: .storyArc
                ),
                kind: .localFolder,
                state: .connected,
                // Not a path, and deliberately something no folder can be called: a
                // locator is matched against a picked folder's own last path component,
                // which can never hold a separator. Without that, a reader with a folder
                // named "On this device" would have it adopted as their imports.
                locator: Self.importedLocator
            )
        )
        sourceStore?.save(registry)
    }

    /// Takes "On this device" out again when the last copy has been deleted.
    ///
    /// Discarded rather than tombstoned. A tombstone says the reader removed a source and
    /// their progress should outlive it; this source was never added by hand, and holding
    /// thirty days of retention open for it would be retention for nothing.
    private func forgetImportedSource() {
        guard registry[ImportedCopies.sourceID] != nil else { return }
        registry = registry.discarding(ImportedCopies.sourceID)
        sourceStore?.save(registry)
    }

    static let importedLocator = "storyarc/imported"
}
