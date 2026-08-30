public import Foundation

public import StoryArcCore

/// What has been downloaded, on disk and in a list.
///
/// Two halves that have to agree: the files, and the record of them. This owns both, so
/// there is one place where "the app thinks it has this" and "the bytes are there" can be
/// made true together — the alternative is a list that outlives its files, which reads to
/// a reader as a library that lost their book.
public struct DownloadStore {
    private let defaults: UserDefaults
    private let key = "app.storyarc.downloads"

    /// Where the files live.
    public let directory: URL

    public init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        self.directory = directory ?? URL.applicationSupportDirectory
            .appending(path: "Downloads", directoryHint: .isDirectory)
    }

    public func library() -> DownloadLibrary {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([StoredDownload].self, from: data)
        else { return DownloadLibrary() }
        return DownloadLibrary(downloads: stored.map(\.download))
    }

    public func save(_ library: DownloadLibrary) {
        let stored = library.downloads.map(StoredDownload.init)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: key)
    }

    /// Where one publication's file goes.
    ///
    /// Named by identity rather than title: two catalogues can offer the same title, and a
    /// filename collision would hand the reader the wrong book.
    ///
    /// The id is the directory and the name is the file's. It used to be the other way
    /// round, and an OPDS download landed as `urn-storyarc-6.cbz`: the indexer reads a
    /// title and a series out of a filename, so a downloaded comic was called after its
    /// identifier everywhere, and `comic-reader`'s per-series settings keyed on one issue.
    /// The id still makes the path unique; it no longer has to be the name as well.
    ///
    /// All three parameters are required. The optional `named` this replaced is the whole bug: a caller
    /// that left it out got `<id>/<id>.cbz` while a caller that passed it got
    /// `<id>/<title>.cbz`, and the two never met until a reader removed a download from
    /// Settings and the bytes stayed — so the storage total on that same screen never moved.
    public func location(for id: String, mediaType: String, title: String) -> URL {
        let folder = directory.appending(path: Self.safe(id), directoryHint: .isDirectory)
        // Blank, not merely empty. A space survives `safe` — it is a character a filesystem
        // takes — so a publication with a whitespace title would be written as `  .cbz`,
        // which is a file a reader cannot see the name of and a shell cannot easily reach.
        // Android's half already treated blank as absent; this is iOS catching up.
        let named = Self.safe(title).trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = named.isEmpty ? Self.safe(id) : named
        return folder
            .appending(path: stem)
            .appendingPathExtension(Self.extension(for: mediaType))
    }

    /// Everything one download owns on disk.
    ///
    /// The directory, not the file. Each download has a directory to itself, keyed by its id
    /// alone, so removing that removes the bytes whatever the file inside happens to be
    /// called — including one written by a build that named it differently. A delete that
    /// does not depend on the stem cannot disagree with the write about it.
    public func remove(_ download: Download) {
        try? FileManager.default.removeItem(
            at: directory.appending(path: Self.safe(download.id), directoryHint: .isDirectory)
        )
    }

    /// The download a file inside ``directory`` belongs to.
    ///
    /// Matched on the directory the file sits in, not on the file's own name. The name is
    /// the publication's and has already changed once; the directory is the download's
    /// identifier and is what every writer of this tree agrees on.
    ///
    /// The library asks. `library-browsing` requires one library spanning every source, so
    /// a comic downloaded from a server has to appear on the shelf attributed to that
    /// server — and the file on disk carries no memory of where it came from.
    public func download(forFileAt url: URL, in library: DownloadLibrary) -> Download? {
        let folder = url.deletingLastPathComponent().lastPathComponent
        return library.downloads.first { Self.safe($0.id) == folder }
    }

    /// A name a filesystem will take: no separators, nothing that reads as a path.
    private static func safe(_ text: String) -> String {
        text.replacing(#/[^A-Za-z0-9._ -]/#, with: "-")
    }

    /// Makes the directory, and keeps it out of backups.
    ///
    /// `offline-downloads`: downloads "are excluded from device backups, because they are
    /// re-downloadable and would otherwise dominate a backup". Set on the directory, so it
    /// applies to every file put in it rather than to whichever ones remembered to ask.
    public func prepare() throws {
        var directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }

    /// Forgets a download and deletes its file, saving the result.
    ///
    /// Both halves in one call, because they are one act: a record without its file is a
    /// library that lost a book, and a file without its record is bytes nothing can find.
    @discardableResult
    public func removing(_ id: Download.ID, from library: DownloadLibrary) -> DownloadLibrary {
        if let download = library[id] {
            remove(download)
        }
        let without = library.removing(id)
        save(without)
        return without
    }

    /// The file extension a media type implies, or `bin` when it implies none.
    ///
    /// Here rather than in the caller: the store chose the name when the file was written
    /// and has to choose the same one to find it again.
    public static func `extension`(for mediaType: String) -> String {
        PublicationFormat(mediaType: mediaType)?.rawValue ?? "bin"
    }

    /// Deletes one download's file, and returns whether there was one.
    @discardableResult
    public func delete(_ file: URL) -> Bool {
        (try? FileManager.default.removeItem(at: file)) != nil
    }

    /// What the files actually weigh, which is not always what the record says.
    ///
    /// Asked by the storage view rather than trusted from the list: the system can reclaim
    /// a file, and a storage total that counts bytes nobody has is the kind of number that
    /// makes a reader distrust the whole screen.
    public func bytesOnDisk() -> Int64 {
        // Walked, not listed: each download sits in a directory of its own, so the top
        // level holds no files at all and a listing of it would total zero.
        guard let walk = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walk {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            total += Int64(values?.fileSize ?? 0)
        }
        return total
    }

    /// Deletes every downloaded file, forgets every record, and leaves the directory ready
    /// for the next download.
    ///
    /// `settings-and-about` asks for downloads to be clearable beside the cache and the
    /// reading history. Not a loop over ``removing(_:from:)``: that writes the library once
    /// per publication, so a reader whose app is killed halfway through is left with a
    /// device that is neither cleared nor intact.
    @discardableResult
    public func clearing() -> DownloadLibrary {
        reset()
        // Re-made rather than left missing, because the exclusion from backups is a
        // property of the directory: a directory re-created by the next download would not
        // carry it.
        try? prepare()
        return DownloadLibrary()
    }

    /// Forgets every download. Used by a reset, and by the tests.
    public func reset() {
        defaults.removeObject(forKey: key)
        try? FileManager.default.removeItem(at: directory)
    }
}

