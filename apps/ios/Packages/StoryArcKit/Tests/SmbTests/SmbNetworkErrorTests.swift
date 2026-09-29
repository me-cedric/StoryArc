import Foundation
import Network
import Testing

@testable import Smb

/// A host that never answered, or that this device cannot reach, is named as such rather
/// than falling to the generic sentence.
///
/// `network-share` "Adding a share" wants the specific failure named. `SmbClient` translated
/// `URLError` and a bare `NSPOSIXErrorDomain` error, but SMBClient's own `Connection` throws
/// the raw `NWError` its socket produces (`.waiting` and `.failed`), which bridged to neither
/// of those and fell to ``SmbError/unexpected(detail:)`` -- the same sentence a share that
/// demands encryption used to give, before that got its own case.
///
/// A denied Local Network permission is the same story from a different code: `EPERM`, on a
/// direct connection this device never had permission to open at all.
@Suite("A network failure is read for what it is")
struct SmbNetworkErrorTests {

    @Test("An unreachable or unresolvable host is read as such from NWError")
    func hostUnreachableFromNWError() {
        #expect(SmbClient.meaning(of: .dns(-65563)) == .hostUnreachable)
        #expect(SmbClient.meaning(of: .posix(.ECONNREFUSED)) == .hostUnreachable)
        #expect(SmbClient.meaning(of: .posix(.EHOSTUNREACH)) == .hostUnreachable)
        #expect(SmbClient.meaning(of: .posix(.ENETUNREACH)) == .hostUnreachable)
        #expect(SmbClient.meaning(of: .posix(.ETIMEDOUT)) == .hostUnreachable)
    }

    @Test("A refused Local Network permission is its own failure, not host-unreachable")
    func localNetworkDeniedFromNWError() {
        #expect(SmbClient.meaning(of: .posix(.EPERM)) == .localNetworkDenied)
    }

    @Test("The same POSIX codes are read the same way as a bare NSError")
    func posixCodesMatchWhicheverWayTheyArrive() {
        #expect(SmbClient.meaning(ofPosix: POSIXErrorCode.EPERM.rawValue) == .localNetworkDenied)
        #expect(SmbClient.meaning(ofPosix: POSIXErrorCode.ECONNREFUSED.rawValue) == .hostUnreachable)
        #expect(SmbClient.meaning(ofPosix: POSIXErrorCode.EHOSTUNREACH.rawValue) == .hostUnreachable)
    }

    @Test("A failure nothing recognises keeps what was said, rather than guessing")
    func unrecognisedNWErrorStaysUnexpected() {
        guard case .unexpected = SmbClient.meaning(of: .posix(.ENETDOWN)) else {
            Issue.record("an unrecognised NWError should stay unexpected")
            return
        }
    }

    /// The two new sentences, and each of their translations in the catalogue on disk.
    ///
    /// Mirrors `SmbDiscoveryRefusalTests.sentences`: `swift build` copies an `.xcstrings`
    /// without compiling it, and an older host answers `String(localized:)` with the bare
    /// key while macOS 26 answers with the translation, so either is accepted.
    private static func sentences(for key: String) throws -> Set<String> {
        var found: Set<String> = [key]
        let record = try localizations(for: key)
        for case let unit as [String: Any] in record.values {
            if let value = (unit["stringUnit"] as? [String: Any])?["value"] as? String { found.insert(value) }
        }
        return found
    }

    private static func localizations(for key: String) throws -> [String: Any] {
        let catalogue = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/LibraryFeature/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogue)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = try #require(parsed?["strings"] as? [String: Any])
        let record = try #require(strings[key] as? [String: Any], "no such key")
        return try #require(record["localizations"] as? [String: Any])
    }

    @Test(
        "Both new sentences are answerable in four languages",
        arguments: ["smb.error.smbNewer", "smb.error.localNetworkDenied"], ["en", "fr", "de", "es"]
    )
    func sentencesAreTranslated(_ key: String, _ language: String) throws {
        let localizations = try Self.localizations(for: key)
        let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
        #expect(unit?["state"] as? String == "translated", "\(key) not translated into \(language)")
        #expect((unit?["value"] as? String)?.isEmpty == false, "\(key) empty in \(language)")
    }
}
