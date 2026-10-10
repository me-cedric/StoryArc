internal import Foundation

internal import StoryArcCore

internal import SwiftData

/// Records written before a reinstall, found again (task 26.4).
///
/// A reinstall gives the app a new data container, so a publication in the app's own folder
/// gets a new path. A record keyed only by the old path is then not found, and a folder
/// audiobook had no other key. These helpers find such a record by the place inside the
/// container, and fold every copy of one publication into one record.
extension ProgressStore {

    /// Records with no digest whose path names the same place inside an app container,
    /// newest first.
    ///
    /// Only records with no digest: a record with one is found by it, and the library asks
    /// this for every publication it draws.
    static func containerTwins(
        of identity: PublicationIdentity,
        in context: ModelContext
    ) throws -> [StoredProgress] {
        guard identity.normalizedPath.flatMap(PublicationIdentity.containerRelativePath) != nil else {
            return []
        }
        return try context.fetch(
            FetchDescriptor<StoredProgress>(
                predicate: #Predicate { $0.contentDigest == nil },
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        ).filter { PublicationIdentity(normalizedPath: $0.normalizedPath).sharesContainerPath(with: identity) }
    }

    /// Folds every record of this publication into the newest one, and files it under the
    /// current path.
    ///
    /// - Returns: the record that stays, and whether anything changed.
    static func collapse(
        _ record: StoredProgress,
        onto identity: PublicationIdentity,
        in context: ModelContext
    ) throws -> (keeper: StoredProgress, changed: Bool) {
        // Fetched by key, not the whole table: the scan links every publication on each launch.
        var twins = try containerTwins(of: identity, in: context) + [record]
        if let digest = identity.contentDigest {
            twins += try context.fetch(
                FetchDescriptor<StoredProgress>(predicate: #Predicate { $0.contentDigest == digest })
            )
        }
        var seen = Set<ObjectIdentifier>()
        twins = twins.filter { seen.insert(ObjectIdentifier($0)).inserted }.sorted { $0.updatedAt > $1.updatedAt }
        let keeper = twins.first ?? record
        var changed = false
        for twin in twins where twin !== keeper {
            keeper.serverKey = keeper.serverKey ?? twin.serverKey
            keeper.contentDigest = keeper.contentDigest ?? twin.contentDigest
            context.delete(twin)
            changed = true
        }
        if let path = identity.normalizedPath, keeper.normalizedPath != path,
           PublicationIdentity(normalizedPath: keeper.normalizedPath).sharesContainerPath(with: identity) {
            keeper.normalizedPath = path
            changed = true
        }
        return (keeper, changed)
    }
}
