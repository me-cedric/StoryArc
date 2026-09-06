import Foundation
import Testing

@testable import LibraryFeature

import Smb
import StoryArcCore

/// What a share's refusal leaves the source saying.
///
/// `network-share` asks the app to "report the specific failure" when a share refuses. The
/// add-a-share sheet did that; the health probe behind a share already saved did not, so a
/// share that demands SMB 3 encryption came back as *No answer since …*. That is false — the
/// server answered and refused — and it is also expensive: `sources` retries an unreachable
/// source every 5 s rising to every 5 minutes, so the app asked a share that can never say
/// yes for as long as the library was on screen.
///
/// Android's `SmbSourceStateTest` holds this table case for case.
@Suite("What a share's refusal means for its source")
struct SmbSourceStateTests {

    private static let moment = Date(timeIntervalSince1970: 1_000)

    private static func unauthorized(_ state: SourceConnectionState) -> String? {
        guard case .unauthorized(let reason) = state else { return nil }
        return reason
    }

    @Test("A share that demands encryption says so, and is not called unreachable")
    func encryptionIsNamed() throws {
        let state = SmbSourceState.of(.encryptionRequired, at: Self.moment)
        let reason = try #require(Self.unauthorized(state), "a refusal was reported as silence")
        #expect(!reason.isEmpty)
    }

    @Test("The refusal a reader can act on is not the one about a password")
    func encryptionIsItsOwnSentence() throws {
        let encryption = try #require(
            Self.unauthorized(SmbSourceState.of(.encryptionRequired, at: Self.moment))
        )
        let password = try #require(
            Self.unauthorized(SmbSourceState.of(.authenticationRejected, at: Self.moment))
        )
        #expect(encryption != password, "an encrypted share was blamed on the password again")
    }

    @Test("A share that did not answer is unreachable, and keeps the moment it went")
    func silenceStaysUnreachable() {
        #expect(SmbSourceState.of(.hostUnreachable, at: Self.moment) == .unreachable(since: Self.moment))
        #expect(SmbSourceState.of(.shareNotFound, at: Self.moment) == .unreachable(since: Self.moment))
        #expect(
            SmbSourceState.of(.unexpected(detail: "x"), at: Self.moment) == .unreachable(since: Self.moment)
        )
    }

    @Test("An SMB 1 server is offline rather than something the reader must fix here")
    func smb1StaysUnreachable() {
        // Offline is a normal state. `protocolUnsupported` is the app's own refusal to speak
        // SMB 1, and the add-a-share sheet is where that sentence belongs — a saved share
        // that turns out to be SMB 1 is grey, not a badge asking for action.
        #expect(
            SmbSourceState.of(.protocolUnsupported, at: Self.moment) == .unreachable(since: Self.moment)
        )
    }
}