/// What is actually written.
///
/// A separate shape rather than making ``Download`` `Codable`, for the same reason
/// `StoredRegistry` exists: the durable fields and the runtime ones are different sets. A
/// download that was *running* when the app died is queued when it comes back, because
/// "running" describes a transfer that is no longer happening.
private struct StoredDownload: Codable {
    let id: String
    let sourceID: UUID?
    let title: String
    let remote: URL
    let mediaType: String
    let expectedBytes: Int64?
    let downloadedBytes: Int64
    let completedAt: Date?
    let isFinished: Bool
    let failure: String?
    let attempts: Int

    init(_ download: Download) {
        id = download.id
        sourceID = download.sourceID
        title = download.title
        remote = download.remote
        mediaType = download.mediaType
        expectedBytes = download.expectedBytes
        downloadedBytes = download.downloadedBytes
        completedAt = download.completedAt
        isFinished = download.state.isFinished
        if case let .failed(reason, count) = download.state {
            failure = reason
            attempts = count
        } else {
            failure = nil
            attempts = 0
        }
    }

    var download: Download {
        Download(
            id: id,
            sourceID: sourceID,
            title: title,
            remote: remote,
            mediaType: mediaType,
            state: state,
            expectedBytes: expectedBytes,
            downloadedBytes: downloadedBytes,
            completedAt: completedAt
        )
    }

    private var state: Download.State {
        if isFinished { return .finished }
        if let failure { return .failed(reason: failure, attempts: attempts) }
        return .queued
    }
}
