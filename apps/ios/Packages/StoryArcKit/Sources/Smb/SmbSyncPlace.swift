public import Foundation
public import StoryArcCore

/// The sync document's place on a share the reader already added.
///
/// `library-sync` task 2.2. The files live in the folder the source opens at
/// (``SmbAddress/path``), with the source's own credential. One session serves the whole sync.
/// Each call throws ``SmbError`` as the share's other calls do, so an unreachable share is
/// grey, not red. Android's `SmbSyncPlace` is the same place.
public struct SmbSyncPlace: SyncPlace {
    private let address: SmbAddress
    private let client: SmbClient

    public init(address: SmbAddress) {
        self.address = address
        client = SmbClient(address: address)
    }

    public func names() async throws -> [String] {
        try await client.list(address.path).filter { !$0.isDirectory }.map(\.name)
    }

    public func read(_ name: String) async throws -> SyncFile? {
        try await client.readFile(path(of: name)).map { SyncFile(data: $0.data, version: $0.version) }
    }

    public func write(_ name: String, data: Data, replacing: String?) async throws -> Bool {
        try await client.writeFile(path(of: name), data: data, replacing: replacing)
    }

    public func delete(_ name: String) async throws -> Bool {
        try await client.deleteFile(path(of: name))
    }

    private func path(of name: String) -> String {
        [address.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), name]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
    }
}
