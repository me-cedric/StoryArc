public import Foundation

public import StoryArcCore

/// The part of the progress store an import writes through and, on a failure, undoes through.
///
/// A seam so a test can hand ``LibraryArchive`` a ledger that fails on the Nth write. The
/// SwiftData store is the only production conformer.
public protocol ProgressLedger: Sendable {
    func recent(limit: Int) async throws -> [ReadingProgress]
    func save(_ progress: ReadingProgress) async throws
    func mark(_ identity: PublicationIdentity, finished: Bool, at: Date) async throws
    func forget(_ identity: PublicationIdentity) async throws
}

extension ProgressStore: ProgressLedger {}
