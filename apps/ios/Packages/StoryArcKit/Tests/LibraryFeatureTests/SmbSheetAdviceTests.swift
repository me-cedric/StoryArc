import Foundation
import SwiftUI
import Testing

@testable import LibraryFeature

@testable import Smb

/// The add-share sheet draws the sentence a refused local-network permission earns.
///
/// `network-share`'s *Local network permission denied* asks for three things: discovery
/// hidden, manual entry working, and the app explaining "once how to enable discovery in
/// system settings". ``SmbDiscovery`` produces that sentence, and ``SmbDiscoveryRefusalTests``
/// holds it there. This suite holds the other half: that the sheet puts it on a screen.
///
/// **A produced sentence and a drawn one are different claims.** The sentence shipped once
/// with no reader able to see it — `SmbSheet` read `discovery.hosts` and never
/// `discovery.advice` — and every test passed, because all of them stopped at the producer.
/// So this walks the sheet's own body and looks for the sentence in it.
///
/// **The sentence is the key here, not the words.** `swift build` copies an `.xcstrings`
/// without compiling it, so `String(localized:)` answers with the key on the host.
/// ``SmbDiscoveryRefusalTests`` reads the four translations off the catalogue on disk.
@MainActor
@Suite("The add-share sheet explains a refused local-network permission")
struct SmbSheetAdviceTests {

    /// What `SmbDiscovery` writes on a refusal, which on the host is the key itself.
    private static let sentence = "smb.discovery.denied"

    /// Every string the sheet's body carries, verbatim ones and localization keys alike.
    ///
    /// The reflection walk ``SourceProgressNoteTests`` documents in full, widened by one case:
    /// the advice is a `String` the discovery already localized rather than a
    /// `LocalizedStringKey`, so a walk that collects only keys would miss it.
    private static func strings(of view: some View) -> Set<String> {
        var found: Set<String> = []
        var seen: Set<ObjectIdentifier> = []

        func walk(_ value: Any, depth: Int) {
            guard depth < 40 else { return }
            if let text = value as? String {
                found.insert(text)
                return
            }
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

    private static func sheet(_ discovery: SmbDiscovery) -> SmbSheet {
        SmbSheet(connection: SmbConnection(), discovery: discovery, onAdd: { _ in })
    }

    @Test("A refused permission puts the sentence on the sheet")
    func aRefusalIsExplainedOnTheSheet() {
        let discovery = SmbDiscovery()
        discovery.noteRefusal()
        let drawn = Self.strings(of: Self.sheet(discovery))
        #expect(drawn.contains(Self.sentence), "the sheet drew \(drawn.sorted())")
    }

    @Test("A permission that was never refused puts nothing there")
    func silenceIsNotExplained() {
        // The other half of the claim, and the one that stops the sentence being drawn always.
        // A reader whose network simply holds no NAS is not told to change a setting that is
        // already right.
        let drawn = Self.strings(of: Self.sheet(SmbDiscovery()))
        #expect(!drawn.contains(Self.sentence), "the sheet drew \(drawn.sorted())")
        #expect(drawn.contains("smb.host.label"), "the walk found nothing: \(drawn.sorted())")
    }

    @Test("A refusal still leaves the host list empty, so discovery keeps hiding itself")
    func discoveryStaysHidden() {
        // `network-share` asks for discovery hidden and manual entry working. The host section
        // is drawn only when the list is not empty, and the fields are drawn either way.
        let discovery = SmbDiscovery()
        discovery.noteRefusal()
        let drawn = Self.strings(of: Self.sheet(discovery))
        #expect(!drawn.contains("smb.found"), "the sheet drew a host section: \(drawn.sorted())")
        #expect(drawn.contains("smb.connect"), "the sheet drew no connect button: \(drawn.sorted())")
    }
}
