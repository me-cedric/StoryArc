internal import Foundation

internal import Formats
internal import Persistence
internal import StoryArcCore

/// Walking a folder, and picking up a walk that was interrupted.
///
/// `local-library`: a scan "is cancellable and resumable, and does not block browsing what
/// it has already found". The first and the third were free — the stream stops when nothing
/// consumes it, and rows appear as they arrive. Resumable was not: a scan of ten thousand
/// comics is minutes of opening archives, and a reader whose phone reclaimed the process
/// watched the whole thing happen again from an empty grid.
///
/// Split out of ``LibraryModel`` for the same reason ``LibrarySources`` was: the file is at
/// its line cap, and this is a seam that was already there.
extension LibraryModel {
    /// Scans a folder, picking up where an interrupted scan of it stopped.
    func scan(_ folder: URL) {
        scanTask?.cancel()

        // Put back before the walk starts, so a reader who left mid-scan comes back to the
        // library they had rather than to an empty grid filling up again.
        let resumed = journal?.indexed(inFolder: folder.path) ?? []
        let sourceID = source(of: folder)
        for publication in resumed { adopt(publication, from: sourceID) }
        if !resumed.isEmpty { rebuild() }

        scanningFolder = folder
        scanned = resumed
        scanState = .scanning(found: publications.count)
        // Matched on the path, which is what a directory walk knows. A publication whose
        // identity is a content digest is still filed under the file it came out of.
        let done = Set(resumed.compactMap(\.identity.normalizedPath))

        scanTask = Task { [weak self] in
            for await event in LibraryScanner.scan(folderAt: folder, skipping: done) {
                guard let self, !Task.isCancelled else { return }
                switch event {
                case let .found(publication):
                    self.append(publication, in: folder)
                case .skipped:
                    // Counted in the finished event. Not surfaced per-file: a scan
                    // of a messy folder would otherwise be a wall of notices.
                    break
                case let .finished(found, skipped):
                    self.finish(folder, found: found + resumed.count, skipped: skipped)
                    // Progress is loaded here rather than only when the view
                    // appears. The view appears before the scan produces anything,
                    // so a load at that point matches recorded positions against an
                    // empty library and the continue row never fills.
                    await self.refreshProgress()
                }
            }
        }
    }

    /// Everything a finished scan settles.
    private func finish(_ folder: URL, found: Int, skipped: Int) {
        scanState = .finished(found: found, skipped: skipped)
        // Before the snapshot below, so what the walk did not meet is gone from the shelf
        // and from the snapshot alike.
        forgetVanished(under: folder, seen: seenInThisScan)
        seenInThisScan = []
        // Nothing left to resume. Cleared rather than kept: this is a journal, not the
        // metadata cache `sources` asks for, and a journal that outlived its scan would be
        // a stale library nobody decided to keep.
        journal?.clear(folder: folder.path)
        scanningFolder = nil
        scanned = []
        // What the folder held at the moment the scan agreed with it. Without this the
        // first reconcile would see every file as new and re-read the whole library to
        // learn nothing.
        snapshots[folder.path] = FolderSnapshot(LibraryScanner.entries(in: folder))
    }

    /// Drops what this folder no longer holds.
    ///
    /// `sources`: when a refresh shows a publication "is no longer present in the source",
    /// it "is removed from the library view and its reading progress is retained". The
    /// second half needs no code — progress lives in its own store, keyed by identity, and
    /// nothing here touches it, so a file that comes back finds its position waiting.
    ///
    /// Scoped to the folder that was walked. A scan of one source must not evict another
    /// source's titles just because it did not happen to see them, which is the mistake
    /// that turns a refresh into a library that empties one folder at a time.
    private func forgetVanished(under folder: URL, seen: Set<String>) {
        // Only when the walk actually saw something. A walk that found nothing at all is
        // far more likely to be a folder it could not read — a permission dropped, a share
        // offline — than a reader who deleted every book they own. `sources` promises cached
        // content "remains browsable" when a source is unreachable, and emptying the shelf
        // on a failed walk is exactly the opposite. A library genuinely emptied is
        // reconciled by the next walk that finds anything.
        guard !seen.isEmpty else { return }

        let gone = publications.filter { publication in
            guard !seen.contains(publication.id),
                  let location = locations[publication.id]
            else { return false }
            return location.path().hasPrefix(folder.path())
        }
        guard !gone.isEmpty else { return }

        let ids = Set(gone.map(\.id))
        publications.removeAll { ids.contains($0.id) }
        for id in ids {
            covers[id] = nil
            locations[id] = nil
        }
    }

    private func append(_ publication: Publication, in folder: URL) {
        // Attributed here rather than by the indexer: indexing decides what a publication
        // is, and the library is the only thing that knows which source it was reached
        // through. `sources` needs this for a source's item count, and
        // `library-browsing` for the order two sources holding one title appear in.
        guard adopt(publication, from: source(of: folder)) else { return }
        seenInThisScan.insert(publication.id)
        scanned.append(publication)
        if case let .scanning(found) = scanState {
            scanState = .scanning(found: found + 1)
        }
        // ponytail: re-arranged in batches during a scan, not per publication —
        // sorting after every one of 10,000 appends is quadratic. The scan's own
        // completion rebuilds the rest, so the only visible effect is that the
        // last few rows arrive together.
        if publications.count % rebuildEvery == 0 { rebuild() }
        // Written down on the same beat. A journal flushed per publication would cost a
        // `UserDefaults` write per file; one every two dozen loses at most that many to a
        // process the system reclaims without warning — which is the case this exists for,
        // because a killed process runs no cleanup of its own.
        if scanned.count % rebuildEvery == 0 {
            journal?.record(scanned, inFolder: folder.path)
        }
    }

    // Internal, not private: `private` is file-scoped, and the imported copies sit in
    // another file.
    /// Puts a publication in the library under the source it was reached through, and
    /// says whether it was new.
    ///
    /// Shared by the folder scan and by the imported copies, which find publications two
    /// entirely different ways and have to agree about what one row means.
    @discardableResult
    func adopt(_ publication: Publication, from sourceID: UUID?) -> Bool {
        var attributed = publication
        attributed.sourceID = sourceID

        // A publication already present from another folder is not added twice.
        // Identity is what decides, not the path, so the same file reached two ways
        // is one row (ADR-0006).
        if let seen = publications.firstIndex(
            where: { $0.identity.matches(publication.identity) }
        ) {
            // Unless this find came through a source the reader put higher. `sources`: the
            // combined view "lists titles from higher sources first when two sources hold
            // the same publication" — so the registry's order decides which copy the row is,
            // not which scan happened to reach it first. ``SourcePrecedence`` is where that
            // comparison lives and where it is asserted.
            //
            // The unattributed case falls out of the same rule: the app's own Documents
            // folder is scanned before any source is restored, so a reader whose library
            // lives there had every publication found with no source at all — and a source
            // holding eleven books reported nought. Nil ranks last, so the source wins.
            guard SourcePrecedence.prefers(
                attributed.sourceID,
                over: publications[seen].sourceID,
                in: registry.sources
            ) else { return false }

            publications[seen].sourceID = attributed.sourceID
            // The file goes with the attribution. A row that says one source and opens the
            // other source's copy is the same bug wearing a different hat.
            if let path = publication.identity.normalizedPath {
                locations[publications[seen].id] = URL(fileURLWithPath: path)
            }
            return false
        }

        publications.append(attributed)
        if let path = publication.identity.normalizedPath {
            locations[publication.id] = URL(fileURLWithPath: path)
        }
        return true
    }
}
