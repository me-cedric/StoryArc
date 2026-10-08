import Foundation
@testable import StoryArcCore

/// A sync place in memory: files by name, each with a version that moves on every write.
///
/// `beforeWrite` runs once before the next write, so a test can let another device write in
/// between a read and a write. `undeletable` names files whose delete fails. Android's
/// `MemoryPlace` is the same place.
final class MemoryPlace: SyncPlace, @unchecked Sendable {
    var files: [String: SyncFile] = [:]
    var beforeWrite: (() async throws -> Void)?
    var undeletable: Set<String> = []
    var writes = 0
    private var version = 0

    func put(_ name: String, _ data: Data) {
        version += 1
        files[name] = SyncFile(data: data, version: "v\(version)")
    }

    func document() throws -> LibraryDocument {
        try LibraryDocumentCoder.decode(files[LibrarySync.fileName]?.data ?? Data())
    }

    func names() async throws -> [String] { Array(files.keys) }

    func read(_ name: String) async throws -> SyncFile? { files[name] }

    func write(_ name: String, data: Data, replacing: String?) async throws -> Bool {
        if let hook = beforeWrite {
            beforeWrite = nil
            try await hook()
        }
        guard files[name]?.version == replacing else { return false }
        writes += 1
        put(name, data)
        return true
    }

    func delete(_ name: String) async throws -> Bool {
        guard !undeletable.contains(name) else { return false }
        return files.removeValue(forKey: name) != nil
    }
}

/// One device: its library in memory, as its stores would hold it after each sync.
final class SyncDevice: @unchecked Sendable {
    let id: String
    var library: LibrarySnapshot
    var mergedCopies: Set<String> = []
    var conflicts: [ProgressPull.Conflict] = []

    init(_ id: String, _ library: LibrarySnapshot = LibrarySnapshot()) {
        self.id = id
        self.library = library
    }

    @discardableResult
    func sync(_ place: MemoryPlace, at second: TimeInterval) async throws -> LibrarySyncOutcome {
        let outcome = try await LibrarySync(place: place, device: id, appVersion: "1.0")
            .sync(library, at: moment(second), mergedCopies: mergedCopies)
        if case let .synced(result) = outcome {
            library = result.merged.snapshot
            mergedCopies = result.mergedCopies
            conflicts += result.merged.conflicts
        }
        return outcome
    }

    func position(_ identity: PublicationIdentity) -> ReadingProgress? {
        library.progress.first { $0.identity.matches(identity) }
    }

    /// Reads to `page` of 100 at `second`, the way the reader's save writes a position.
    func read(_ identity: PublicationIdentity, page: Int, at second: TimeInterval) {
        var record = position(identity)
            ?? ReadingProgress(identity: identity, position: .page(index: page, of: 100), updatedAt: moment(second))
        record.position = .page(index: page, of: 100)
        record.updatedAt = moment(second)
        library.progress = library.progress.filter { !$0.identity.matches(identity) } + [record]
    }
}

/// Moments a test reads easily: `second` seconds after a fixed day.
func moment(_ second: TimeInterval) -> Date {
    Date(timeIntervalSince1970: 1_767_225_600 + second)
}
