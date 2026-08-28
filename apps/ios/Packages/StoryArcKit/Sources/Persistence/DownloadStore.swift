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
    public func location(for id: String, extension ext: String) -> URL {
        directory
            .appending(path: id.replacing(#/[^A-Za-z0-9._-]/#, with: "-"))
            .appendingPathExtension(ext)
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
            delete(location(for: id, extension: Self.extension(for: download.mediaType)))
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
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return files.reduce(0) { total, file in
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
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
