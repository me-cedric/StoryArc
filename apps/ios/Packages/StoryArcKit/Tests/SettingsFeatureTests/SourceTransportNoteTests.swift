import Foundation
import SwiftUI
import Testing

@testable import SettingsFeature

import StoryArcCore

/// The source detail screen states how a share is reached, and whether that is encrypted.
///
/// `network-share`'s *Encrypted transport*: "the source detail screen states whether the
/// connection is encrypted".
///
/// **The screen used to draw one fixed key.** It said the connection is not encrypted
/// whatever the code had measured, so it made a claim about a reader's security that nothing
/// had checked. The tests that matter are the first two below: they build the view with each
/// measurement and read back which key it looked up. Against the old view the first one
/// fails, because the old view looked up the same key for both answers.
///
/// **Neither client encrypts today**, so a reader only ever sees the plain sentence. The
/// encrypted answer is still exercised here, because the point of the change is that the
/// screen follows the value instead of repeating an answer.
///
/// **The sentence names encryption and never signing, and that is [ADR-0016][adr]'s rule
/// rather than an omission.** That ADR refuses a signing line on iOS, because this client
/// verifies no response. Android's client can answer the question and its add-share sheet
/// says so; this screen is drawn the same way on both platforms, so a signed session and an
/// unsigned one read identically here.
///
/// [adr]: docs/decisions/0016-ios-smb-response-signing.md
@MainActor
@Suite("The iOS source detail screen states a share's transport")
struct SourceTransportNoteTests {

    private static let plain = "sources.detail.transport.plain"
    private static let encrypted = "sources.detail.transport.encrypted"
    private static let anyField = "sources.detail.status"

    private static func lookups(for source: Source, isEncrypted: Bool = false) -> Set<String> {
        let view = SourceDetail(
            source: source,
            diagnosis: SourceDiagnosis.of(source, itemCount: 3, downloads: []),
            perform: { _ in },
            isTransportEncrypted: isEncrypted
        )

        var found: Set<String> = []
        var seen: Set<ObjectIdentifier> = []

        func walk(_ value: Any, depth: Int) {
            guard depth < 40 else { return }
            if type(of: value) == LocalizedStringKey.self {
                for child in Mirror(reflecting: value).children where child.label == "key" {
                    if let key = child.value as? String { found.insert(key) }
                }
                return
            }
            let mirror = Mirror(reflecting: value)
            if mirror.displayStyle == .class,
               !seen.insert(ObjectIdentifier(value as AnyObject)).inserted {
                return
            }
            for child in mirror.children { walk(child.value, depth: depth + 1) }
        }

        walk(view.body, depth: 0)
        return found
    }

    private static func localizations(of key: String) -> [String: Any]? {
        let catalogue = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Sources/SettingsFeature/Resources/Localizable.xcstrings")
        guard
            let data = try? Data(contentsOf: catalogue),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let strings = parsed["strings"] as? [String: Any]
        else {
            fatalError("the settings string catalogue is not readable at \(catalogue.path)")
        }
        guard let record = strings[key] as? [String: Any] else { return nil }
        return record["localizations"] as? [String: Any] ?? [:]
    }

    private static func value(of key: String, in language: String) throws -> String {
        let localizations = try #require(
            Self.localizations(of: key),
            "the catalogue defines no \"\(key)\""
        )
        let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
        return try #require(unit?["value"] as? String, "\"\(key)\" is empty in \(language)")
    }

    private static func source(_ kind: SourceKind, state: SourceConnectionState = .connected) -> Source {
        Source(displayName: "Fixture", kind: kind, state: state)
    }

    @Test("A share whose connection is encrypted states that it is encrypted")
    func anEncryptedShareSaysSo() {
        let keys = Self.lookups(for: Self.source(.networkShare), isEncrypted: true)
        #expect(keys.contains(Self.encrypted), "the share looked up \(keys.sorted())")
        #expect(!keys.contains(Self.plain), "the share looked up \(keys.sorted())")
    }

    @Test("A share whose connection is not encrypted says so")
    func aPlaintextShareSaysSo() {
        let keys = Self.lookups(for: Self.source(.networkShare), isEncrypted: false)
        #expect(keys.contains(Self.plain), "the share looked up \(keys.sorted())")
        #expect(!keys.contains(Self.encrypted), "the share looked up \(keys.sorted())")
    }

    @Test("The rule answers a different sentence for each measurement")
    func theRuleFollowsTheMeasurement() {
        #expect(
            transportNote(for: .networkShare, isEncrypted: true)
                != transportNote(for: .networkShare, isEncrypted: false)
        )
    }

    @Test(
        "No other kind has a transport to state, because SMB is not how any of them is reached",
        arguments: [SourceKind.localFolder, .opdsCatalog, .kavitaServer]
    )
    func noOtherKindStatesATransport(for kind: SourceKind) {
        #expect(transportNote(for: kind, isEncrypted: false) == nil)
        #expect(transportNote(for: kind, isEncrypted: true) == nil)

        let keys = Self.lookups(for: Self.source(kind))
        #expect(keys.contains(Self.anyField), "the walk found nothing: \(keys.sorted())")
        #expect(!keys.contains(Self.plain), "\(kind) looked up \(keys.sorted())")
        #expect(!keys.contains(Self.encrypted), "\(kind) looked up \(keys.sorted())")
    }

    @Test(
        "The sentence is stated whatever the session did, because it is a standing fact",
        arguments: [
            SourceConnectionState.connected,
            .unauthorized(reason: "The password was refused."),
            .unreachable(since: Date(timeIntervalSince1970: 0)),
        ]
    )
    func theSentenceDoesNotMoveWithTheSession(for state: SourceConnectionState) {
        let keys = Self.lookups(for: Self.source(.networkShare, state: state))
        #expect(keys.contains(Self.plain), "\(state) looked up \(keys.sorted())")
    }

    /// The denial that belongs to the plain sentence, and to that one only.
    ///
    /// Two catalogue entries that had been swapped would pass the two drawing tests above
    /// and fail here.
    private static let denial = [
        "en": "not encrypted",
        "fr": "pas chiffré",
        "de": "nicht verschlüsselt",
        "es": "no está cifrad",
    ]
    private static let signing = [
        "signed", "signing", "signé", "signature", "signiert", "signatur", "firmad", "firma",
    ]

    @Test("The denial belongs to the plain sentence alone", arguments: ["en", "fr", "de", "es"])
    func onlyThePlainSentenceDeniesEncryption(_ language: String) throws {
        let plain = try Self.value(of: Self.plain, in: language).lowercased()
        let encrypted = try Self.value(of: Self.encrypted, in: language).lowercased()
        let claim = try #require(Self.denial[language])
        #expect(plain.contains(claim), "the \(language) plain sentence reads \"\(plain)\"")
        #expect(
            !encrypted.contains(claim),
            "the \(language) encrypted sentence reads \"\(encrypted)\""
        )
    }

    @Test("Neither sentence claims anything about signing", arguments: ["en", "fr", "de", "es"])
    func noLanguageNamesSigning(_ language: String) throws {
        for key in [Self.plain, Self.encrypted] {
            let sentence = try Self.value(of: key, in: language).lowercased()
            for claim in Self.signing {
                #expect(!sentence.contains(claim), "the \(language) \(key) mentions \(claim)")
            }
        }
    }
}
