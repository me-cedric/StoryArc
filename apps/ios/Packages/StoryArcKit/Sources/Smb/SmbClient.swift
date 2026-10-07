public import Foundation

public import Formats

internal import Network
internal import StoryArcCore

// The module and its main class share a name, so the class is imported by itself: written
// as `SMBClient.SMBClient` the compiler reads the module and finds no member.
internal import class SMBClient.SMBClient
internal import class SMBClient.Session
internal import struct SMBClient.NTStatus
internal import struct SMBClient.ErrorResponse
internal import enum SMBClient.SMB3Error

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
        try await translating(isHandshake: true) {
            // `login` negotiates and sets up the session in one call. The vendored client
            // offers SMB 2.0.2 to SMB 3.1.1, and seals every later message in an SMB 3
            // transform when the two ends agreed a cipher. ADR-0018.
            try await client.login(
                username: address.isGuest ? nil : address.username,
                password: address.isGuest ? nil : address.password
            )
            // The response, not just the act. A share can demand encryption in the
            // tree-connect response's flags, and a session that cannot encrypt refuses it
            // there. Thrown before `isConnected` is set, so a share this client may not read
            // is never treated as reachable.
            let tree = try await client.connectShare(address.share)
            let session = client.session
            let flags = tree.shareFlags.rawValue
            if let refusal = Self.refusal(forShareFlags: flags, isEncrypting: session.isEncrypting) {
                throw refusal
            }
            isConnected = true

            // What this session negotiated, read off the session itself: the dialect the
            // server chose, and whether every message after the setup is sealed.
            return SmbIdentity(
                dialect: Self.name(of: session.dialect?.rawValue),
                isEncrypted: session.isEncrypting
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
            // The opener rather than the reader, so the source can make a new one. A
            // session does not survive the device sleeping, the Wi-Fi changing, or the
            // server restarting, and `network-share` asks for all three to be invisible.
            let address = self.address
            return SmbSource(length: Int64(stat.size)) {
                let fresh = Held(SMBClient(host: address.host, port: address.port))
                // A reopen that loses its deadline is cancelled. Ending its connection is
                // what makes an abandoned login return, rather than wait for a reply that a
                // silent network never sends.
                return try await withTaskCancellationHandler {
                    try await fresh.value.login(
                        username: address.isGuest ? nil : address.username,
                        password: address.isGuest ? nil : address.password
                    )
                    try await fresh.value.connectShare(address.share)
                    return Held(SmbSession(client: fresh.value, reader: fresh.value.fileReader(path: path)))
                } onCancel: {
                    fresh.value.session.disconnect()
                }
            }
        }
    }

    /// Turns whatever the library threw into one of the four failures the spec names.
    ///
    /// A reader who typed the wrong password and a reader whose NAS is asleep need different
    /// sentences, and one error type does not tell them apart.
    ///
    /// `isHandshake` is set only by ``connect()``. Two of the statuses below mean "no
    /// dialect in common" while the two ends are still agreeing on one, and mean something
    /// far narrower afterwards, so the reading is scoped to the step that can produce it.
    private func translating<T>(
        isHandshake: Bool = false,
        _ body: () async throws -> T
    ) async throws -> T {
        do {
            return try await body()
        } catch let error as SmbError {
            throw error
        } catch let error as ErrorResponse {
            // The library reports a refusal as the server's own NT status, wrapped in the
            // response header it arrived in.
            throw Self.meaning(of: error.header.status, isHandshake: isHandshake)
        } catch let error as NTStatus {
            throw Self.meaning(of: error.rawValue, isHandshake: isHandshake)
        } catch SMB3Error.encryptionRequired {
            throw SmbError.encryptionRequired
        } catch let error as URLError {
            throw error.code == .userAuthenticationRequired
                ? SmbError.authenticationRejected
                : SmbError.hostUnreachable
        } catch let error as NWError {
            throw Self.meaning(of: error)
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain {
            throw Self.meaning(ofPosix: Int32(error.code))
        } catch {
            throw SmbError.unexpected(detail: String(describing: error))
        }
    }

    /// What the network itself said, read out of `NWError` rather than a status this
    /// connection never reached far enough to receive.
    ///
    /// SMBClient's `Connection` throws the raw `NWError` from `.waiting` or `.failed` (see
    /// its `Connection.swift`), and every one of the cases below bridges to
    /// `NSPOSIXErrorDomain` or `"Network.NWError"` before it ever reaches a `catch` clause
    /// that can read it as a POSIX code, which is why this reads `NWError` directly instead.
    static func meaning(of error: NWError) -> SmbError {
        switch error {
        case .dns:
            .hostUnreachable
        case let .posix(code):
            meaning(ofPosix: code.rawValue)
        default:
            .unexpected(detail: String(describing: error))
        }
    }

    /// A POSIX errno, read the same way whether it arrived wrapped in an `NWError` or as a
    /// bare `NSError` in `NSPOSIXErrorDomain`.
    static func meaning(ofPosix code: Int32) -> SmbError {
        switch code {
        case POSIXErrorCode.EPERM.rawValue:
            // The Local Network permission is off: the connect never left the device, and
            // that is a setting for the reader to change here, not a server to chase.
            .localNetworkDenied
        case POSIXErrorCode.ECONNREFUSED.rawValue,
            POSIXErrorCode.EHOSTUNREACH.rawValue,
            POSIXErrorCode.ENETUNREACH.rawValue,
            POSIXErrorCode.ETIMEDOUT.rawValue:
            .hostUnreachable
        default:
            .unexpected(detail: "posix \(code)")
        }
    }

    /// The four failures `network-share` names, read out of the server's NT status.
    static func meaning(of status: UInt32, isHandshake: Bool = false) -> SmbError {
        // Two shapes of "no dialect in common", and they do not mean the same thing.
        // STATUS_NOT_SUPPORTED is what MS-SMB2 has *any* server with nothing in common send,
        // including one that requires SMB 3 or later -- newer than this client, not older.
        // The CIFS error-class statuses, whose codes all end in `0002`, are what an SMB 2
        // server has no way to send at all: only a genuine SMB-1-only server answers this
        // way. Read only while the two ends are still agreeing on a dialect, because
        // STATUS_NOT_SUPPORTED means something much narrower afterwards.
        //
        // The SMB 1 sentence says where to turn SMB 2 on. It does not say why SMB 1 is not
        // spoken here -- that is a sentence for the ADR, not for a reader trying to reach
        // their NAS. The "too new" sentence has no setting to name: this client cannot speak
        // a dialect it was never built to offer.
        if isHandshake, status == Self.noDialectInCommon { return .protocolTooNew }
        if isHandshake, Self.cifsErrorClassRefusals.contains(status) { return .protocolUnsupported }
        // ACCESS_DENIED from a server that has agreed a dialect usually means a refused
        // password, but a server with `reject unencrypted access` answers the same way to a
        // client that cannot encrypt. Those two are indistinguishable *from a status*, so
        // the commoner reading wins here. The share-level demand is not read from a status
        // at all: the tree-connect response carries it as a flag, and
        // ``refusal(forShareFlags:isEncrypting:)`` names it. A session-level demand the
        // session cannot meet is the vendored client's own `SMB3Error.encryptionRequired`.
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

    /// What a share's own flags refuse, read out of the tree-connect response.
    ///
    /// One flag matters to this client: `SMB2_SHAREFLAG_ENCRYPT_DATA`. MS-SMB2 has a server
    /// set it to tell the client that this share's traffic must be encrypted, and has the
    /// client fail the operation when it cannot encrypt. A session that seals its messages
    /// meets the demand. One that cannot -- an SMB 2 server, or a guest session with no key --
    /// fails here, where the demand is a fact rather than a guess:
    /// ``meaning(of:isHandshake:)`` sees only `ACCESS_DENIED`, which a refused password
    /// sends too.
    ///
    /// `nil` when the share demands nothing this session cannot give.
    static func refusal(forShareFlags flags: UInt32, isEncrypting: Bool = false) -> SmbError? {
        flags & encryptDataShareFlag == 0 || isEncrypting ? nil : .encryptionRequired
    }

    /// How a dialect revision is written in the sheet and on the detail screen.
    static func name(of revision: UInt16?) -> String {
        switch revision {
        case 0x0202: "SMB 2.0.2"
        case 0x0210: "SMB 2.1"
        case 0x0300: "SMB 3.0"
        case 0x0302: "SMB 3.0.2"
        case 0x0311: "SMB 3.1.1"
        default: "SMB 2"
        }
    }

    /// `SMB2_SHAREFLAG_ENCRYPT_DATA`, from MS-SMB2 2.2.10.
    private static let encryptDataShareFlag: UInt32 = 0x0000_8000

    /// `STATUS_NOT_SUPPORTED`. Either end may be the one with nothing to offer the other, so
    /// this alone never says which -- ``meaning(of:isHandshake:)`` reads it as this client
    /// needing a server that speaks a newer dialect than it does.
    private static let noDialectInCommon: UInt32 = 0xC000_00BB

    /// The CIFS error-class statuses: `STATUS_INVALID_SMB`, `STATUS_SMB_BAD_COMMAND`,
    /// `STATUS_SMB_BAD_TID`, `STATUS_SMB_BAD_UID` and `STATUS_SMB_USE_STANDARD`. An SMB 2
    /// server has no way to send any of these, so only a genuine SMB-1-only server does.
    private static let cifsErrorClassRefusals: Set<UInt32> = [
        0x0001_0002, 0x0016_0002, 0x0005_0002, 0x005B_0002, 0x00FB_0002,
    ]

    /// Whether a share is reachable at all, without keeping the session.
    ///
    /// `network-share` validates before saving, and a caller that only wants a yes or no
    /// should not have to hold a connection open to get one.
    public static func check(_ address: SmbAddress) async throws -> SmbIdentity {
        let client = SmbClient(address: address)
        return try await client.connect()
    }
}
