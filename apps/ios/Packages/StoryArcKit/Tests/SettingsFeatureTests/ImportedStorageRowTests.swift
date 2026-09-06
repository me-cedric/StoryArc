import Foundation
import SwiftUI
import Testing

@testable import SettingsFeature

import Persistence
import StoryArcCore

/// The storage screen states what the imported copies weigh.
///
/// `local-library`'s *Importing* scenario ends "**AND** the app reports the space used", and
/// `offline-downloads`' *Storage view* asks for the total "broken down by source". "On this
/// device" is a source. `LibraryModel.importedBytes` answered that question from the day it
/// was written and no screen on either platform read it, so the figure reached a reader only
/// inside the downloads total, under a label that says downloads.
///
/// **The view's own body is built and read, not its source file**, for the reason
/// `DownloadsHeldNoteTests` gives: a row commented out satisfies a text match and fails a
/// reader. That suite's walk, with the drawn figure collected as well as the key — a label
/// with no number beside it is the row failing quietly.
///
/// Android's `ImportedStorageRowTest` composes `DownloadsGroup` to answer the same three
/// claims.
@MainActor
@Suite("The iOS storage screen states the imported copies")
struct ImportedStorageRowTests {

    /// A key every rendering of this screen looks up, so a walk that found nothing at all
    /// cannot be read as "the row is absent".
    private static let anyField = "downloads.total"

    /// Every localization key and every literal string `DownloadsSettings` draws.
    ///
    /// Reflection into SwiftUI's own value tree, exactly as `DownloadsHeldNoteTests` does it
    /// and for the same reason: `Text` keeps the `LocalizedStringKey` or the string it was
    /// given, and nothing public exposes either.
    private static func drawn(importedBytes: Int64, bytesOnDisk: Int64 = 129_000) -> Set<String> {
        let view = DownloadsSettings(
            bytesOnDisk: bytesOnDisk,
            importedBytes: importedBytes,
            downloads: DownloadLibrary(),
            settings: .constant(AppSettings())
        )

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

    @Test("A device holding imported copies is told what they weigh")
    func theRowIsDrawn() {
        let drawn = Self.drawn(importedBytes: 512_000)

        #expect(drawn.contains("downloads.imported"), "drawn \(drawn.sorted())")
        #expect(drawn.contains(DownloadStore.formatted(512_000)), """
            The row was drawn with no figure beside it, which tells a reader nothing.
            """)
    }

    @Test("The figure is written the way every other screen writes one")
    func oneHelper() {
        // `DownloadStore.formatted` exists because the same figure was written two ways one
        // screen apart. A new row composing its own is how that comes back.
        let drawn = Self.drawn(importedBytes: 512_000)

        #expect(!drawn.contains { $0.lowercased().contains("zero") }, "drawn \(drawn.sorted())")
        #expect(drawn.contains(DownloadStore.formatted(512_000)), "drawn \(drawn.sorted())")
    }

    @Test("A device holding no imported copies is not told about them")
    func nothingWhenNothingIsImported() {
        // The other half of the claim. A row of zero drawn for a reader who has never
        // imported a file is the noise every other conditional row on this screen avoids.
        let drawn = Self.drawn(importedBytes: 0)

        #expect(drawn.contains(Self.anyField), "the walk found nothing: \(drawn.sorted())")
        #expect(!drawn.contains("downloads.imported"), "drawn \(drawn.sorted())")
    }
}
