public import Foundation

/// A device after a sync merge, and what the merge has to tell the reader.
public struct LibrarySyncMerged: Sendable, Equatable {
    public var snapshot: LibrarySnapshot

    /// Positions where both devices had moved. Each is shown once, naming both positions.
    public var conflicts: [ProgressPull.Conflict]

    /// Hosts that gained an accepted certificate, and the source that names each.
    public var certificatePinsAdded: [CertificatePinNotice]

    /// Sources, by name, that the reader has to sign in to on this device.
    public var sourcesNeedingSignIn: [String]

    public init(
        snapshot: LibrarySnapshot,
        conflicts: [ProgressPull.Conflict] = [],
        certificatePinsAdded: [CertificatePinNotice] = [],
        sourcesNeedingSignIn: [String] = []
    ) {
        self.snapshot = snapshot
        self.conflicts = conflicts
        self.certificatePinsAdded = certificatePinsAdded
        self.sourcesNeedingSignIn = sourcesNeedingSignIn
    }
}

/// A sync document merged into this device.
///
/// `library-sync` *Two devices that both moved*. Unlike an import, nothing here simply takes
/// the document's side: a position goes by ADR-0006 (``ProgressPull``), a shelf's members are a
/// union, a deletion travels, and a setting or a theme field goes to the device that changed it
/// last. Pure, over a ``LibrarySnapshot``, so two devices can be reconciled in a test with no
/// store. Android's `LibrarySyncMerge` applies the same rules in the same order.
public enum LibrarySyncMerge {

    public static func merging(
        _ document: LibraryDocument,
        into local: LibrarySnapshot,
        device: String
    ) -> LibrarySyncMerged {
        let shelves = ShelfStamps.merging(local.shelves, removed: local.removedShelves, with: document.library)
        let settings = SettingsStamps.merging(
            local.settings, stamps: local.settingsChangedAt, with: document.library.settings, device: device
        )
        let themes = ThemeStamps.merging(
            local.themes, stamps: local.themesChangedAt, with: document.library.readingThemes, device: device
        )
        let progress = mergingProgress(document, into: local)

        var merged = local
        merged.sources = LibraryImport.mergingSources(document, into: local.sources)
        merged.certificatePins = LibraryImport.mergingPins(document, into: local.certificatePins)
        merged.shelves = shelves.shelves
        merged.removedShelves = shelves.removed
        merged.pinnedShelves = PinnedShelves(tokens: local.pinnedShelves.tokens + document.library.pinnedShelves)
        merged.settings = settings.value
        merged.settingsChangedAt = settings.changedAt
        merged.themes = themes.value
        merged.themesChangedAt = themes.changedAt
        merged.progress = progress.records
        merged.covers = local.covers + LibraryImport.coversArriving(document, onto: local)

        return LibrarySyncMerged(
            snapshot: merged,
            conflicts: progress.conflicts,
            certificatePinsAdded: LibraryImport.pinsArriving(document, onto: local),
            sourcesNeedingSignIn: LibraryImport.signInsNeeded(document, onto: local)
        )
    }

    /// Positions by ADR-0006, then each one the document now agrees on stamped as synchronised.
    ///
    /// `library-sync` task 3.2. The stamp is ``ReadingProgress/syncedPosition``, as
    /// `KavitaExchange.settled` writes it for a server. Without it, a position that moved on
    /// the other device after this sync would meet a stale watermark and raise a conflict that
    /// did not happen. A Kavita position is neither merged nor stamped: its watermark is
    /// Kavita's.
    private static func mergingProgress(_ document: LibraryDocument, into local: LibrarySnapshot)
        -> (records: [ReadingProgress], conflicts: [ProgressPull.Conflict]) {
        let arriving = onePerPublication(
            LibraryImport.readableProgress(document).filter { !local.ownedByKavita($0.identity) }
        )
        let held = onePerPublication(local.progress)
        let pull = ProgressPull.merging(remote: arriving) { identity in
            held.first { $0.identity.matches(identity) }
        }
        var merged = held
        for record in pull.toSave {
            if let existing = merged.firstIndex(where: { $0.identity.matches(record.identity) }) {
                // The device's own identity stays: it holds the current path, and an arriving
                // record from before a reinstall holds the old one (task 26.4).
                merged[existing] = record.identified(as: merged[existing].identity.filling(from: record.identity))
            } else {
                merged.append(record)
            }
        }
        let settled = merged.map { record -> ReadingProgress in
            guard !local.ownedByKavita(record.identity) else { return record }
            var stamped = record
            stamped.syncedPosition = record.position
            return stamped
        }
        return (settled, pull.conflicts)
    }

    /// One record for each publication, the newest, with the identity of every copy.
    ///
    /// Task 26.4: a document written across reinstalls held one record for each container
    /// path a folder audiobook had, seven for one book. The copies are one publication, so the
    /// document keeps one.
    static func onePerPublication(_ records: [ReadingProgress]) -> [ReadingProgress] {
        var kept: [ReadingProgress] = []
        for record in records.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            if let index = kept.firstIndex(where: { $0.identity.matches(record.identity) }) {
                kept[index] = kept[index].identified(as: kept[index].identity.filling(from: record.identity))
            } else {
                kept.append(record)
            }
        }
        return kept
    }
}

extension ReadingProgress {
    /// This record, filed under another identity.
    func identified(as identity: PublicationIdentity) -> ReadingProgress {
        ReadingProgress(
            identity: identity,
            position: position,
            isFinished: isFinished,
            finishedAt: finishedAt,
            updatedAt: updatedAt,
            syncedPosition: syncedPosition
        )
    }
}
