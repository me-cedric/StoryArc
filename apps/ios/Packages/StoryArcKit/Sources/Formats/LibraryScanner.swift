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

    /// Publications in `folder`, emitted as they are found.
    ///
    /// Depth-first and alphabetical, so the order a user sees matches the order
    /// they would see in a file browser — a scan that returns rows in filesystem
    /// order looks broken even when it is complete.
    public static func scan(folderAt folder: URL) -> AsyncStream<ScanEvent> {
        AsyncStream<ScanEvent> { continuation in
            let task = Task {
                let tally = await walk(folder) { continuation.yield($0) }
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

    // MARK: - Walking

    /// How much a walk found, so counts add up across recursion without shared
    /// mutable state.
    private struct Tally {
        var found = 0
        var skipped = 0

        static func + (lhs: Tally, rhs: Tally) -> Tally {
            Tally(found: lhs.found + rhs.found, skipped: lhs.skipped + rhs.skipped)
        }
    }

    private static func walk(
        _ directory: URL,
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

        if publicationFiles.isEmpty, !imageFiles.isEmpty {
            // Its subdirectories are chapters of it, not separate publications.
            return tally + (await index(directory, emit: emit))
        }

        for file in publicationFiles {
            guard !Task.isCancelled else { return tally }
            tally = tally + (await index(file, emit: emit))
        }
        for child in directories {
            guard !Task.isCancelled else { return tally }
            tally = tally + (await walk(child, emit: emit))
        }
        return tally
    }

    private static func index(
        _ url: URL,
        emit: @Sendable (ScanEvent) -> Void
    ) async -> Tally {
        do {
            let publication = try await PublicationIndexer.index(fileAt: url)
            emit(.found(publication))
            return Tally(found: 1, skipped: 0)
        } catch let error as PublicationIndexer.IndexError {
            emit(.skipped(path: url.lastPathComponent, reason: reason(for: error)))
        } catch {
            emit(.skipped(path: url.lastPathComponent, reason: "it could not be read"))
        }
        return Tally(found: 0, skipped: 1)
    }

    /// A reason in words a person can act on.
    ///
    /// "7-Zip is not supported" tells someone to convert the file; "could not open"
    /// tells them nothing, which is what `publication-formats` forbids.
    private static func reason(for error: PublicationIndexer.IndexError) -> String {
        switch error {
        case let .unsupported(format): "\(format) is not a format StoryArc reads"
        case let .unreadable(reason): reason
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
