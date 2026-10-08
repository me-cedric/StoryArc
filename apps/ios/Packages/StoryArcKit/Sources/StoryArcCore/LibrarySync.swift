public import Foundation

/// A file in a sync place, with the version the place gave it when it was read.
public struct SyncFile: Sendable, Equatable {
    public let data: Data
    public let version: String

    public init(data: Data, version: String) {
        self.data = data
        self.version = version
    }
}

/// Where the sync document lives: a share the reader added, or a folder they picked.
///
/// `library-sync` tasks 2.2 and 2.3 fill this: an SMB write and a picked folder. The engine
/// needs no more than these four calls. Each call throws when the place cannot be reached, and
/// the caller shows the place as unreachable, not as an error.
public protocol SyncPlace: Sendable {
    /// The names of the files in the place, for the conflicted copies a provider leaves.
    func names() async throws -> [String]

    /// The file, or nil when there is none.
    func read(_ name: String) async throws -> SyncFile?

    /// Writes `data` only when the file is still at version `replacing`, or still absent when
    /// `replacing` is nil. A place with an atomic replace uses it.
    ///
    /// - Returns: false when the file changed since that read, with nothing written.
    func write(_ name: String, data: Data, replacing: String?) async throws -> Bool

    /// - Returns: false when the file is still there.
    func delete(_ name: String) async throws -> Bool
}

/// What one sync did.
public enum LibrarySyncOutcome: Sendable, Equatable {
    /// The device as the sync leaves it: the caller writes the merged snapshot to the stores.
    case synced(LibrarySyncResult)

    /// The document in the place cannot be read, by name: newer than this app, or not a
    /// library. Nothing was written, so a newer app's document is never overwritten.
    case refused(LibraryDocumentFailure)

    /// The document changed under every attempt. Nothing was written; the next sync tries
    /// again.
    case busy
}

/// A sync that wrote.
public struct LibrarySyncResult: Sendable, Equatable {
    public var merged: LibrarySyncMerged

    /// Conflicted copies that could not be read, by name. They stay in the place.
    public var skippedCopies: [String]

    /// Conflicted copies merged and not deleted, as `name@version`. The caller keeps this set
    /// and hands it to the next sync, so no copy is merged twice.
    public var mergedCopies: Set<String>

    /// The conflicted copies this sync merged, by name, so the reader can be told.
    public var copiesMergedNow: [String]
}

/// Read, merge, write: one sync of the library document.
///
/// `library-sync` task 3.1 / *Two devices write at once*: a write is never a blind overwrite.
/// The engine reads the document, merges it and any conflicted copy into this device, and
/// writes the result only when the document is still the one it read. When another device
/// wrote in between, it reads again and merges again, from this device's own state.
///
/// Android's `LibrarySync` is the same engine.
public struct LibrarySync: Sendable {

    /// The document's name in the place. Android writes the same name.
    public static let fileName = "StoryArc Library.json"
    public static let attempts = 3

    private let place: any SyncPlace
    private let device: String
    private let appVersion: String
    private let fileName: String
    private let attempts: Int

    /// - Parameter device: this install's id. See ``LibrarySyncState``.
    public init(
        place: any SyncPlace,
        device: String,
        appVersion: String,
        fileName: String = LibrarySync.fileName,
        attempts: Int = LibrarySync.attempts
    ) {
        self.place = place
        self.device = device
        self.appVersion = appVersion
        self.fileName = fileName
        self.attempts = attempts
    }

    /// Whether `name` is a copy a file provider made of `original` when two devices wrote at
    /// once.
    ///
    /// Providers name one differently: `name 2.json` on iCloud Drive, `name (1).json` on Google
    /// Drive, `name (… conflicted copy …).json` on Dropbox, `name-DEVICE.json` on OneDrive. Each
    /// is the same name and extension with a suffix between them.
    public static func isConflictedCopy(
        _ name: String,
        of original: String = LibrarySync.fileName
    ) -> Bool {
        let base = original.split(separator: ".", omittingEmptySubsequences: false).dropLast().joined(separator: ".")
        let suffixes = original.dropFirst(base.count)
        guard name != original, name.hasPrefix(base), name.hasSuffix(suffixes),
              name.count > base.count + suffixes.count
        else { return false }
        let suffix = String(name.dropFirst(base.count).dropLast(suffixes.count))
        let trimmed = suffix.drop { $0.isWhitespace }
        let digits = !trimmed.isEmpty && trimmed.allSatisfy { ("0"..."9").contains($0) }
        if trimmed.count < suffix.count, digits { return true }
        if trimmed.hasPrefix("("), trimmed.hasSuffix(")"), trimmed.count > 2 { return true }
        return suffix.hasPrefix("-") && suffix.count > 1
    }

    private struct Copy {
        let name: String
        let key: String
        let document: LibraryDocument
    }

    /// - Parameter mergedCopies: what the last sync returned as
    ///   ``LibrarySyncResult/mergedCopies``.
    public func sync(
        _ local: LibrarySnapshot,
        at moment: Date,
        mergedCopies: Set<String> = []
    ) async throws -> LibrarySyncOutcome {
        for _ in 0..<attempts {
            let file = try await place.read(fileName)
            var document: LibraryDocument?
            if let file {
                do {
                    document = try LibraryDocumentCoder.decode(file.data)
                } catch let failure as LibraryDocumentFailure {
                    return .refused(failure)
                }
            }
            var skipped: [String] = []
            let copies = try await self.copies(mergedCopies, skipped: &skipped)

            // With no document yet, an empty one: the merge still settles each position this
            // device is about to write.
            let first = document ?? LibraryDocument(
                appVersion: appVersion, writtenBy: "", writtenAt: moment, library: LibraryBody()
            )
            var merged = LibrarySyncMerged(snapshot: local)
            for incoming in [first] + copies.map(\.document) {
                let next = LibrarySyncMerge.merging(incoming, into: merged.snapshot, device: device)
                merged = LibrarySyncMerged(
                    snapshot: next.snapshot,
                    conflicts: merged.conflicts + next.conflicts,
                    certificatePinsAdded: merged.certificatePinsAdded + next.certificatePinsAdded,
                    sourcesNeedingSignIn: next.sourcesNeedingSignIn
                )
            }

            let written = LibraryExport.syncDocument(
                merged.snapshot, appVersion: appVersion, writtenAt: moment, device: device, previous: document
            )
            guard try await place.write(fileName, data: LibraryDocumentCoder.encode(written), replacing: file?.version)
            else { continue }

            var undeleted: Set<String> = []
            for copy in copies {
                let deleted = try await place.delete(copy.name)
                undeleted.formUnion(deleted ? [] : [copy.key])
            }
            return .synced(LibrarySyncResult(
                merged: merged,
                skippedCopies: skipped,
                mergedCopies: mergedCopies.union(undeleted),
                copiesMergedNow: copies.map(\.name)
            ))
        }
        return .busy
    }

    /// Every conflicted copy not merged before, read; one that cannot be read is named.
    private func copies(_ mergedCopies: Set<String>, skipped: inout [String]) async throws -> [Copy] {
        var copies: [Copy] = []
        for name in try await place.names().filter({ Self.isConflictedCopy($0, of: fileName) }).sorted() {
            guard let file = try await place.read(name) else { continue }
            let key = "\(name)@\(file.version)"
            guard !mergedCopies.contains(key) else { continue }
            guard let document = try? LibraryDocumentCoder.decode(file.data) else {
                skipped.append(name)
                continue
            }
            copies.append(Copy(name: name, key: key, document: document))
        }
        return copies
    }
}
