public import Foundation

public import Formats

internal import Network
internal import StoryArcCore

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
        try await translating(isHandshake: true) {
            // `login` negotiates and sets up the session in one call. Reaching into
            // `client.session` to learn the exact dialect would send a non-Sendable value
            // out of this actor, so the dialect is reported as the range this client offers
            // rather than the one it landed on. Android reports the exact figure.
            try await client.login(
                username: address.isGuest ? nil : address.username,
                password: address.isGuest ? nil : address.password
            )
            // The response, not just the act. `network-share` wants the specific failure
            // named, and the tree-connect response is the one place this connection learns
            // that the share demands encryption it cannot give. Thrown before `isConnected`
            // is set, so a share this client may not read is never treated as reachable.
            let tree = try await client.connectShare(address.share)
            if let refusal = Self.refusal(forShareFlags: tree.shareFlags.rawValue) {
                throw refusal
            }
            isConnected = true

            return SmbIdentity(
                dialect: Self.offeredDialects,
                // ``StoryArcCore/ShareTransport`` holds the answer and the evidence for it,
                // so that the add-share sheet and the source detail screen read one value.
                // SMBClient 0.3.1 offers SMB 2.0.2 and SMB 2.1 only, and SMB 3 is where
                // transport encryption starts. ADR-0010 records the split with Android.
                isEncrypted: ShareTransport.isEncrypted
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
                let fresh = SMBClient(host: address.host, port: address.port)
                try await fresh.login(
                    username: address.isGuest ? nil : address.username,
                    password: address.isGuest ? nil : address.password
                )
                try await fresh.connectShare(address.share)
                return Held(try await fresh.fileReader(path: path))
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
        // ``refusal(forShareFlags:)`` names it. Android reads the same demand out of jcifs'
        // own message.
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
    /// client fail the operation when it cannot encrypt. This client cannot, so it fails it
    /// here, where the demand is a fact rather than a guess -- ``meaning(of:isHandshake:)``
    /// sees only `ACCESS_DENIED`, which a refused password sends too.
    ///
    /// `nil` when the share demands nothing this client cannot give.
    static func refusal(forShareFlags flags: UInt32) -> SmbError? {
        flags & encryptDataShareFlag == 0 ? nil : .encryptionRequired
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
    nonisolated(unsafe) private var reader: FileReader?
    private let opener: @Sendable () async throws -> Held<FileReader>
    nonisolated let length: Int64

    /// Watches the path underneath this session, so a change drops it before the next read
    /// finds out the hard way.
    ///
    /// `network-share`'s *Network changes*: nothing used to watch for one at all — a stale
    /// session was dropped only after a read against it failed, which after this file's own
    /// deadlines still means up to 20 s (or 10 s, for a reopen) of a wait this source already
    /// knows is doomed the moment the path moves.
    private let pathMonitor = NWPathMonitor()

    /// `NWPathMonitor` calls its handler once immediately with the path already in effect,
    /// which is not a change — only a report after this one drops the session.
    private var hasSeenFirstPath = false

    init(length: Int64, opener: @escaping @Sendable () async throws -> Held<FileReader>) {
        self.length = length
        self.opener = opener
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            guard let self else { return }
            Task { await self.noteNetworkChange() }
        }
        pathMonitor.start(queue: .global(qos: .utility))
    }

    deinit {
        pathMonitor.cancel()
    }

    private func noteNetworkChange() async {
        guard hasSeenFirstPath else {
            hasSeenFirstPath = true
            return
        }
        await close()
    }

    /// Reads, and opens a new session once if the old one has gone.
    ///
    /// `network-share` requires the app to "re-establish the session transparently on the
    /// next read" after the device sleeps, and to reconnect in the background when the
    /// connection drops. Both are the same act from here: the reader is stale, so make
    /// another and ask again. Once, not in a loop — a share that is genuinely gone should
    /// say so rather than hang.
    func read(offset: Int64, count: Int) async throws -> Data {
        let available = max(0, length - offset)
        let toRead = Int(min(Int64(count), available))
        guard toRead > 0 else { return Data() }

        do {
            let bytes = try await readOnce(offset: offset, count: toRead)
            SmbReachability.noteSuccess()
            return bytes
        } catch {
            do {
                reader = nil
                let bytes = try await readOnce(offset: offset, count: toRead)
                SmbReachability.noteSuccess()
                return bytes
            } catch {
                SmbReachability.noteFailure()
                throw SmbError.hostUnreachable
            }
        }
    }

    /// A read or a reopen past this either got an answer or never will. `network-share`'s
    /// *Connection drops while reading*: a silent drop used to wait forever, because
    /// `NWConnection.receive` has no timeout of its own and nothing here set one — the 2 s
    /// notice and the 60 s offer both depend on ``SmbReachability/noteFailure()`` running,
    /// and it never ran. Chosen to match Android's own bound (`SmbClient.kt`'s
    /// `responseTimeout` and `connTimeout`) rather than a value invented for this platform.
    private static let readDeadline: Duration = .seconds(20)
    private static let reopenDeadline: Duration = .seconds(10)

    private func readOnce(offset: Int64, count: Int) async throws -> Data {
        if reader == nil {
            // The task group backing `SmbDeadline.run` requires its result `Sendable`, and
            // `FileReader` on its own is not — `Held` is what carries it across, same as
            // everywhere else in this file. Unwrapped only once the race is over.
            let opener = self.opener
            let held = try await SmbDeadline.run(within: Self.reopenDeadline) {
                try await opener()
            }
            reader = held.value
        }
        return try await SmbDeadline.run(within: Self.readDeadline) {
            try await self.readFromReader(offset: offset, count: count)
        }
    }

    /// The actual read, isolated to this actor so a task racing it under
    /// ``SmbDeadline/run(within:operation:)`` can call it without sending `reader` — a plain
    /// class — across the boundary. An actor's own async method is safe to invoke from
    /// anywhere, which is the same reason `read(offset:count:)` and `close()` need no such
    /// wrapper.
    private func readFromReader(offset: Int64, count: Int) async throws -> Data {
        guard let bytes = try await reader?.read(offset: UInt64(offset), length: UInt32(count))
        else { throw SmbError.hostUnreachable }
        return bytes
    }

    func close() async {
        try? await reader?.close()
        reader = nil
    }
}

/// A non-Sendable value carried across an actor boundary.
///
/// `FileReader` is a plain class, and the actor above is what serialises every use of it —
/// which is the reason that actor exists. Swift cannot see that from the type, so this says
/// it out loud in one place rather than scattering `nonisolated(unsafe)` through the file.
///
/// Internal rather than private to this file: ``SmbDeadline`` is in its own file, at the
/// 400-line cap's own insistence, and needs this to describe what it races.
struct Held<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
