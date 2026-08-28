public import Foundation

public import Formats

// The module and its main class share a name, so the class is imported by itself: written
// as `SMBClient.SMBClient` the compiler reads the module and finds no member.
internal import class SMBClient.SMBClient
internal import class SMBClient.FileReader
internal import struct SMBClient.NTStatus
internal import struct SMBClient.ErrorResponse

/// A share, as StoryArc talks to it.
///
/// Thin on purpose: everything above this line — the ZIP reader, the page decoder, the
/// reader — works against `RandomAccessSource` and learns nothing about SMB. ADR-0010 keeps
/// the client behind this seam so that the choice of library stays a detail.
///
/// An actor because one SMB session is one connection: two reads racing on the same socket
/// interleave their responses, and the library does not serialise them for us.
public actor SmbClient {
    private let address: SmbAddress
    /// `nonisolated(unsafe)` because the library's types are plain classes and Swift cannot
    /// see that this actor is what serialises every use of them. Every method below is
    /// actor-isolated, so only one call touches the session at a time -- which is the reason
    /// this is an actor rather than a struct.
    nonisolated(unsafe) private let client: SMBClient
    private var isConnected = false

    public init(address: SmbAddress) {
        self.address = address
        client = SMBClient(host: address.host, port: address.port)
    }

    /// Connects, and reports what the far end turned out to be.
    ///
    /// `network-share` wants the connection validated "before saving", with the specific
    /// failure named. Reaching the share's root is the cheapest thing that exercises all of
    /// host, share and credentials at once.
    @discardableResult
    public func connect() async throws -> SmbIdentity {
        try await translating {
            // `login` negotiates and sets up the session in one call. Reaching into
            // `client.session` to learn the exact dialect would send a non-Sendable value
            // out of this actor, so the dialect is reported as the range this client offers
            // rather than the one it landed on. Android reports the exact figure.
            try await client.login(
                username: address.isGuest ? nil : address.username,
                password: address.isGuest ? nil : address.password
            )
            try await client.connectShare(address.share)
            isConnected = true

            return SmbIdentity(
                dialect: Self.offeredDialects,
                // This client implements SMB 2 dialects and no transport encryption, so
                // saying otherwise would be a claim the connection cannot back. Android
                // negotiates SMB 3 and reports what it got. ADR-0010 records the split.
                isEncrypted: false
            )
        }
    }

    /// What is in one folder of the share, folders first, in natural order.
    public func list(_ path: String = "") async throws -> [SmbEntry] {
        if !isConnected { _ = try await connect() }
        return try await translating {
            try await client.listDirectory(path: path)
                .filter { $0.name != "." && $0.name != ".." }
                .map { each in
                    SmbEntry(
                        name: each.name,
                        path: [path, each.name]
                            .filter { !$0.isEmpty }
                            .joined(separator: "/"),
                        isDirectory: each.isDirectory,
                        length: each.isDirectory ? 0 : Int64(each.size)
                    )
                }
                .sorted { left, right in
                    left.isDirectory == right.isDirectory
                        ? left.name.localizedStandardCompare(right.name) == .orderedAscending
                        : left.isDirectory
                }
        }
    }

    /// One file on the share, read where the reader needs it rather than whole.
    public func open(_ path: String) async throws -> any RandomAccessSource {
        if !isConnected { _ = try await connect() }
        return try await translating {
            // The length comes from the directory entry rather than from the reader:
            // `FileReader.fileSize` is a nonisolated async property, and reaching it would
            // send a non-Sendable reader out of this actor.
            let stat = try await client.fileStat(path: path)
            return SmbSource(
                reader: Held(try await client.fileReader(path: path)),
                length: Int64(stat.size)
            )
        }
    }

    /// Turns whatever the library threw into one of the four failures the spec names.
    ///
    /// A reader who typed the wrong password and a reader whose NAS is asleep need different
    /// sentences, and one error type does not tell them apart.
    private func translating<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as SmbError {
            throw error
        } catch let error as ErrorResponse {
            // The library reports a refusal as the server's own NT status, wrapped in the
            // response header it arrived in.
            throw Self.meaning(of: error.header.status)
        } catch let error as NTStatus {
            throw Self.meaning(of: error.rawValue)
        } catch let error as URLError {
            throw error.code == .userAuthenticationRequired
                ? SmbError.authenticationRejected
                : SmbError.hostUnreachable
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain {
            throw SmbError.hostUnreachable
        } catch {
            throw SmbError.unexpected(detail: String(describing: error))
        }
    }

    /// The four failures `network-share` names, read out of the server's NT status.
    private static func meaning(of status: UInt32) -> SmbError {
        switch status {
        case 0xC000_006D, 0xC000_006A, 0xC000_0022: return .authenticationRejected
        // BAD_NETWORK_NAME and OBJECT_PATH_NOT_FOUND only. OBJECT_NAME_NOT_FOUND means a
        // missing *file*, which is not a missing share and must not be reported as one --
        // it sent a reader looking at their server settings for a typo in a filename.
        case 0xC000_00CC, 0xC000_003A: return .shareNotFound
        case 0xC000_0203, 0xC000_0205: return .hostUnreachable
        default: return .unexpected(detail: NTStatus(status).description)
        }
    }

    /// What this client offers. The library negotiates SMB 2.0.2 and 2.1 and no more.
    private static let offeredDialects = "SMB 2"

    /// Whether a share is reachable at all, without keeping the session.
    ///
    /// `network-share` validates before saving, and a caller that only wants a yes or no
    /// should not have to hold a connection open to get one.
    public static func check(_ address: SmbAddress) async throws -> SmbIdentity {
        let client = SmbClient(address: address)
        return try await client.connect()
    }
}

/// A file on a share, read at an offset.
///
/// The third implementation ADR-0008 planned for. SMB2's `READ` takes an offset and a length
/// as a first-class operation, so this is the interface it was already shaped like.
private actor SmbSource: RandomAccessSource {
    /// `nonisolated(unsafe)` for the reason the client's own is: the library's reader is a
    /// plain class, and this actor is what serialises every use of it.
    nonisolated(unsafe) private let reader: FileReader
    nonisolated let length: Int64

    init(reader: Held<FileReader>, length: Int64) {
        self.reader = reader.value
        self.length = length
    }

    func read(offset: Int64, count: Int) async throws -> Data {
        let available = max(0, length - offset)
        let toRead = Int(min(Int64(count), available))
        guard toRead > 0 else { return Data() }
        return try await reader.read(offset: UInt64(offset), length: UInt32(toRead))
    }

    func close() async {
        try? await reader.close()
    }
}

/// A non-Sendable value carried across an actor boundary.
///
/// `FileReader` is a plain class, and the actor above is what serialises every use of it —
/// which is the reason that actor exists. Swift cannot see that from the type, so this says
/// it out loud in one place rather than scattering `nonisolated(unsafe)` through the file.
private struct Held<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
