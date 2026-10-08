public import Foundation

public import StoryArcCore

/// The seven stores a ``LibrarySnapshot`` is made of, read together and written together, and
/// the cover store when one is handed in.
///
/// `library-portability` names what an export carries, and what it names is spread across
/// `UserDefaults` and one SwiftData store. This is the only place that knows which store holds
/// which part, so ``LibraryExport`` and ``LibraryImport`` can stay pure and be asserted
/// without a disk.
///
/// Android's `LibraryArchive` reads and writes the same seven.
///
/// `@unchecked Sendable`: it holds a `UserDefaults`, which is documented as safe to use from any
/// thread but is not marked so. The other stores are `Sendable` already.
public struct LibraryArchive: @unchecked Sendable {
    private let defaults: UserDefaults
    private let progress: any ProgressLedger
    private let covers: (any ChosenCoverStore)?
    private let now: @Sendable () -> Date

    /// - Parameter covers: where chosen covers are kept. `Persistence` cannot see `Formats`,
    ///   so the app hands the store in; an archive built without one neither reads nor writes
    ///   covers.
    public init(
        defaults: UserDefaults = .standard,
        progress: any ProgressLedger,
        covers: (any ChosenCoverStore)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.defaults = defaults
        self.progress = progress
        self.covers = covers
        self.now = now
    }

    /// The failure an import reports when a cover could not be written.
    public struct CoverNotWritten: Error, Equatable {
        public let key: String
    }

    /// Everything the export carries, as it stands right now.
    public func snapshot() async throws -> LibrarySnapshot {
        let shelves = ShelvesStore(defaults: defaults)
        var library = LibrarySnapshot(
            sources: SourceStore(defaults: defaults).registry(),
            certificatePins: CertificatePinStore(defaults: defaults).pins(),
            shelves: shelves.shelves(),
            pinnedShelves: PinnedShelves(
                stored: defaults.string(forKey: PinnedShelves.storageKey) ?? ""
            ),
            settings: SettingsStore(defaults: defaults).settings(),
            themes: ReaderPreferences(defaults: defaults).themes(),
            // Everything, not a page of it. `recent(limit:)` is the only enumeration this
            // store has, and the export wants every record rather than the ones a
            // "Continue reading" row would show.
            progress: try await progress.recent(limit: .max),
            removedShelves: shelves.removed(),
            settingsChangedAt: SettingsStore(defaults: defaults).changedAt(),
            themesChangedAt: ReaderPreferences(defaults: defaults).themesChangedAt(),
            kavitaKept: KavitaProgressStore(defaults: defaults).rememberedPublications()
        )
        library.covers = covers?.chosen(including: Self.coverKeys(in: library)) ?? []
        return library
    }

    /// Every key a cover could be filed under for what the library holds, for the covers a
    /// store has no key file for.
    private static func coverKeys(in library: LibrarySnapshot) -> [String] {
        library.progress.map { $0.identity.coverOverrideKey }
            + library.shelves.collections.flatMap(\.members)
            + library.shelves.lists.flatMap(\.entries)
    }

    /// Writes a merged snapshot back, all or nothing.
    ///
    /// `library-portability` / *Import merges*: a throw part-way leaves the device as it was.
    /// The device is read first. On a failure the six small stores are written back from that
    /// reading and the progress records are put back one by one, and then the failure is
    /// thrown again. An import that stopped after the third store would otherwise leave a
    /// library that is neither the old one nor the new one, and nothing to say so.
    public func apply(_ snapshot: LibrarySnapshot) async throws {
        let before = try await self.snapshot()
        var replacedCovers: [(key: String, previous: Data?)] = []
        do {
            try writeCovers(snapshot.covers, replaced: &replacedCovers)
            writeStores(snapshot)
            try await writeProgress(snapshot.progress)
        } catch {
            restoreCovers(replacedCovers)
            writeStores(before, exactly: true)
            // The failure the reader needs is the first one. A second one while undoing
            // cannot be shown better than that, so it does not replace it.
            await restoreProgress(before.progress, over: snapshot.progress)
            throw error
        }
    }

    /// Each cover the device does not hold already, with what it replaced noted for the undo.
    private func writeCovers(
        _ chosen: [ChosenCover],
        replaced: inout [(key: String, previous: Data?)]
    ) throws {
        guard let covers else { return }
        for cover in chosen {
            let previous = covers.image(forKey: cover.key)
            guard previous != cover.image else { continue }
            guard covers.store(cover.image, forKey: cover.key) else {
                throw CoverNotWritten(key: cover.key)
            }
            replaced.append((cover.key, previous))
        }
    }

    private func restoreCovers(_ replaced: [(key: String, previous: Data?)]) {
        for (key, previous) in replaced {
            if let previous {
                covers?.store(previous, forKey: key)
            } else {
                covers?.remove(forKey: key)
            }
        }
    }

    /// - Parameter exactly: true for an undo, which puts back the moments and deletions as they
    ///   were. Otherwise a store stamps what changed and records what was deleted.
    private func writeStores(_ snapshot: LibrarySnapshot, exactly: Bool = false) {
        SourceStore(defaults: defaults).save(snapshot.sources)
        CertificatePinStore(defaults: defaults).save(snapshot.certificatePins)
        defaults.set(snapshot.pinnedShelves.stored, forKey: PinnedShelves.storageKey)
        let shelves = ShelvesStore(defaults: defaults, now: now)
        let settings = SettingsStore(defaults: defaults, now: now)
        let reader = ReaderPreferences(defaults: defaults, now: now)
        if exactly {
            shelves.restore(snapshot.shelves, removed: snapshot.removedShelves)
            settings.restore(snapshot.settings, changedAt: snapshot.settingsChangedAt)
            reader.restore(snapshot.themes, changedAt: snapshot.themesChangedAt)
        } else {
            shelves.save(snapshot.shelves, removed: snapshot.removedShelves)
            settings.save(snapshot.settings, changedAt: snapshot.settingsChangedAt)
            reader.save(snapshot.themes, changedAt: snapshot.themesChangedAt)
        }
    }

    /// Reading progress goes through ``ProgressLedger/save(_:)`` one record at a time rather
    /// than being written wholesale, because that method is where finished stays sticky — a
    /// bulk write that bypassed it could unmark a publication the merge had just decided was
    /// finished.
    private func writeProgress(_ records: [ReadingProgress]) async throws {
        for record in records {
            try await progress.save(record)
            if record.isFinished {
                try await progress.mark(record.identity, finished: true, at: record.updatedAt)
            }
        }
    }

    /// Puts every record the import may have touched back as `before` held it.
    ///
    /// A record `before` did not hold is forgotten. One it held is saved again, and then
    /// marked unfinished when it was unfinished: ``ProgressLedger/save(_:)`` keeps finished
    /// sticky, so saving alone would leave the flag the import turned on.
    private func restoreProgress(
        _ before: [ReadingProgress],
        over touched: [ReadingProgress]
    ) async {
        for record in touched {
            if let prior = before.first(where: { $0.identity.matches(record.identity) }) {
                try? await progress.save(prior)
                if !prior.isFinished {
                    try? await progress.mark(prior.identity, finished: false, at: prior.updatedAt)
                }
            } else {
                try? await progress.forget(record.identity)
            }
        }
    }
}
