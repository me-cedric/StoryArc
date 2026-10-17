import Foundation
import StoryArcCore
import Testing

@testable import StoryArc

/// The rows of the Sources tab, test first (task 3.10).
///
/// `desktop-experience`, *Finding and reaching a network share*: a share states whether its
/// connection is encrypted, and a share that refused names why. `sources`: an unreachable
/// source is grey, never red, and a refused sign-in offers one action.
@Suite("Source rows")
struct SourceRowTests {
    private let share = Source(
        displayName: "nas/Comics", kind: .networkShare, state: .connected,
        locator: "smb://reader@nas.local:4745/Comics"
    )

    @Test("A share whose session was encrypted says so, with the dialect")
    func encryptedShare() {
        let row = SourceRow(server: share, transport: ShareTransport(dialect: "SMB 3.1.1", isEncrypted: true))
        #expect(row.kind == .share)
        #expect(row.lines == [.encrypted(dialect: "SMB 3.1.1")])
        #expect(!row.isGrey)
    }

    @Test("A share whose session was not encrypted says that too")
    func plainShare() {
        let row = SourceRow(server: share, transport: ShareTransport(dialect: "SMB 2.1", isEncrypted: false))
        #expect(row.lines == [.notEncrypted(dialect: "SMB 2.1")])
    }

    @Test("A share not connected in this run claims nothing about encryption")
    func shareNotYetConnected() {
        let row = SourceRow(server: share, transport: nil)
        #expect(row.lines == [.transportUnknown])
    }

    @Test("An unreachable source is grey and keeps its place")
    func unreachableIsGrey() {
        var away = share
        away.state = .unreachable(since: Date(timeIntervalSince1970: 0))
        let row = SourceRow(server: away, transport: nil)
        #expect(row.isGrey)
        #expect(row.lines.first == .unreachable)
    }

    @Test("A refused sign-in asks for the sign-in and offers to reconnect")
    func refusedSignIn() {
        let kavita = Source(
            displayName: "Kavita", kind: .kavitaServer, state: .unauthorized(reason: "401"),
            locator: "http://127.0.0.1:4650"
        )
        let row = SourceRow(server: kavita, transport: nil)
        #expect(row.kind == .kavita)
        #expect(row.lines == [.needsSignIn])
        #expect(row.offersReconnect)
        #expect(row.isGrey)
    }

    @Test("A catalogue names nothing about a transport it does not have")
    func catalogue() {
        let opds = Source(
            displayName: "Corpus", kind: .opdsCatalog, state: .connected, locator: "http://127.0.0.1:4644/opds"
        )
        let row = SourceRow(server: opds, transport: ShareTransport(dialect: "SMB 3.1.1", isEncrypted: true))
        #expect(row.kind == .catalogue)
        #expect(row.lines.isEmpty)
    }

    @Test("The address shown never carries a user name")
    func addressWithoutUser() {
        let row = SourceRow(server: share, transport: nil)
        #expect(row.address == "smb://nas.local:4745/Comics")
    }
}
