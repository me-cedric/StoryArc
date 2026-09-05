import Foundation
import SwiftUI
import Testing

@testable import SettingsFeature

import Persistence
import StoryArcCore

/// The source detail screen writes a size the way the rest of the app writes one.
///
/// `sources` names "the bytes downloaded" among the five fields the screen shows. What it
/// showed for a source with nothing downloaded was the word **Zero** — `Zero kB` in English,
/// `Zéro ko` in French — because `ByteCountFormatStyle` spells zero out unless it is told
/// not to, and this call site had not told it. Every source a reader has just added has
/// nothing downloaded, so that was the first thing the screen said about most of them.
///
/// ``Persistence/DownloadStore/formatted(_:)`` is the app's answer and predates this suite:
/// its own note records the September sweep finding *Space used — Zero kB* one screen away
/// from *Downloads · 0 bytes*, both reading `bytesOnDisk`. The sweep wrote the helper and
/// converted three call sites; this screen's two were not among them.
///
/// **The screen's value tree is built and read, not its source file.** A regex over Swift
/// source would be satisfied by the helper's name appearing in a comment — the failure
/// [SourceProgressNoteTests] records, where two matched lines survived behind `//` while the
/// row they described was replaced by `EmptyView()`. A SwiftUI `body` is an eagerly built
/// value, so what the row will draw is in it on the host with no simulator.
///
/// It is still short of a screenshot: it proves the field carries the right characters,
/// never that they fitted the row at the largest text size. That is §4.1's frame.
@MainActor
@Suite("The iOS source detail screen writes a size as a number")
struct SourceDetailSizeTests {

    /// Every verbatim string `SourceDetail` puts in its value tree for one source.
    ///
    /// The sibling of [SourceProgressNoteTests.lookups(for:)], which collects
    /// `LocalizedStringKey`s; a size is not localized by key — it is a `String` the
    /// formatter already rendered, so it arrives as `Text`'s `verbatim` storage instead.
    ///
    /// Collecting *every* `String` in the tree rather than only `Text`'s own is deliberate.
    /// It over-collects — bundle paths and key names come with it — and over-collection can
    /// only ever weaken a *negative* claim. Every assertion below is positive: a particular
    /// rendering is present. Depth is capped and class instances are visited once, because
    /// the tree holds bundles and key paths that refer back into it.
    private static func rendered(_ diagnosis: SourceDiagnosis) -> Set<String> {
        let view = SourceDetail(
            source: Source(displayName: "Fixture", kind: .networkShare, state: .connected),
            diagnosis: diagnosis,
            perform: { _ in }
        )

        var found: Set<String> = []
        var seen: Set<ObjectIdentifier> = []

        func walk(_ value: Any, depth: Int) {
            guard depth < 40 else { return }
            if let text = value as? String {
                found.insert(text)
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

    private static func diagnosis(bytes: Int64, downloads: Int) -> SourceDiagnosis {
        SourceDiagnosis(
            state: .connected,
            lastSuccessfulSync: nil,
            failure: nil,
            itemCount: 3,
            downloadCount: downloads,
            downloadedBytes: bytes,
            actions: [.testConnection, .refresh, .clearCache, .remove]
        )
    }

    @Test("A source with nothing downloaded shows a number, not the word zero")
    func zeroIsANumber() {
        // The defect, stated as the assertion. Before the fix the field held the platform's
        // spelled-out zero, which differs from the helper's rendering in all four shipped
        // languages — `Zero kB`/`0 bytes`, `Zéro ko`/`0 octet`, `0 kB`/`0 Byte`,
        // `0 kB`/`0 bytes` — so this case fails whichever of them the host is running in.
        let shown = Self.rendered(Self.diagnosis(bytes: 0, downloads: 0))
        #expect(
            shown.contains(DownloadStore.formatted(0)),
            "the field did not write zero the way the app does: \(shown.sorted())"
        )
    }

    @Test("A source with downloads shows the figure the rest of the app would show")
    func aRealSizeIsTheAppsOwn() {
        // The control. `zeroIsANumber` alone would pass against a screen that had lost the
        // row entirely and gained the string somewhere else, and against a walk that had
        // stopped working the day an SDK renamed a stored property.
        let bytes: Int64 = 5_242_880
        let shown = Self.rendered(Self.diagnosis(bytes: bytes, downloads: 2))
        #expect(
            shown.contains(DownloadStore.formatted(bytes)),
            "the field did not write \(DownloadStore.formatted(bytes)): \(shown.sorted())"
        )
    }

    @Test(
        "Zero reads as a numeral in each of the four languages",
        arguments: ["en", "fr", "de", "es"]
    )
    func everyLanguageGetsANumeral(_ language: String) {
        // Why the helper passes `spellsOutZero: false` rather than the app carrying a
        // "sources.detail.noDownloads" key of its own: the platform already has the sentence
        // in every language it ships, and a catalogue entry would be a fifth wording to keep
        // in step with four. What has to hold is only that each of them starts with a digit.
        //
        // `localization` names these four; `strings:ios` checks that every *key* resolves in
        // all of them and cannot see a size, because a size never becomes a key.
        let zero = Int64(0).formatted(
            .byteCount(style: .file, spellsOutZero: false).locale(Locale(identifier: language))
        )
        #expect(zero.first?.isNumber == true, "\(language) rendered zero as \"\(zero)\"")
    }
}
