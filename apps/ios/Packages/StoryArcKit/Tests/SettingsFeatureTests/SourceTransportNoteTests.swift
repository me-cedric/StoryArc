import Foundation
import SwiftUI
import Testing

@testable import SettingsFeature

import StoryArcCore

/// The source detail screen states how a share is reached, and whether that is encrypted.
///
/// `network-share`'s *Encrypted transport*: "the source detail screen states whether the
/// connection is encrypted". The sentence existed only in the add-share sheet, which a reader
/// sees once, before the source exists. This suite asserts the detail screen says it too.
///
/// **The sentence names encryption and never signing, and that is [ADR-0016][adr]'s rule
/// rather than an omission.** iOS's SMB client verifies no response, so it cannot answer
/// whether a session is signed; Android's can, and says so on its own add-share sheet. The
/// ADR refuses that line on iOS — "the app does not explain its own weaknesses to the reader"
/// — so the detail screen, which both platforms draw the same way, states the transport and
/// the encryption alone. A signed session and an unsigned one therefore read identically here.
///
/// [adr]: docs/decisions/0016-ios-smb-response-signing.md
///
/// **The sentence denies encryption, and the denial is what is asserted.** Both clients
/// hardcode `isEncrypted = false`, so the screen states a constant rather than reading the
/// session, and [ADR-0016][adr] records why that is where this stands. The day item 1 of that
/// ADR's *What would change this* lands, the four sentences become false and these tests fail
/// by name, in whichever language was edited first.
///
/// **The view's own body is built and read, not its source file**, for the reason
/// ``SourceProgressNoteTests`` gives: a guard that a comment satisfies is not a guard. The
/// four translations are read from the catalogue on disk, because `swift build` copies an
/// `.xcstrings` without compiling it and `String(localized:)` answers with the key on the host.
@MainActor
@Suite("The iOS source detail screen states a share's transport")
struct SourceTransportNoteTests {

    /// The key the sentence is drawn from, and the field that proves the walk still works.
    private static let note = "sources.detail.transport"
    private static let anyField = "sources.detail.status"

    /// Every localization key `SourceDetail` looks up for one source.
    ///
    /// The same reflection walk ``SourceProgressNoteTests`` documents in full: `Text` keeps the
    /// `LocalizedStringKey` it was given, nothing public exposes it, and `Mirror` is the only
    /// way in without a simulator.
    private static func lookups(for source: Source) -> Set<String> {
        let view = SourceDetail(
            source: source,
            diagnosis: SourceDiagnosis.of(source, itemCount: 3, downloads: []),
            perform: { _ in }
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

    /// The settings catalogue on disk, for one key.
    ///
    /// Reached from `#filePath` rather than found: this repository nests agent worktrees at
    /// `.claude/worktrees/`, and a walk that looks upwards for a marker climbs out of the one
    /// under test.
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

    @Test("A share on the network states its transport")
    func aShareStatesItsTransport() {
        let keys = Self.lookups(for: Self.source(.networkShare))
        #expect(keys.contains(Self.note), "the share looked up \(keys.sorted())")
    }

    @Test(
        "No other kind states one, because SMB is not how any of them is reached",
        arguments: [SourceKind.localFolder, .opdsCatalog, .kavitaServer]
    )
    func noOtherKindStatesATransport(for kind: SourceKind) {
        let keys = Self.lookups(for: Self.source(kind))
        #expect(keys.contains(Self.anyField), "the walk found nothing: \(keys.sorted())")
        #expect(!keys.contains(Self.note), "\(kind) looked up \(keys.sorted())")
    }

    /// A signed session and an unsigned one read the same, because signing never reaches here.
    ///
    /// The screen is handed a ``Source`` and a ``SourceDiagnosis``, and neither carries what
    /// the session negotiated. So the sentence cannot vary with it, and this asserts that the
    /// state a live session does reach the screen through — connected, or refused — moves the
    /// sentence no more than signing does.
    @Test(
        "The sentence is the same whatever the session negotiated",
        arguments: [
            SourceConnectionState.connected,
            .unauthorized(reason: "The password was refused."),
            .unreachable(since: Date(timeIntervalSince1970: 0)),
        ]
    )
    func theSentenceDoesNotMoveWithTheSession(for state: SourceConnectionState) {
        let keys = Self.lookups(for: Self.source(.networkShare, state: state))
        #expect(keys.contains(Self.note), "\(state) looked up \(keys.sorted())")
    }

    /// The claim a reader is owed, and the words ADR-0016 refuses.
    ///
    /// **The negation is matched, not the word alone.** An earlier form of this suite asked
    /// only whether each sentence carried the word for "encrypted", so *The connection is
    /// encrypted.* satisfied it. That is the edit someone will make the day a client
    /// negotiates SMB 3, and it is the edit that lands in one language before the other three.
    /// The polarity is the whole of the claim, so the polarity is what is pinned.
    ///
    /// Every token is matched against every language: a French word has no business in the
    /// German sentence either, and the signing half is a promise this app does not make in any
    /// of the four.
    private static let notEncrypted = [
        "en": "not encrypted",
        "fr": "pas chiffré",
        "de": "nicht verschlüsselt",
        "es": "no está cifrad",
    ]
    private static let signing = [
        "signed", "signing", "signé", "signature", "signiert", "signatur", "firmad", "firma",
    ]

    @Test(
        "Every language states that the connection is not encrypted",
        arguments: ["en", "fr", "de", "es"]
    )
    func everyLanguageDeniesEncryption(_ language: String) throws {
        let sentence = try Self.value(of: Self.note, in: language).lowercased()
        let claim = try #require(Self.notEncrypted[language])
        #expect(sentence.contains(claim), "the \(language) sentence reads \"\(sentence)\"")
    }

    @Test("No language claims anything about signing", arguments: ["en", "fr", "de", "es"])
    func noLanguageNamesSigning(_ language: String) throws {
        let sentence = try Self.value(of: Self.note, in: language).lowercased()
        for claim in Self.signing {
            #expect(!sentence.contains(claim), "the \(language) sentence mentions \(claim)")
        }
    }
}
