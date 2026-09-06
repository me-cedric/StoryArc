import Foundation
import Testing

@testable import Smb

/// A share that demands SMB 3 encryption is named as such, and not as a refused password.
///
/// `network-share` requires the specific failure rather than a general one. ``SmbError``
/// declared ``SmbError/encryptionRequired``, `SmbConnection` translated it into a sentence in
/// four languages, and **nothing threw it**. So a reader whose NAS has `smb encrypt =
/// required` on the share met the generic path, which reads that status as a refused
/// password. They retype a correct password until they give up.
///
/// **Where the connection learns the demand.** MS-SMB2 puts it in the tree-connect response:
/// the server sets `SMB2_SHAREFLAG_ENCRYPT_DATA` in `ShareFlags` to say that this share's
/// traffic must be encrypted. `SmbClient.connect()` threw that response away. It reads it now.
///
/// **The end-to-end path is unproven here, and this suite does not claim it.** No SMB server
/// runs in this suite, so what is asserted is the mapping from the share flags to the case,
/// not that a real NAS sets the bit. What would prove it: a Samba container with
/// `smb encrypt = required` on one share and `smb encrypt = disabled` on another, and one
/// connection to each — the first reporting `encryptionRequired`, the second connecting.
/// Android's own half is proved the same way, from jcifs' message, and no further.
@Suite("A share that demands encryption is named")
struct SmbEncryptionRequiredTests {

    /// `SMB2_SHAREFLAG_ENCRYPT_DATA`, spelled out here so the test does not read the constant
    /// it is checking out of the code it is checking.
    private static let encryptData: UInt32 = 0x0000_8000

    @Test("A share whose flags demand encryption is refused as such")
    func namesTheDemand() {
        #expect(SmbClient.refusal(forShareFlags: Self.encryptData) == .encryptionRequired)
    }

    @Test("And is not read as a refused password, which is the sentence it used to get")
    func isNotACredentialFailure() {
        #expect(SmbClient.refusal(forShareFlags: Self.encryptData) != .authenticationRejected)
    }

    /// The bit is read out of a word that carries the share's other properties too.
    @Test(
        "The demand is read beside every other share flag",
        arguments: [
            0x0000_0001, // DFS
            0x0000_0030, // no caching
            0x0000_0800, // access-based directory enumeration
            0x0010_0000, // compressed data
        ] as [UInt32]
    )
    func readsTheBitBesideOthers(_ other: UInt32) {
        #expect(SmbClient.refusal(forShareFlags: Self.encryptData | other) == .encryptionRequired)
    }

    @Test(
        "A share that demands nothing is refused nothing",
        arguments: [
            0x0000_0000, // nothing set
            0x0000_0001, // DFS
            0x0000_0030, // no caching
            0x0010_0000, // compressed data
            0x0020_0000, // isolated transport
        ] as [UInt32]
    )
    func doesNotOverreach(_ flags: UInt32) {
        #expect(SmbClient.refusal(forShareFlags: flags) == nil)
    }

    /// The reader is owed a sentence, and the sentence exists in four languages.
    ///
    /// `SmbConnection.describe(_:)` already answers `encryptionRequired` with
    /// `smb.error.encryption`; what was missing was anything that produced the case. This
    /// pins the case's own identity, so a later edit that folds it back into
    /// `authenticationRejected` fails here rather than silently in front of a reader.
    @Test("The case stays distinct from the other four")
    func staysItsOwnAnswer() {
        let refusal = SmbClient.refusal(forShareFlags: Self.encryptData)
        #expect(refusal != .hostUnreachable)
        #expect(refusal != .shareNotFound)
        #expect(refusal != .protocolUnsupported)
    }

    /// The client's own source, read from where this test file is.
    ///
    /// Reached from `#filePath` rather than found: this repository nests agent worktrees at
    /// `.claude/worktrees/`, and a walk that looks upwards for a marker climbs out of the one
    /// under test. `SourceTransportNoteTests` reads its catalogue the same way.
    private static let clientSource: String = {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/Smb/SmbClient.swift")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            fatalError("SmbClient.swift is not readable at \(file.path)")
        }
        return text
    }()

    /// That the decision above is consulted, which is the half that was missing.
    ///
    /// A rule asserted and never called is indistinguishable from a rule that works —
    /// AGENTS.md section 5 catalogues three of them in this repository. The honest test drops a
    /// Samba server that demands encryption under a real connection; there is none here, so
    /// this reads the source instead and says only what source text may honestly say: that the
    /// call exists, and that it sits before the line which declares the share usable.
    /// Android's `SourceRetryWiringTest` makes the same second choice for the same reason.
    @Test("The connection consults the share flags before it calls itself connected")
    func theRefusalIsReachable() throws {
        let text = Self.clientSource
        let start = try #require(
            text.range(of: "public func connect() async throws -> SmbIdentity"),
            "SmbClient no longer has connect()"
        )
        let body = text[start.lowerBound...]
        let consulted = try #require(
            body.range(of: "refusal(forShareFlags:"),
            "connect() never asks what the share's flags refuse, so nothing throws that case"
        )
        let connected = try #require(
            body.range(of: "isConnected = true"),
            "connect() no longer marks the session connected"
        )
        #expect(
            consulted.lowerBound < connected.lowerBound,
            "the share flags are read after the session is called connected"
        )
    }
}
