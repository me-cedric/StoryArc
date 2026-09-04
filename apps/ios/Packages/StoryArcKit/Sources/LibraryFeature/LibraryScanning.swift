internal import Foundation
internal import Synchronization

internal import Formats
internal import Persistence
internal import StoryArcCore

/// Walking the places the library knows about, and picking up a walk that was interrupted.
///
/// A place is a folder the reader picked or a single publication another app handed over.
/// They are walked by one task, one after another, because the model holds one scan and a
/// second scan used to cancel the first.
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
    /// Scans one folder, picking up where an interrupted scan of it stopped.
    func scan(_ folder: URL) {
        scan([folder])
    }

    /// Scans several places, one after another, under a single cancellable task.
    ///
    /// The model holds one scan task, and the version of this that took one folder opened
    /// with `scanTask?.cancel()`. Every caller with more than one place to walk therefore
    /// cancelled its own previous walk: a reader with two libraries got the second one, and
    /// a reader who had opened a comic from another app got neither, because the remembered
    /// file went round the loop last and cancelled the folder they had actually picked.
    ///
    /// One task over a list rather than a task per place, so that cancelling still cancels
    /// everything — `local-library` requires the scan to be cancellable, and a reader who
    /// stops a scan means all of it. Android's `rescan` has always walked its trees this
    /// way, inside one job; this is iOS catching up to its mirror.
    func scan(_ places: [URL]) {
        scanTask?.cancel()
        skipsInThisScan = []
        scanTask = Task { [weak self] in
            // Whether any place this scan walked met a directory it could not list. Carried
            // as a return value rather than held on the model, because it is true of one
            // scan and nothing outside this task ever asks: see ``cacheLibrary(partial:)``,
            // which is the only reader, and the model is one line under its length cap.
            var partial = false
            for place in places {
                guard !Task.isCancelled else { return }
                if await self?.walk(place) == true { partial = true }
            }
            guard !Task.isCancelled else { return }
            self?.settleSkipped()
            // Written down here rather than per folder: a snapshot taken between two places
            // is a half-library, and restoring one would show a shelf missing books for no
            // reason a reader could see. **Nothing called this at all until 2026-09-05**, so
            // the file the next launch reads was never written — Android has always written
            // it at the same point, at the end of its one job over every tree.
            self?.cacheLibrary(partial: partial)
        }
    }

    /// Hands the whole scan's refusals to ``LibraryModel/skipped``, once.
    ///
    /// At the end of every place rather than at the end of each, because settling replaces
    /// the list — see ``SkippedPublications/settling(_:)``. A cancelled scan settles
    /// nothing: it did not finish walking, so what it did not meet is not evidence that
    /// anything was fixed.
    private func settleSkipped() {
        skipped = skipped.settling(skipsInThisScan)
    }

    /// The reader put the notice away. `library-browsing` keeps the list reachable.
    public func dismissSkipped() {
        skipped = skipped.dismissing()
    }

    /// Walks one place to the end: a folder, or a single remembered publication.
    ///
    /// Decided here rather than by the caller, from the filesystem rather than from the
    /// URL's spelling, so that a bookmark that resolves to something other than what was
    /// remembered still lands in the right half.
    ///
    /// - Returns: whether the walk met a directory it could not list. A remembered file is
    ///   never partial: it is one archive, and failing to open it is a refusal the reader is
    ///   told about by name rather than a hole in what the walk can account for.
    @discardableResult
    private func walk(_ place: URL) async -> Bool {
        let isDirectory = (try? place.resourceValues(forKeys: [.isDirectoryKey]))?
            .isDirectory ?? false
        if isDirectory {
            return await walkFolder(place)
        }
        await adoptRememberedFile(place)
        return false
    }

    /// Puts a publication another app handed over back on the shelf.
    ///
    /// `local-library`: the app "offers, once and unobtrusively, to remember it in the
    /// library". This is what remembering it comes to on the next launch — the book is
    /// there, opening reads the reader's own file where they left it, and nothing was
    /// copied.
    ///
    /// Attributed to no source, for the same reason the app's own Documents folder is not
    /// one: there is nothing here to remove, rename, reconnect or refresh, and a row in the
    /// source list named after a single comic would be a source the reader never added.
    /// `sources` orders a title found twice by the source the reader put higher, and no
    /// source ranks last — so the same book later found inside a picked folder is that
    /// folder's copy, which is the right answer.
    private func adoptRememberedFile(_ file: URL) async {
        for await event in LibraryScanner.scan(fileAt: file) {
            guard !Task.isCancelled else { return }
            // A remembered file the app can no longer open is exactly the case a reader
            // needs named: they handed this one book over themselves, and the shelf
            // silently losing it is the failure the notice exists for.
            if case let .skipped(path, reason) = event {
                skipsInThisScan.append(.init(name: path, reason: reason))
                continue
            }
            guard case let .found(publication) = event else { continue }
            adopt(publication, from: nil)
            // Set again rather than left to ``adopt``: a PDF or an EPUB carries a content
            // digest instead of a path, and the reader still has to be handed the file.
            locations[publication.id] = file
            rebuild()
        }
    }

    /// Walks a folder, picking up where an interrupted scan of it stopped.
    ///
    /// - Returns: whether any directory under it could not be listed.
    private func walkFolder(_ folder: URL) async -> Bool {
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

        // The walk reports an unlistable directory from whichever executor it is running on,
        // and this is read back on the main actor, so it cannot be a plain `var`. It is a
        // single flag rather than the paths themselves: nothing here names the folder, and
        // the two decisions that consult it — the reconcile and the snapshot — need only to
        // know that the walk cannot account for everything it was asked about.
        let unreadable = Mutex(false)

        let walk = LibraryScanner.scan(
            folderAt: folder,
            skipping: done,
            onUnreadableFolder: { _ in unreadable.withLock { $0 = true } }
        )
        for await event in walk {
            guard !Task.isCancelled else { return unreadable.withLock { $0 } }
            switch event {
            case let .found(publication):
                append(publication, in: folder)
            case let .skipped(path, reason):
                // Kept, not counted. The scanner has always emitted the reason
                // `publication-formats` words for this refusal, and this is where it used
                // to be dropped: a walk that met a 7-Zip container and a broken EPUB
                // reported "2 couldn't be opened" and lost both sentences. Still not
                // surfaced per file — a messy folder would be a wall of notices — but the
                // pairs reach the notice's list now instead of a tally.
                skipsInThisScan.append(.init(name: path, reason: reason))
            case let .finished(found, skipped):
                finish(
                    folder,
                    found: found + resumed.count,
                    skipped: skipped,
                    partial: unreadable.withLock { $0 }
                )
                // Progress is loaded here rather than only when the view
                // appears. The view appears before the scan produces anything,
                // so a load at that point matches recorded positions against an
                // empty library and the continue row never fills.
                await refreshProgress()
            }
        }
        return unreadable.withLock { $0 }
    }

    /// Walks every folder again, without emptying the shelf first.
    ///
    /// `sources`: a refresh "re-fetches the catalogue in the background" and updates the view
    /// "incrementally rather than clearing it and re-populating". ``scan(_:)-(URL)`` already
    /// appends to what is there and removes only what it can prove is gone, so all this adds
    /// is which places to walk and the wait for the last of them.
    ///
    /// Nothing here for a server: a catalogue's contents are browsed rather than folded into
    /// the shelf, so what a refresh means for one is asking whether it answers —
    /// ``refresh(_:)`` on a single source does that.
    public func rescan() async {
        scan(folders.isEmpty ? [documentsFolder] : folders)
        await scanTask?.value
        await refreshProgress()
    }

    /// Everything a finished scan settles.
    ///
    /// - Parameter partial: whether the walk met a directory it could not list. Passed on
    ///   rather than acted on here, because the two things it changes are two decisions:
    ///   what may be forgotten, and whether the shelf is still the cached one.
    private func finish(_ folder: URL, found: Int, skipped: Int, partial: Bool) {
        scanState = .finished(found: found, skipped: skipped)
        // Before the snapshot below, so what the walk did not meet is gone from the shelf
        // and from the snapshot alike.
        forgetVanished(under: folder, seen: seenInThisScan, partial: partial)
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
        // A walk of the app's own storage decides whether "On this device" is a library the
        // reader has. Here, once, rather than per publication: it is a question about the
        // whole shelf and the answer cannot change more than twice in a scan.
        if isAppStorage(folder) { reconcileAppStorageSource() }
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
    private func forgetVanished(under folder: URL, seen: Set<String>, partial: Bool) {
        // Only when the walk actually saw something. A walk that found nothing at all is
        // far more likely to be a folder it could not read — a permission dropped, a share
        // offline — than a reader who deleted every book they own. `sources` promises cached
        // content "remains browsable" when a source is unreachable, and emptying the shelf
        // on a failed walk is exactly the opposite. A library genuinely emptied is
        // reconciled by the next walk that finds anything.
        guard !seen.isEmpty else { return }
        // And only when it saw *everything*. The rule above was an inference from an empty
        // result, which covers the folder that became unreadable whole and misses the one
        // that lost a single subdirectory: that walk still returns rows, and every book under
        // the branch it could not list looked deleted. The walk reports the fact now, per
        // directory, for exactly this.
        guard !partial else { return }

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
        let isNew = adopt(publication, from: source(of: folder))
        // Met either way, and recorded before the early return. Whether the row was already
        // on the shelf says nothing about whether the file is still on disk, and the
        // reconcile below drops exactly the rows this walk did not meet — so a publication
        // the walk found but did not have to add would otherwise be treated as gone. A
        // remembered file that also lives inside a picked folder is met that way every
        // launch.
        seenInThisScan.insert(publication.id)
        guard isNew else { return }
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
