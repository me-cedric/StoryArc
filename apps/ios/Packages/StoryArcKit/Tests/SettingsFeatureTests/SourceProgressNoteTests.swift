import Foundation
import SwiftUI
import Testing

@testable import SettingsFeature

import Persistence
import StoryArcCore

/// The source detail screen says when a source cannot hold a reading position.
///
/// `reading-progress`' *Source cannot store progress*: "progress is kept locally only, and
/// the source detail screen states that progress for it does not sync". Which sources have a
/// mechanism is ``StoryArcCore/SourceKind/syncsReadingProgress``' answer and is asserted
/// beside it in `StoryArcCoreTests`; what is asserted here is that this screen asks the
/// question at all, because a test of the predicate alone stays green when the row is deleted
/// from the view — which is the state the app was already in.
///
/// **The view's own body is built and read, not its source file.** The first version of this
/// suite matched `SourceDetail.swift` as text, and a review broke it in the most ordinary way
/// a row goes: the footer's body was replaced with `EmptyView()` and the two matched lines
/// were left in place behind `//`. Every test stayed green, and so did `scripts/ios-strings.mjs`,
/// which is a regex over Swift source and says so in its own header. A guard that a comment
/// satisfies is not a guard.
///
/// A SwiftUI `body` is an eagerly built value — `List`, `Section` and the two `ViewBuilder`
/// closures are all evaluated when `body` is asked for — so the footer's `Text`, or its
/// absence, is in that value on the host with no simulator and no rendering. `Text` keeps the
/// `LocalizedStringKey` it was given, and [lookups(for:)] walks the value and collects every
/// one. That is still short of a screenshot: it proves the sentence is looked up under the
/// right condition, never that the pixels were legible at the largest text size. The
/// screenshot AGENTS.md §6 asks for is what closes *that* gap. Android answers the same
/// question by composing `SourceDetailScreen` under Robolectric.
@MainActor
@Suite("The iOS source detail screen states when progress stays local")
struct SourceProgressNoteTests {

    /// The key the note is drawn from, and the field that proves the walk still works.
    private static let note = "sources.detail.progressLocalOnly"
    private static let anyField = "sources.detail.status"

    /// Every localization key `SourceDetail` looks up for one source.
    ///
    /// Reflection into SwiftUI's own value tree, which is a deliberate cost. `Text` stores
    /// either a verbatim string or an `AnyTextStorage`; the localized subclass holds a
    /// `LocalizedStringKey`, whose single stored property is the key. Nothing public exposes
    /// it, so `Mirror` is the only way in without a simulator or a third-party inspector.
    ///
    /// It fails safely in the one direction that matters. If a future SDK renames that
    /// property the walk returns nothing, and every test below that expects a key fails
    /// loudly; the two that expect *no* key would pass on an empty set, so both also assert
    /// [anyField] is still there. Depth is capped and class instances are visited once,
    /// because the tree holds bundles, key paths and colours that refer back into it.
    private static func lookups(for source: Source, isRemovable: Bool = true) -> Set<String> {
        let view = SourceDetail(
            source: source,
            diagnosis: SourceDiagnosis.of(
                source, itemCount: 3, downloads: [], isRemovable: isRemovable
            ),
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

    private static func source(_ kind: SourceKind) -> Source {
        Source(displayName: "Fixture", kind: kind, state: .connected)
    }

    @Test(
        "A folder, a share and an OPDS catalogue each say a position stays on this device",
        arguments: [SourceKind.localFolder, .networkShare, .opdsCatalog]
    )
    func theNoteIsDrawn(for kind: SourceKind) {
        // A share is the kind the gap cost most: it is a server the reader signed in to,
        // which is exactly the shape of a source they would expect to carry their place
        // across devices. It cannot — an SMB share is files on a disk.
        let keys = Self.lookups(for: Self.source(kind))
        #expect(keys.contains(Self.note), "\(kind) looked up \(keys.sorted())")
    }

    @Test("Kavita does not, because for Kavita it would be false")
    func kavitaSaysNothing() {
        // The other half of the claim. A sentence shown on every source would be no
        // information at all, and on the one source that does sync it would be a lie.
        let keys = Self.lookups(for: Self.source(.kavitaServer))
        #expect(keys.contains(Self.anyField), "the walk found nothing: \(keys.sorted())")
        #expect(!keys.contains(Self.note), "Kavita looked up \(keys.sorted())")
    }

    @Test("\"On this device\" does not, because it is the device")
    func theImportedSourceSaysNothing() {
        // `ImportedCopies` registers "On this device" as a real source of kind `.localFolder`
        // the moment a reader imports a file, and its detail screen is reachable from
        // Settings › Your libraries like any other. On the kind alone the sentence renders
        // there and tells a reader that the device cannot store progress and that their place
        // is kept on the device.
        let device = Source(
            id: ImportedCopies.sourceID,
            displayName: "On this device",
            kind: .localFolder,
            state: .connected
        )
        let keys = Self.lookups(for: device, isRemovable: false)
        #expect(keys.contains(Self.anyField), "the walk found nothing: \(keys.sorted())")
        #expect(!keys.contains(Self.note), "On this device looked up \(keys.sorted())")
    }
}
