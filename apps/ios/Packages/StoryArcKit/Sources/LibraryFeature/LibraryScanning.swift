internal import Foundation

internal import Formats
internal import Persistence
internal import StoryArcCore

/// How the shelf gets filled: the walk, what it adds, and what it stops finding.
///
/// Its own file rather than a tail on `LibraryModel.swift`, which had grown past the length
/// the linter allows. One subject — a scan is the only thing that puts a publication on the
/// shelf or takes one off it, and the cache above is the same story written down.
extension LibraryModel {
    func scan(_ folder: URL) {
        scanTask?.cancel()
        scanState = .scanning(found: publications.count)

        scanTask = Task { [weak self] in
            // What this walk actually saw, so what it did not see can go afterwards.
            var seen: Set<String> = []
            for await event in LibraryScanner.scan(folderAt: folder) {
                guard let self, !Task.isCancelled else { return }
                switch event {
                case let .found(publication):
                    seen.insert(publication.id)
                    self.append(publication, in: folder)
                case .skipped:
                    // Counted in the finished event. Not surfaced per-file: a scan
                    // of a messy folder would otherwise be a wall of notices.
                    break
                case let .finished(found, skipped):
                    self.forgetVanished(under: folder, seen: seen)
                    self.scanState = .finished(found: found, skipped: skipped)
                    self.cacheLibrary()
                    // Progress is loaded here rather than only when the view
                    // appears. The view appears before the scan produces anything,
                    // so a load at that point matches recorded positions against an
                    // empty library and the continue row never fills.
                    await self.refreshProgress()
                }
            }
        }
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
        var attributed = publication
        attributed.sourceID = source(of: folder)

        // A publication already present from another folder is not added twice.
        // Identity is what decides, not the path, so the same file reached two ways
        // is one row (ADR-0006).
        if let seen = publications.firstIndex(
            where: { $0.identity.matches(publication.identity) }
        ) {
            // Unless the second find knows something the first did not. The app's own
            // Documents folder is scanned before any source is restored, so a reader whose
            // library lives there had every publication found unattributed first — and a
            // source that holds eleven books reported nought. Whichever scan carries a
            // source wins; the earlier row is otherwise identical.
            if publications[seen].sourceID == nil, attributed.sourceID != nil {
                publications[seen].sourceID = attributed.sourceID
            }
            return
        }

        publications.append(attributed)
        if let path = publication.identity.normalizedPath {
            locations[publication.id] = URL(fileURLWithPath: path)
        }
        if case let .scanning(found) = scanState {
            scanState = .scanning(found: found + 1)
        }
        // ponytail: re-arranged in batches during a scan, not per publication —
        // sorting after every one of 10,000 appends is quadratic. The scan's own
        // completion rebuilds the rest, so the only visible effect is that the
        // last few rows arrive together.
        if publications.count % rebuildEvery == 0 { rebuild() }
    }
}
