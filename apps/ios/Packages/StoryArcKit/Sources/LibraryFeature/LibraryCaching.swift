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
        // **A cached row whose file has moved is dropped, and the reason is a duplicate
        // shelf.** The snapshot records absolute paths, and on iOS an absolute path into the
        // app's own container is not stable: the container's UUID changes when the app is
        // reinstalled, so every recorded path dies at once while every file survives. The
        // scan then finds the same books at their new paths, and `adopt(_:from:)` cannot tell
        // they are the same books — `PublicationIdentity.matches` falls back to
        // `normalizedPath` when neither a server id nor a content digest was recorded, which
        // is the ordinary case for a local file, because digesting every file in a library to
        // list it would cost more than the walk. So both rows survive.
        //
        // Photographed on 2026-09-05: **every publication on the shelf twice** — once with
        // its cover and once as a format placeholder whose page reads "This cannot be opened
        // until it is on this device", for a file sitting in the app's own corpus directory.
        // 1926 tests passed throughout. It is also why every reflowable walk in the
        // repository was skipping: they pick a cover by title, and the fileless twin sorts
        // first.
        //
        // This is what the snapshot's own doc comment already promises — "a path that no
        // longer resolves is a publication the next scan will not find and will remove" —
        // applied at the moment of restore rather than left to a reconciliation that cannot
        // see it. A publication with no recorded location is kept: that is a server
        // publication, and its absence from this device is the point of it.
        let alive = snapshot.locations.filter { Self.stillThere($0.value) }
        publications = snapshot.publications.filter { publication in
            snapshot.locations[publication.id] == nil || alive[publication.id] != nil
        }
        locations = alive.reduce(into: [:]) { result, pair in
            result[pair.key] = URL(fileURLWithPath: pair.value)
        }
        cachedAt = snapshot.refreshedAt
        rebuild()
    }

    /// Whether a recorded path is a publication this device still holds.
    ///
    /// **Absence is not the question; *knowable* absence is.** A folder the app cannot list —
    /// a permission withdrawn, a volume not mounted — answers `fileExists` with `false` for
    /// every child, and dropping those rows would empty a reader's shelf for a reason that has
    /// nothing to do with their books. That is the case `LibraryShelfLifecycleTests`' "A walk
    /// that could not read the folder at all removes nothing either" pins, and this function
    /// exists because the first version of it failed exactly that test.
    ///
    /// So the parent decides. A file missing from a directory that *is* there and readable is
    /// a file that is gone. A file missing because its whole directory is gone is the reinstall
    /// case — the container moved and took every path with it — and those rows have to go, or
    /// the scan's re-find doubles the shelf. A directory that exists and refuses to be read is
    /// the one case where the honest answer is "cannot tell", and the row stays.
    private static func stillThere(_ path: String) -> Bool {
        let manager = FileManager.default
        if manager.fileExists(atPath: path) { return true }
        let parent = (path as NSString).deletingLastPathComponent
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: parent, isDirectory: &isDirectory), isDirectory.boolValue
        else { return false }
        return !manager.isReadableFile(atPath: parent)
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
