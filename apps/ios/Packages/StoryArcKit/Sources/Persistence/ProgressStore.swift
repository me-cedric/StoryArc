public import Foundation

public import StoryArcCore

internal import SwiftData

/// One reading position, as SwiftData stores it.
///
/// The identity fields are flattened rather than stored as one blob, because
/// ADR-0006 requires looking a record up by *any* of them: a file read from a
/// folder and the same file served by Kavita have to resolve to one record, and
/// that only works if each component is queryable on its own.
@Model
final class StoredProgress {
    /// The server's identifier, when the publication came from a source with one.
    var serverKey: String?
    /// A digest of the file's size plus its first and last bytes.
    var contentDigest: String?
    /// Last resort, when neither of the above is obtainable.
    var normalizedPath: String?

    /// The position, encoded. `ReadingPosition` is an enum with associated
    /// values; storing it as JSON keeps the domain type free of persistence
    /// annotations, which is what lets `StoryArcCore` stay free of SwiftData.
    var positionData: Data
    var isFinished: Bool
    var updatedAt: Date
    var syncedPositionData: Data?

    init(
        serverKey: String?,
        contentDigest: String?,
        normalizedPath: String?,
        positionData: Data,
        isFinished: Bool,
        updatedAt: Date,
        syncedPositionData: Data?
    ) {
        self.serverKey = serverKey
        self.contentDigest = contentDigest
        self.normalizedPath = normalizedPath
        self.positionData = positionData
        self.isFinished = isFinished
        self.updatedAt = updatedAt
        self.syncedPositionData = syncedPositionData
    }
}

