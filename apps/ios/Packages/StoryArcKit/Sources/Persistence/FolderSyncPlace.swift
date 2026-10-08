public import Foundation
public import StoryArcCore

/// The sync document's place in a folder the reader picked through the system picker.
///
/// `library-sync` task 2.3. The folder is the one ``SyncPlaceStore`` re-opened from its
/// security-scoped bookmark. A folder in iCloud Drive or another provider is written as any
/// folder is, through a file coordinator so the provider sees each read and write: the provider
/// syncs the file, and the app holds no account with it.
///
/// Each call throws when the folder cannot be reached: removed, or the provider refusing. The
/// caller shows the place as unreachable. Android's `FolderSyncPlace` is the same place.
public struct FolderSyncPlace: SyncPlace {
    private let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    public func names() async throws -> [String] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
            .map(\.lastPathComponent)
    }

    public func read(_ name: String) async throws -> SyncFile? {
        let file = try url(of: name)
        return try coordinated(reading: file) { url in
            guard let version = try Self.version(of: url) else { return nil }
            return SyncFile(data: try Data(contentsOf: url), version: version)
        }
    }

    /// Writes the whole file in one step, through a file beside it that then replaces it.
    ///
    /// The check and the write are two steps. The engine reads again at each sync, so a write
    /// from another device between them comes back then, and a provider that keeps both makes a
    /// conflicted copy the engine merges.
    public func write(_ name: String, data: Data, replacing: String?) async throws -> Bool {
        let file = try url(of: name)
        return try coordinated(writing: file) { url in
            guard try Self.version(of: url) == replacing else { return false }
            try data.write(to: url, options: .atomic)
            return true
        }
    }

    public func delete(_ name: String) async throws -> Bool {
        let file = try url(of: name)
        return try coordinated(writing: file) { url in
            if try Self.version(of: url) != nil { try FileManager.default.removeItem(at: url) }
            return try Self.version(of: url) == nil
        }
    }

    /// The file's url, once the folder itself is known to be there. A folder that has gone throws
    /// rather than reading as empty.
    private func url(of name: String) throws -> URL {
        _ = try folder.checkResourceIsReachable()
        return folder.appending(path: name, directoryHint: .notDirectory)
    }

    /// The modification time and the size, or nil when there is no file.
    private static func version(of url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let moment = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(moment)-\(values.fileSize ?? 0)"
    }

    /// Runs `body` inside a coordinated read, and hands back what it returned or threw.
    private func coordinated<T>(reading url: URL, _ body: (URL) throws -> T) throws -> T {
        var coordination: NSError?
        var outcome: Result<T, any Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: url, options: [], error: &coordination
        ) { granted in
            outcome = Result { try body(granted) }
        }
        if let coordination { throw coordination }
        return try outcome.get()
    }

    /// Runs `body` inside a coordinated write, and hands back what it returned or threw.
    private func coordinated<T>(writing url: URL, _ body: (URL) throws -> T) throws -> T {
        var coordination: NSError?
        var outcome: Result<T, any Error> = .failure(CocoaError(.fileWriteUnknown))
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url, options: .forReplacing, error: &coordination
        ) { granted in
            outcome = Result { try body(granted) }
        }
        if let coordination { throw coordination }
        return try outcome.get()
    }
}
