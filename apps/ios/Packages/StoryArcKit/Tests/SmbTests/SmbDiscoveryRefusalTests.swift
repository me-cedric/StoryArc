import Foundation
import Network
import Testing

@testable import Smb

/// A refused local-network permission is noticed, and explained once.
///
/// `network-share`'s *Local network permission denied*: "discovery is hidden, manual entry
/// still works, and the app explains once how to enable discovery in system settings". Two of
/// the three were already true and are deliberate — an empty host list draws nothing, and the
/// form sits beside the list rather than behind it. The third was missing, and so was the fact
/// it needed: ``SmbDiscovery`` built an `NWBrowser` and set no `stateUpdateHandler`, so a
/// refusal and an empty network were the same silence.
///
/// **Explained once, and not as a failure.** AGENTS.md section 2 keeps a normal condition out
/// of the reader's way: this is a sentence beside the form, not an alert to dismiss, and a
/// second scan does not say it again. ``SmbDiscovery/noteRefusal()`` reports whether it
/// produced the sentence, which is what makes "once" a thing a test can hold.
///
/// **The sentence itself is not asserted here.** `swift build` copies an `.xcstrings` without
/// compiling it, so `String(localized:)` answers with the key on the host. What is asserted is
/// that the key is produced, produced once, and answerable in four languages — the last read
/// from the catalogue on disk.
@MainActor
@Suite("A refused local-network permission is explained once")
struct SmbDiscoveryRefusalTests {

    private static let key = "smb.discovery.denied"

    @Test("A refused browser is recognised from what Network reports")
    func aRefusalIsRecognised() {
        // The two dnssd codes a refused permission answers with, and the POSIX refusal the
        // same policy produces on a direct local connection. Values rather than the `dnssd`
        // constants so this reads as the wire does: -65570 is kDNSServiceErr_PolicyDenied and
        // -65555 is kDNSServiceErr_NoAuth.
        #expect(SmbDiscovery.isRefusal(.dns(-65570)))
        #expect(SmbDiscovery.isRefusal(.dns(-65555)))
        #expect(SmbDiscovery.isRefusal(.posix(.EPERM)))
    }

    @Test("An ordinary network failure is not a refusal")
    func anOrdinaryFailureIsNotARefusal() {
        // The other half of the claim. A browser waiting because the Wi-Fi is down must not
        // tell a reader to change a setting that is already right.
        #expect(!SmbDiscovery.isRefusal(.posix(.ECONNREFUSED)))
        #expect(!SmbDiscovery.isRefusal(.posix(.ENETDOWN)))
        #expect(!SmbDiscovery.isRefusal(.dns(-65563)))
    }

    @Test("The sentence is produced on the first refusal")
    func theSentenceIsProduced() {
        let discovery = SmbDiscovery()
        #expect(discovery.advice == nil)
        #expect(discovery.noteRefusal())
        #expect(discovery.advice == Self.key)
    }

    @Test("A second scan does not produce it again")
    func theSentenceIsProducedOnce() {
        let discovery = SmbDiscovery()
        _ = discovery.noteRefusal()
        // What a second appearance of the sheet does: stop, then start, then be refused
        // again. The sentence stays the one already on screen rather than becoming a second.
        discovery.stop()
        #expect(!discovery.noteRefusal())
        #expect(discovery.advice == Self.key)
    }

    @Test("Discovery still hides itself when the permission is refused")
    func discoveryStaysHidden() {
        // `SmbSheet` draws the host section only when the list is not empty, so an empty list
        // is the hiding. A refusal must not put anything in it.
        let discovery = SmbDiscovery()
        _ = discovery.noteRefusal()
        #expect(discovery.hosts.isEmpty)
    }

    @Test("The sentence is answerable in four languages", arguments: ["en", "fr", "de", "es"])
    func theSentenceIsTranslated(_ language: String) throws {
        let catalogue = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/Smb/Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogue)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let strings = try #require(parsed?["strings"] as? [String: Any])
        let record = try #require(strings[Self.key] as? [String: Any], "no such key")
        let localizations = try #require(record["localizations"] as? [String: Any])
        let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
        #expect(unit?["state"] as? String == "translated", "not translated into \(language)")
        #expect((unit?["value"] as? String)?.isEmpty == false, "empty in \(language)")
    }
}