/// Reading positions, stored locally and authoritative.
///
/// ADR-0006: "Progress is written locally first, always, for every publication —
/// including ones from sources that cannot store progress. Remote sync is a
/// projection of that store outward, never a prerequisite for it." So this has no
/// idea a server exists, and the app works fully with none configured.
///
/// An actor because the reader writes to it on every page turn while the library
/// reads from it to draw progress rings, and SwiftData's context is not
/// thread-safe.
public actor ProgressStore {
    private let container: ModelContainer
    private let context: ModelContext

    /// Opens the store on disk.
    ///
    /// The database is small and worth restoring, so it is *not* excluded from
    /// backup — ADR-0006 splits it from downloads for exactly that reason.
    public init(url: URL? = nil) throws {
        let configuration = if let url {
            ModelConfiguration(url: url)
        } else {
            ModelConfiguration()
        }
        self.container = try ModelContainer(
            for: StoredProgress.self,
            configurations: configuration
        )
        self.context = ModelContext(container)
    }

    /// An in-memory store, for tests and previews.
    public static func inMemory() throws -> ProgressStore {
        try ProgressStore(configuration: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private init(configuration: ModelConfiguration) throws {
        self.container = try ModelContainer(
            for: StoredProgress.self,
            configurations: configuration
        )
        self.context = ModelContext(container)
    }

    /// The progress recorded for a publication, if any.
    ///
    /// Matches on *any* identity component, in ADR-0006's order of preference. A
    /// file that gains a server id later still finds the record written against
    /// its digest.
    public func progress(for identity: PublicationIdentity) throws -> ReadingProgress? {
        try existing(for: identity).map(Self.domain)
    }

    /// Records a position, replacing whatever was there.
    ///
    /// Last write wins *locally* — this is one device, and the interesting
    /// conflict rules apply between devices, not within one. `ProgressMerge` is
    /// where those live.
    public func save(_ progress: ReadingProgress) throws {
        let encoder = JSONEncoder()
        let position = try encoder.encode(progress.position)
        let synced = try progress.syncedPosition.map(encoder.encode)

        if let record = try existing(for: progress.identity) {
            record.positionData = position
            // Finished is sticky. ADR-0006: unmarking a finished publication is a
            // deliberate act, and losing it to a routine save is not something a
            // user would ever want.
            record.isFinished = record.isFinished || progress.isFinished
            record.updatedAt = progress.updatedAt
            record.syncedPositionData = synced
            // Identity components fill in as they become known, so a record
            // written against a path can later be found by its digest.
            record.serverKey = record.serverKey ?? Self.serverKey(progress.identity)
            record.contentDigest = record.contentDigest ?? progress.identity.contentDigest
            record.normalizedPath = record.normalizedPath ?? progress.identity.normalizedPath
        } else {
            context.insert(
                StoredProgress(
                    serverKey: Self.serverKey(progress.identity),
                    contentDigest: progress.identity.contentDigest,
                    normalizedPath: progress.identity.normalizedPath,
                    positionData: position,
                    isFinished: progress.isFinished,
                    updatedAt: progress.updatedAt,
                    syncedPositionData: synced
                )
            )
        }
        try context.save()
    }

    /// Everything recorded, most recently read first.
    ///
    /// What `library-browsing`'s "Continue reading" row is built from.
    public func recent(limit: Int = 50) throws -> [ReadingProgress] {
        var descriptor = FetchDescriptor<StoredProgress>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).map(Self.domain)
    }

    /// Forgets one publication's position. A deliberate act, per ADR-0006.
    public func forget(_ identity: PublicationIdentity) throws {
        guard let record = try existing(for: identity) else { return }
        context.delete(record)
        try context.save()
    }

    /// Forgets every recorded position.
    ///
    /// `settings-and-about` requires reading history to be individually clearable. A reader
    /// who clears this is choosing to lose their places, which is why the confirmation names
    /// it rather than calling it "data".
    ///
    /// Deleted through the context rather than by removing the file: dropping the store from
    /// under an open container is how a later read finds a corrupt file instead of an empty
    /// one.
    public func clear() throws {
        try context.delete(model: StoredProgress.self)
        try context.save()
    }

    /// Bytes the store is holding, journals included.
    ///
    /// `settings-and-about` asks each clearable thing to state "how much space it frees",
    /// and a number is the point: "clear history" with nothing behind it asks a reader to
    /// guess whether it is worth doing.
    public func sizeOnDisk() -> Int64 {
        guard let url = container.configurations.first?.url else { return 0 }
        let directory = url.deletingLastPathComponent()
        let stem = url.lastPathComponent
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return files
            .filter { $0.lastPathComponent.hasPrefix(stem) }
            .reduce(into: Int64(0)) { total, file in
                total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
    }

    // MARK: - Private

    private func existing(for identity: PublicationIdentity) throws -> StoredProgress? {
        // Queried component by component in preference order rather than with one
        // compound predicate: SwiftData cannot express "any of these three match"
        // over optionals cleanly, and three cheap indexed lookups on a small table
        // are not worth outsmarting.
        if let key = Self.serverKey(identity) {
            let found = try context.fetch(
                FetchDescriptor<StoredProgress>(predicate: #Predicate { $0.serverKey == key })
            )
            if let first = found.first { return first }
        }
        if let digest = identity.contentDigest {
            let found = try context.fetch(
                FetchDescriptor<StoredProgress>(predicate: #Predicate { $0.contentDigest == digest })
            )
            if let first = found.first { return first }
        }
        if let path = identity.normalizedPath {
            let found = try context.fetch(
                FetchDescriptor<StoredProgress>(predicate: #Predicate { $0.normalizedPath == path })
            )
            if let first = found.first { return first }
        }
        return nil
    }

    /// A server identifier flattened to one string, so it can be one column.
    private static func serverKey(_ identity: PublicationIdentity) -> String? {
        identity.serverIdentifier.map { "\($0.sourceID.uuidString):\($0.remoteID)" }
    }

    private static func domain(_ record: StoredProgress) -> ReadingProgress {
        let decoder = JSONDecoder()
        let position = (try? decoder.decode(ReadingPosition.self, from: record.positionData))
            ?? .page(index: 0, of: 1)
        let synced = record.syncedPositionData
            .flatMap { try? decoder.decode(ReadingPosition.self, from: $0) }

        return ReadingProgress(
            identity: PublicationIdentity(
                serverIdentifier: nil,
                contentDigest: record.contentDigest,
                normalizedPath: record.normalizedPath
            ),
            position: position,
            isFinished: record.isFinished,
            updatedAt: record.updatedAt,
            syncedPosition: synced
        )
    }
}
