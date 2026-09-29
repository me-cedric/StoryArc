internal import Foundation

internal import Formats
internal import Network

// The module and its main class share a name, so each class is imported by itself: written
// as `SMBClient.SMBClient` the compiler reads the module and finds no member.
internal import class SMBClient.SMBClient
internal import class SMBClient.FileReader
internal import class SMBClient.Session

/// One open file on a share, and the connection it rides on.
///
/// The connection travels with the reader so that ``SmbSource`` can end it. SMBClient's
/// `Connection.send` waits for a reply with no timeout and no cancellation, so a read on a
/// connection that went silent is ended by one thing only: cancelling that connection.
struct SmbSession {
    let client: SMBClient
    let reader: FileReader
}

/// A file on a share, read at an offset.
///
/// The third implementation ADR-0008 planned for. SMB2's `READ` takes an offset and a length
/// as a first-class operation, so this is the interface it was already shaped like.
///
/// A file of its own rather than a private actor inside `SmbClient.swift`, which is at the
/// 400-line cap.
actor SmbSource: RandomAccessSource {
    /// `nonisolated(unsafe)` for the reason the client's own is: the library's types are
    /// plain classes, and this actor is what serialises every use of them.
    nonisolated(unsafe) private var session: SmbSession?
    private let opener: @Sendable () async throws -> Held<SmbSession>
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

    init(length: Int64, opener: @escaping @Sendable () async throws -> Held<SmbSession>) {
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
        session?.client.session.disconnect()
    }

    private func noteNetworkChange() {
        guard hasSeenFirstPath else {
            hasSeenFirstPath = true
            return
        }
        drop()
    }

    /// Reads, and opens a new session once if the old one has gone.
    ///
    /// `network-share` requires the app to "re-establish the session transparently on the
    /// next read" after the device sleeps, and to reconnect in the background when the
    /// connection drops. Both are the same act from here: the session is stale, so drop it,
    /// make another and ask again. Once, not in a loop — a share that is genuinely gone
    /// should say so rather than hang.
    func read(offset: Int64, count: Int) async throws -> Data {
        let available = max(0, length - offset)
        let toRead = Int(min(Int64(count), available))
        guard toRead > 0 else { return Data() }

        do {
            return try await readOnce(offset: offset, count: toRead)
        } catch {
            drop()
            do {
                return try await readOnce(offset: offset, count: toRead)
            } catch {
                drop()
                throw SmbError.hostUnreachable
            }
        }
    }

    /// A read or a reopen past this either got an answer or never will. `network-share`'s
    /// *Connection drops while reading*: a silent drop used to wait forever, because
    /// `NWConnection.receive` has no timeout of its own and nothing here set one. Chosen to
    /// match Android's own bound (`SmbClient.kt`'s `responseTimeout` and `connTimeout`)
    /// rather than a value invented for this platform.
    private static let readDeadline: Duration = .seconds(20)
    private static let reopenDeadline: Duration = .seconds(10)

    private func readOnce(offset: Int64, count: Int) async throws -> Data {
        if session == nil {
            // `Held` carries the non-Sendable session out of the race, and it is unwrapped
            // only once the race is over.
            let opener = self.opener
            session = try await SmbDeadline.run(within: Self.reopenDeadline) {
                try await opener()
            }.value
        }
        return try await SmbDeadline.run(within: Self.readDeadline) {
            try await self.readFromSession(offset: offset, count: count)
        }
    }

    /// The actual read, isolated to this actor so a task racing it under
    /// ``SmbDeadline/run(within:operation:)`` can call it without sending the session — a
    /// plain class — across the boundary.
    private func readFromSession(offset: Int64, count: Int) async throws -> Data {
        guard let bytes = try await session?.reader.read(offset: UInt64(offset), length: UInt32(count))
        else { throw SmbError.hostUnreachable }
        return bytes
    }

    /// Forgets the session without asking it anything.
    ///
    /// Cancelling the connection is what ends a read still waiting on it: the pending
    /// receive fails, and the read that lost its deadline returns at last. An SMB `CLOSE`
    /// first would be one more request on a connection that answers nothing, and the server
    /// closes the file with the session anyway.
    private func drop() {
        session?.client.session.disconnect()
        session = nil
    }
}

/// A non-Sendable value carried across an actor boundary.
///
/// `FileReader` is a plain class, and the actor above is what serialises every use of it —
/// which is the reason that actor exists. Swift cannot see that from the type, so this says
/// it out loud in one place rather than scattering `nonisolated(unsafe)` through the file.
struct Held<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
