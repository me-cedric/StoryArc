import Foundation
import Testing

@testable import Smb

/// A server that offers only SMB 1 is refused, and named.
///
/// `network-share` wants the refusal to say which server setting to change, rather than a
/// fifth way of saying "could not connect". This client reaches an NT status for it: a
/// server with no dialect in common answers the SMB 2 NEGOTIATE with `STATUS_NOT_SUPPORTED`,
/// and an older one answers in the CIFS error classes, which an SMB 2 server cannot send.
///
/// Mirrored case for case by `SmbProtocolRefusalTest.kt`, which reads jcifs' own sentences
/// instead because that client fails before the server answers with a status.
@Suite("SMB 1 refusal")
struct SmbProtocolRefusalTests {

    @Test("a server that would not agree a dialect is named as SMB 1")
    func namesSmb1() {
        // STATUS_NOT_SUPPORTED, the answer MS-SMB2 tells a server with no dialect in common
        // to give, then the CIFS error-class statuses an older server gives instead.
        for status: UInt32 in [0xC000_00BB, 0x0001_0002, 0x0016_0002, 0x0005_0002, 0x005B_0002, 0x00FB_0002] {
            #expect(SmbClient.meaning(of: status, isHandshake: true) == .protocolUnsupported)
        }
    }

    @Test("a failure that is not about the dialect is not named as SMB 1")
    func doesNotOverreach() {
        #expect(SmbClient.meaning(of: 0xC000_006D, isHandshake: true) == .authenticationRejected)
        #expect(SmbClient.meaning(of: 0xC000_00CC, isHandshake: true) == .shareNotFound)
        #expect(SmbClient.meaning(of: 0xC000_0203, isHandshake: true) == .hostUnreachable)
    }

    @Test("a failure nothing recognises keeps what was said, rather than guessing")
    func keepsTheDetail() {
        guard case .unexpected(let detail) = SmbClient.meaning(of: 0xC000_0001, isHandshake: true)
        else {
            Issue.record("an unrecognised status should stay unexpected")
            return
        }
        #expect(!detail.isEmpty)
    }

    /// No Android counterpart, and none is possible: jcifs only ever says "dialect" while
    /// the two ends are negotiating one, so its probe is scoped by what produces it. This
    /// client reads a status that means something far narrower once a share is open, so the
    /// scope has to be stated rather than inherited.
    @Test("the same status after the handshake is not read as SMB 1")
    func scopedToTheHandshake() {
        #expect(SmbClient.meaning(of: 0xC000_00BB) != .protocolUnsupported)
        #expect(SmbClient.meaning(of: 0x0001_0002) != .protocolUnsupported)
    }
}
