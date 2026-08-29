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
        publications.removeAll { publication in
            guard publication.sourceID == ImportedCopies.sourceID else { return false }
            return !files.contains(locations[publication.id]?.path ?? "")
        }

        guard !imports.isEmpty else {
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

    /// Puts "On this device" in the registry, if it is not there already.
    ///
    /// Added the moment there is something in it rather than at launch: `sources` requires
    /// the empty state to name the four source types, and a fifth row for a source holding
    /// nothing would be a source the reader never added.
    private func registerImportedSource() {
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
