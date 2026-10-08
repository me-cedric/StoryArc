public import Foundation

internal import struct SMBClient.ErrorResponse
internal import struct SMBClient.FileStat

/// A whole file read from a share, with the version it had when it was read.
public struct SmbFileContent: Sendable, Equatable {
    public let data: Data
    public let version: String
}

/// Whole small files: read, write in one step, delete.
///
/// `library-sync` task 2.2: the sync document is read whole, merged, and written back. The same
/// credential, the same session and the same failures as a read, so an unreachable share is
/// grey, not red. Android's `SmbClient.readFile`, `writeFile` and `deleteFile` are the same
/// three calls.
extension SmbClient {

    /// The file and its version, or nil when there is none.
    public func readFile(_ path: String) async throws -> SmbFileContent? {
        try await connectOnce()
        return try await translating {
            guard let stat = try await stat(path) else { return nil }
            let data = try await client.download(path: path)
            return SmbFileContent(data: data, version: Self.version(of: stat))
        }
    }

    /// Writes `data` to `path` only when the file is still at version `replacing`, or still
    /// absent when `replacing` is nil.
    ///
    /// The bytes go to a new file beside the target first. A rename with replace then puts that
    /// file in place in one server step, so a reader of the share never sees half a document.
    /// The check and the rename are two steps: a write from another device between them is
    /// replaced. The sync engine reads again at each sync, so it merges that write back then.
    ///
    /// - Returns: false when the file changed since that read, with nothing written.
    public func writeFile(_ path: String, data: Data, replacing: String?) async throws -> Bool {
        try await connectOnce()
        return try await translating {
            let current = try await stat(path).map(Self.version(of:))
            guard current == replacing else { return false }
            let parts = path.split(separator: "/").map(String.init)
            let temporary = (parts.dropLast() + [".\(parts.last ?? "file").\(UUID().uuidString).tmp"])
                .joined(separator: "/")
            try await client.upload(content: data, path: temporary)
            do {
                try await client.move(from: temporary, to: path, replacing: true)
            } catch {
                try? await client.deleteFile(path: temporary)
                throw error
            }
            return true
        }
    }

    /// Removes one file.
    ///
    /// - Returns: false when it is still there.
    public func deleteFile(_ path: String) async throws -> Bool {
        try await connectOnce()
        return try await translating {
            if try await stat(path) != nil { try await client.deleteFile(path: path) }
            return try await stat(path) == nil
        }
    }

    /// The file's facts, or nil when the server says there is no such file.
    private func stat(_ path: String) async throws -> FileStat? {
        do {
            return try await client.fileStat(path: path)
        } catch let error as ErrorResponse where error.header.status == Self.objectNameNotFound {
            return nil
        }
    }

    /// `STATUS_OBJECT_NAME_NOT_FOUND`, from MS-ERREF 2.3.1.
    private static let objectNameNotFound: UInt32 = 0xC000_0034

    /// The last write time and the size: what changes when any client writes the file.
    private static func version(of stat: FileStat) -> String {
        "\(stat.lastWriteTime.timeIntervalSince1970)-\(stat.size)"
    }
}
