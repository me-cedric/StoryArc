public import StoryArcCore

/// The conflicts a library sync found, handed to the notice a refresh already shows.
///
/// `library-sync` task 5.4. The sync merges positions by ADR-0006 and returns each title both
/// devices had moved. The runner used to drop them, so the reader never saw D3's notice. They
/// go to ``RefreshConflicts``, which the library screen draws as ``SyncConflictNotice``: one
/// title names the kept and the discarded position, several give a count and Show. Android's
/// `SyncConflicts` is the same step.
public enum SyncConflicts {

    /// Adds what one sync found to the notice. None adds nothing.
    @MainActor
    public static func report(_ found: [ProgressPull.Conflict]) {
        RefreshConflicts.shared.report(found.map(notice))
    }

    /// One conflict as the notice names it. The sync document carries no title, so the title
    /// is the file's name without its extension, as a folder scan names a publication.
    static func notice(_ conflict: ProgressPull.Conflict) -> KavitaConflict {
        KavitaConflict(
            title: title(conflict.resolved.identity),
            resolved: conflict.resolved,
            discarded: conflict.discarded
        )
    }

    static func title(_ identity: PublicationIdentity) -> String {
        let path = identity.normalizedPath ?? ""
        let name = (path.removingPercentEncoding ?? path).split(separator: "/").last.map(String.init) ?? ""
        let leaf = name.split(separator: ":").last.map(String.init) ?? name
        guard let dot = leaf.lastIndex(of: "."), dot > leaf.startIndex else { return leaf }
        return String(leaf[..<dot])
    }
}
