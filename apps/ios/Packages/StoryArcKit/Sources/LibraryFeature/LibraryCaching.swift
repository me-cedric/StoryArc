internal import Foundation

internal import Persistence

/// Last session's shelf: putting it back, and writing the next one down.
///
/// Its own file rather than a middle section of ``LibraryModel``, which was one line under
/// the length the linter allows — and because this is a seam that was already there, the same
/// one ``LibraryScanning`` and ``LibraryRestore`` were split along. Android keeps the pair in
/// `LibraryViewModel` still, and its `cacheLibrary` takes the same argument.
///
/// **`sources` asks for two things here and the second was missing.** The cached catalogue is
/// shown "within 500 ms of the library view appearing", which is what ``restoreCachedLibrary``
/// serves — and "a single unobtrusive indicator" says the content is cached and when it was
/// last refreshed. Until now nothing on iOS ever *wrote* a snapshot after a walk: the only
/// caller of ``cacheLibrary(partial:)`` was the per-source *clear cache* action, so the file
/// the restore reads was never created, ``LibraryModel/cachedAt`` was never set, and
/// ``CachedNotice`` — a whole drawn view, with its own string — could not appear at all.
extension LibraryModel {
    // Internal, not private: the restore half of this type lives in another file, and
    // `private` is file-scoped.
    /// Puts last session's shelf back before anything is walked.
    ///
    /// `sources` asks the cached catalogue to be shown "within 500 ms of the library view
    /// appearing", and a folder walk is not that — it is a directory tree, an archive
    /// opened per file, and a metadata read per archive. This is a single JSON read.
    ///
    /// What follows is a scan, which now appends to this rather than replacing it, and
    /// removes only what it can prove is gone. So the reader sees their library at once and
    /// watches it correct itself, instead of watching it appear.
    func restoreCachedLibrary() {
        guard publications.isEmpty, let snapshot = libraryCache.read() else { return }
        publications = snapshot.publications
        locations = snapshot.locations.reduce(into: [:]) { result, pair in
            result[pair.key] = URL(fileURLWithPath: pair.value)
        }
        cachedAt = snapshot.refreshedAt
        rebuild()
    }

    /// Records the shelf as it now stands, for the next launch.
    ///
    /// Called when a walk finishes rather than as publications arrive: a snapshot written
    /// mid-scan is a half-library, and restoring one would show a shelf that is missing
    /// books for no reason a reader could see.
    ///
    /// - Parameter partial: whether the scan met a directory it could not list.
    ///
    ///   **The honest limit this closes.** The notice left the moment a walk finished,
    ///   including a walk that saw nothing because it could *see* nothing — which is exactly
    ///   when a reader most needs telling that the shelf is last session's. A walk that could
    ///   not list a directory has refreshed nothing, so it neither clears the indicator nor
    ///   stamps `now` into the snapshot, which would put the same lie on disk for the next
    ///   launch. ``LibraryScanner`` reports the fact per directory; ``LibraryScanning`` is
    ///   where it is gathered.
    func cacheLibrary(partial: Bool = false) {
        guard !partial else { return }
        // Same reason as the reconciliation: a walk that found nothing must not replace a
        // good snapshot with an empty one, or one unreadable folder costs the reader their
        // whole cached shelf on the next launch too.
        if publications.isEmpty, libraryCache.read()?.publications.isEmpty == false { return }
        libraryCache.write(
            LibraryCache.Snapshot(
                refreshedAt: .now,
                publications: publications,
                // `percentEncoded: false` because the read side is
                // `URL(fileURLWithPath:)`, which takes its string literally. `path()`
                // encodes by default, so a location under "Application Support" was written
                // as "Application%20Support" and never matched again on the next launch:
                // a downloaded publication silently lost its on-device mark and came back
                // as a second row beside itself.
                locations: locations.reduce(into: [:]) { $0[$1.key] = $1.value.path(percentEncoded: false) }
            )
        )
        cachedAt = nil
    }
}
