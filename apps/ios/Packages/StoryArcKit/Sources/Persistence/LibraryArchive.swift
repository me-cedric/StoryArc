public import Foundation

public import StoryArcCore

/// The seven stores a ``LibrarySnapshot`` is made of, read together and written together.
///
/// `library-portability` names what an export carries, and what it names is spread across
/// `UserDefaults` and one SwiftData store. This is the only place that knows which store holds
/// which part, so ``LibraryExport`` and ``LibraryImport`` can stay pure and be asserted
/// without a disk.
///
/// Android's `LibraryArchive` reads and writes the same seven.
public struct LibraryArchive {
    private let defaults: UserDefaults
    private let progress: ProgressStore

    public init(defaults: UserDefaults = .standard, progress: ProgressStore) {
        self.defaults = defaults
        self.progress = progress
    }

    /// Everything the export carries, as it stands right now.
    public func snapshot() async throws -> LibrarySnapshot {
        LibrarySnapshot(
            sources: SourceStore(defaults: defaults).registry(),
            certificatePins: CertificatePinStore(defaults: defaults).pins(),
            shelves: ShelvesStore(defaults: defaults).shelves(),
            pinnedShelves: PinnedShelves(
                stored: defaults.string(forKey: PinnedShelves.storageKey) ?? ""
            ),
            settings: SettingsStore(defaults: defaults).settings(),
            themes: ReaderPreferences(defaults: defaults).themes(),
            // Everything, not a page of it. `recent(limit:)` is the only enumeration this
            // store has, and the export wants every record rather than the ones a
            // "Continue reading" row would show.
            progress: try await progress.recent(limit: .max)
        )
    }

    /// Writes a merged snapshot back, store by store.
    ///
    /// Reading progress goes through ``ProgressStore/save(_:)`` one record at a time rather
    /// than being written wholesale, because that method is where finished stays sticky — a
    /// bulk write that bypassed it could unmark a publication the merge had just decided was
    /// finished.
    public func apply(_ snapshot: LibrarySnapshot) async throws {
        SourceStore(defaults: defaults).save(snapshot.sources)
        CertificatePinStore(defaults: defaults).save(snapshot.certificatePins)
        ShelvesStore(defaults: defaults).save(snapshot.shelves)
        defaults.set(snapshot.pinnedShelves.stored, forKey: PinnedShelves.storageKey)
        SettingsStore(defaults: defaults).save(snapshot.settings)
        ReaderPreferences(defaults: defaults).save(snapshot.themes)
        for record in snapshot.progress {
            try await progress.save(record)
            if record.isFinished {
                try await progress.mark(record.identity, finished: true, at: record.updatedAt)
            }
        }
    }
}
