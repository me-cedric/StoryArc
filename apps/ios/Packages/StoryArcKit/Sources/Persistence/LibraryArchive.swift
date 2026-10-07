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
    private let progress: any ProgressLedger

    public init(defaults: UserDefaults = .standard, progress: any ProgressLedger) {
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

    /// Writes a merged snapshot back, all or nothing.
    ///
    /// `library-portability` / *Import merges*: a throw part-way leaves the device as it was.
    /// The device is read first. On a failure the six small stores are written back from that
    /// reading and the progress records are put back one by one, and then the failure is
    /// thrown again. An import that stopped after the third store would otherwise leave a
    /// library that is neither the old one nor the new one, and nothing to say so.
    public func apply(_ snapshot: LibrarySnapshot) async throws {
        let before = try await self.snapshot()
        do {
            writeStores(snapshot)
            try await writeProgress(snapshot.progress)
        } catch {
            writeStores(before)
            // The failure the reader needs is the first one. A second one while undoing
            // cannot be shown better than that, so it does not replace it.
            await restoreProgress(before.progress, over: snapshot.progress)
            throw error
        }
    }

    private func writeStores(_ snapshot: LibrarySnapshot) {
        SourceStore(defaults: defaults).save(snapshot.sources)
        CertificatePinStore(defaults: defaults).save(snapshot.certificatePins)
        ShelvesStore(defaults: defaults).save(snapshot.shelves)
        defaults.set(snapshot.pinnedShelves.stored, forKey: PinnedShelves.storageKey)
        SettingsStore(defaults: defaults).save(snapshot.settings)
        ReaderPreferences(defaults: defaults).save(snapshot.themes)
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
