public import Foundation

public import StoryArcCore

/// What a scan reports as it goes.
///
/// `local-library` requires a scan to report progress as a count of items found
/// and not to block browsing what it has already found — so it emits as it walks
/// rather than returning a list at the end.
public enum ScanEvent: Sendable, Equatable {
    /// A publication was indexed. Emitted the moment it is known, so the first
    /// screen can fill while the rest of the folder is still being walked.
    case found(Publication)
    /// A file was recognised and not indexed. Carries a reason the library can
    /// show, because `publication-formats` forbids a silent failure.
    case skipped(path: String, reason: String)
    /// The walk finished.
    case finished(found: Int, skipped: Int)
}

/// Walks a folder and turns what it finds into publications.
///
/// `local-library`: "walks it recursively, identifies supported publications,
/// extracts covers and metadata, and reports progress as a count of items found",
/// cancellable, resumable, and never blocking the browsing of what is already
/// found.
///
/// The stream is what delivers all four of those at once. Cancelling the
/// consuming task stops the walk; the events already delivered are the resumable
/// state; and nothing waits for the whole folder before the first row appears.
public enum LibraryScanner {
    /// Extensions worth opening. A cheap pre-filter, not the decision — format is
    /// still determined from content, so a `.cbz` that is really a RAR opens as a
    /// RAR. This only avoids opening every text file in a folder.
    private static let candidateExtensions: Set<String> = [
        "cbz", "cbr", "cb7", "cbt", "epub", "pdf", "zip", "rar",
    ]

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "avif", "heic", "bmp", "tif", "tiff",
    ]

    /// Whether a file is a candidate part or a candidate audiobook.
    ///
    /// **Audio is deliberately not in ``candidateExtensions``.** Putting it there would make
    /// every part of a folder of chapter MP3s its own publication, which is the one thing
    /// `publication-formats` says a folder of audio is not — "a folder holds ordered audio
    /// files … it is treated as a single audiobook". So audio is counted separately, exactly
    /// as images already are, and the folder-versus-file decision below reads both.
    ///
    /// The set itself is `FolderKind`'s, so the walk and the kind cannot disagree about what
    /// counts as audio.
    private static func isAudio(_ url: URL) -> Bool {
        FolderKind.audioExtensions.contains(url.pathExtension.lowercased())
    }

    /// Publications in `folder`, emitted as they are found.
    ///
    /// Depth-first and alphabetical, so the order a user sees matches the order
    /// they would see in a file browser — a scan that returns rows in filesystem
    /// order looks broken even when it is complete.
    /// - Parameter known: what the library already holds for a path, if anything.
    ///
    ///   `local-library` asks a returning app to reconcile "by comparing file modification
    ///   times and sizes rather than re-reading every archive". A publication handed back
    ///   here whose size and modification date still match the file is emitted as it is,
    ///   and the container is never opened. Default is "nothing is known", which is a full
    ///   re-index and what a first scan wants.
    ///
    ///   A closure rather than a store: this module reads containers and knows nothing
    ///   about caches or registries, and handing it a question keeps it that way.
    ///
    ///   **Nothing passes this yet, and whoever first does has one trap to avoid.** A
    ///   publication handed back here is emitted exactly as it was cached, identity
    ///   included — so a cache written before content digests existed would hand back
    ///   path-only identities for ever, and the rename this exists to survive would go
    ///   on losing the reader's place on every device that had already scanned once.
    ///   A cached publication with no `contentDigest` must be re-indexed, or have one
    ///   attached, before it is emitted.
    /// - Parameter skipping: paths an earlier, interrupted scan of this folder already
    ///   indexed. `local-library` requires a scan to be "cancellable and resumable", and
    ///   this is the resumable half: the walk still visits them, which costs one directory
    ///   listing, and opens none of them, which is where the minutes go.
    ///
    ///   The two are different refusals and both are wanted: `known` still emits a
    ///   publication and only declines to reopen its container, while `skipping` emits
    ///   nothing at all because the caller has already put those back itself.
    public static func scan(
        folderAt folder: URL,
        known: (@Sendable (URL) -> Publication?)? = nil,
        skipping: Set<String> = []
    ) -> AsyncStream<ScanEvent> {
        AsyncStream<ScanEvent> { continuation in
            let task = Task {
                // The picked folder's own name is not a series: it is the library.
                let tally = await walk(folder, seriesHint: nil, known: known, skipping: skipping) {
                    continuation.yield($0)
                }
                if !Task.isCancelled {
                    continuation.yield(.finished(found: tally.found, skipped: tally.skipped))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// One publication, emitted the same way a walk emits one of many.
    ///
    /// `local-library` remembers a file another app handed over, and a remembered file is a
    /// publication rather than a library. Handed to ``scan(folderAt:known:skipping:)`` it
    /// produced nothing at all — `contentsOfDirectory` on a regular file lists nothing and
    /// the walk finished `found: 0` — which is how a reader ended up with an empty shelf
    /// named after their own book.
    ///
    /// The same stream, so a caller feeds a remembered file and a picked folder through one
    /// path and gets the same events, the same reconcile against `known`, and the same
    /// filesystem facts stamped on what comes out. A second, quieter way of indexing would
    /// be a second place for the two to disagree.
    ///
    /// No `skipping`: there is one thing here, and a caller that already has it does not
    /// call this at all.
    public static func scan(
        fileAt file: URL,
        known: (@Sendable (URL) -> Publication?)? = nil
    ) -> AsyncStream<ScanEvent> {
        AsyncStream<ScanEvent> { continuation in
            let task = Task {
                // No series hint. A file reached on its own has no folder above it that the
                // app is entitled to read, so its own name is all there is to go on.
                let tally = await index(file, seriesHint: nil, known: known) {
                    continuation.yield($0)
                }
                if !Task.isCancelled {
                    continuation.yield(.finished(found: tally.found, skipped: tally.skipped))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Everything in a folder, for a caller that genuinely wants the whole list.
    ///
    /// The indexer for a small folder, or a test. A library UI should consume the
    /// stream instead — this waits for the last file before returning the first.
    public static func scanAll(folderAt folder: URL) async -> [Publication] {
        var publications: [Publication] = []
        for await event in scan(folderAt: folder) {
            if case let .found(publication) = event { publications.append(publication) }
        }
        return publications
    }

    // MARK: - Listing

    /// What a folder holds, without opening anything in it.
    ///
    /// The cheap half of `local-library`'s watched changes: the app "reconciles by comparing
    /// file modification times and sizes rather than re-reading every archive". A directory
    /// listing is one call per folder; opening an archive is hundreds of reads, and a
    /// reconcile that opened them all would be the full rescan the requirement forbids.
    ///
    /// The same decisions as ``scan(folderAt:)`` — the same extensions, and the same
    /// a-folder-of-images-is-one-publication rule — because the two lists are compared
    /// against each other. A disagreement would make the same publication appear and
    /// disappear on every pass.
    public static func entries(in folder: URL) -> [FolderSnapshot.Entry] {
        var found: [FolderSnapshot.Entry] = []
        list(folder, into: &found)
        return found
    }

    private static func list(_ directory: URL, into found: inout [FolderSnapshot.Entry]) {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var files: [URL] = []
        var directories: [URL] = []
        for child in children {
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?
                .isDirectory ?? false
            if isDirectory { directories.append(child) } else { files.append(child) }
        }

        let publications = files.filter {
            candidateExtensions.contains($0.pathExtension.lowercased())
        }
        let images = files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
        let audio = files.filter { isAudio($0) }
        if publications.isEmpty, !images.isEmpty || !audio.isEmpty {
            found.append(entry(for: directory))
            return
        }
        // A lone audiobook beside packed comics is its own row. It is not in
        // `candidateExtensions` on purpose — see that property's own note.
        for file in publications + audio { found.append(entry(for: file)) }
        for child in directories { list(child, into: &found) }
    }

    /// One listing row. A folder of images has no size of its own, so it is compared on its
    /// modification date alone — which is what changes when a page is added to it.
    private static func entry(for url: URL) -> FolderSnapshot.Entry {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return FolderSnapshot.Entry(
            path: normalized(url),
            modified: values?.contentModificationDate ?? .distantPast,
            size: Int64(values?.fileSize ?? 0)
        )
    }

    // MARK: - Walking

    /// How much a walk found, so counts add up across recursion without shared
    /// mutable state.
    private struct Tally {
        var found = 0
        var skipped = 0

        static func += (lhs: inout Tally, rhs: Tally) {
            lhs = lhs + rhs
        }

        static func + (lhs: Tally, rhs: Tally) -> Tally {
            Tally(found: lhs.found + rhs.found, skipped: lhs.skipped + rhs.skipped)
        }
    }

    /// - Parameter seriesHint: what to call the series when a publication's own
    ///   name does not say. `local-library` presents a subfolder of a library "as a
    ///   series whose name is the folder name"; passing the name down as a hint is
    ///   the metadata half of that, and it is why the top-level call passes `nil` —
    ///   the library's own folder is not a series.
    private static func walk(
        _ directory: URL,
        seriesHint: String?,
        known: (@Sendable (URL) -> Publication?)? = nil,
        skipping: Set<String>,
        emit: @Sendable (ScanEvent) -> Void
    ) async -> Tally {
        var tally = Tally()
        guard !Task.isCancelled else { return tally }
        let children = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        // Alphabetical, case-insensitively, so the order matches a file browser's.
        let sorted = children.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }

        var files: [URL] = []
        var directories: [URL] = []
        for child in sorted {
            let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?
                .isDirectory ?? false
            if isDirectory { directories.append(child) } else { files.append(child) }
        }

        // A directory holding images and no publications is itself one publication.
        // A directory holding publications is a shelf. Deciding per directory is
        // what lets an unpacked comic sit next to packed ones without either being
        // mistaken for the other.
        let publicationFiles = files.filter {
            candidateExtensions.contains($0.pathExtension.lowercased())
        }
        let imageFiles = files.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
        let audioFiles = files.filter { isAudio($0) }

        if publicationFiles.isEmpty, !imageFiles.isEmpty || !audioFiles.isEmpty {
            // Its subdirectories are chapters of it, not separate publications.
            //
            // Which kind of publication is `FolderKind`'s answer, not this one's: a folder
            // of images is a comic, a folder of audio is an audiobook, and one holding both
            // is whichever it holds more of. The walk only has to decide that the *folder*
            // is the unit, which is the same decision for both.
            guard !skipping.contains(normalized(directory)) else { return tally }
            return tally + (await index(directory, seriesHint: seriesHint, known: known, emit: emit))
        }

        // Audio beside packed publications is indexed file by file, because a folder holding
        // comics is a shelf and an audiobook standing on it is one book.
        for file in publicationFiles + audioFiles {
            guard !Task.isCancelled else { return tally }
            // Already done by the scan this one is picking up from. Not counted either: the
            // caller put those publications back itself and has already counted them.
            guard !skipping.contains(normalized(file)) else { continue }
            tally += await index(file, seriesHint: seriesHint, known: known, emit: emit)
        }
        for child in directories {
            guard !Task.isCancelled else { return tally }
            tally += await walk(
                child, seriesHint: child.lastPathComponent,
                known: known, skipping: skipping, emit: emit
            )
        }
        return tally
    }

    /// The form a publication's identity records a path in.
    ///
    /// `contentsOfDirectory` hands back `/private/var/…` where the identity holds `/var/…`,
    /// because the indexer standardises what it is given. Comparing the two raw is how a
    /// resumed scan skips nothing and re-opens the whole folder, and how a reconcile fails
    /// to find the row belonging to a file that has gone.
    static func normalized(_ url: URL) -> String {
        (url.path as NSString).standardizingPath
    }

    private static func index(
        _ url: URL,
        seriesHint: String?,
        known: (@Sendable (URL) -> Publication?)? = nil,
        emit: @Sendable (ScanEvent) -> Void
    ) async -> Tally {
        // The reconcile `local-library` asks for. One `stat` decides whether the container
        // has to be opened at all, and for a library that has not changed since the last
        // launch — which is most launches — the answer is no, for every publication in it.
        if let cached = known?(url) {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let size = values?.fileSize.map(Int64.init)
            if cached.matchesFile(size: size, modifiedAt: values?.contentModificationDate) {
                emit(.found(cached))
                return Tally(found: 1, skipped: 0)
            }
        }

        do {
            var publication = try await PublicationIndexer.index(fileAt: url, seriesHint: seriesHint)
            stampFileFacts(on: &publication, at: url)
            emit(.found(publication))
            return Tally(found: 1, skipped: 0)
        } catch let error as PublicationIndexer.IndexError {
            emit(.skipped(path: url.lastPathComponent, reason: skipReason(for: error)))
        } catch {
            emit(.skipped(path: url.lastPathComponent, reason: "it could not be read"))
        }
        return Tally(found: 0, skipped: 1)
    }

    /// The two things about a publication that only the filesystem knows.
    ///
    /// `library-browsing` sorts by date added and by file size, and neither is
    /// written anywhere inside a comic. The walk is where they come from because
    /// the walk is the part that touches the filesystem — the indexer below it
    /// reads containers and is handed bytes, not directory entries.
    ///
    /// "Date added" is the date the Finder shows under that name: when this file
    /// arrived in this folder, which is what a reader means by recently added. Not
    /// every filesystem records it, so creation and then modification stand in —
    /// each is a worse answer to the same question rather than a different one.
    private static func stampFileFacts(on publication: inout Publication, at url: URL) {
        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey, .addedToDirectoryDateKey, .creationDateKey, .contentModificationDateKey,
        ])
        publication.addedAt = values?.addedToDirectoryDate
            ?? values?.creationDate
            ?? values?.contentModificationDate
        publication.modifiedAt = values?.contentModificationDate
        // Nil for a directory, and left alone there: an unpacked folder was already
        // weighed by the pages the indexer found inside it.
        if let size = values?.fileSize { publication.fileSize = Int64(size) }
    }

    /// A reason in words a person can act on.
    ///
    /// "7-Zip is not supported" tells someone to convert the file; "could not open"
    /// tells them nothing, which is what `publication-formats` forbids.
    static func skipReason(for error: PublicationIndexer.IndexError) -> String {
        switch error {
        case let .unsupported(format): "\(format) is not a format StoryArc reads"
        case let .unreadable(reason): reason
        // Distinct from the line above, and `publication-formats` requires it to be: the
        // format is one StoryArc reads and this file is locked by the store that sold it.
        // No key is asked for here or anywhere.
        case .contentProtected: "it is protected by its store's content protection"
        }
    }
}

extension ScanEvent {
    /// The publication, when this event carries one.
    public var publication: Publication? {
        if case let .found(publication) = self { return publication }
        return nil
    }
}
