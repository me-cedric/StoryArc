import Foundation
import SwiftUI
import Testing

@testable import SettingsFeature

import StoryArcCore

/// The free-space sheet behind the storage-full hold (6.6): a largest-first list of finished
/// downloads, each removable, with the same ten-second undo every other removal offers.
///
/// **The view's own body is built and read, not its source file**, for the reason
/// `DownloadsHeldNoteTests` gives: a row commented out satisfies a text match and fails a
/// reader. The walk is that suite's.
@MainActor
@Suite("The iOS free-space sheet lists finished downloads largest first")
struct FreeSpaceSheetTests {

    private static func download(_ id: String, bytes: Int64) -> Download {
        Download(
            id: id,
            title: id,
            remote: URL(filePath: "/nowhere/\(id).cbz"),
            mediaType: "application/vnd.comicbook+zip",
            state: .finished,
            downloadedBytes: bytes
        )
    }

    /// Every literal string and localization key `FreeSpaceSheet` draws, in source order —
    /// `List` walks its rows in the order its own data gives them, so a title found before
    /// another in this set is drawn before it, which is what "largest first" means here.
    private static func drawn(_ downloads: [Download]) -> [String] {
        let sheet = FreeSpaceSheet(
            downloads: DownloadLibrary(downloads: downloads),
            onRemove: { _ in nil },
            onRestore: { _ in }
        )

        var found: [String] = []
        var seen: Set<ObjectIdentifier> = []

        func walk(_ value: Any, depth: Int) {
            guard depth < 40 else { return }
            if let text = value as? String {
                found.append(text)
                return
            }
            if type(of: value) == LocalizedStringKey.self {
                for child in Mirror(reflecting: value).children where child.label == "key" {
                    if let key = child.value as? String { found.append(key) }
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

        walk(sheet.body, depth: 0)
        return found
    }

    @Test("The biggest finished download is drawn before the smallest")
    func largestFirst() {
        let drawn = Self.drawn([
            Self.download("small", bytes: 1_000),
            Self.download("large", bytes: 9_000),
        ])

        let smallIndex = drawn.firstIndex(of: "small")
        let largeIndex = drawn.firstIndex(of: "large")

        #expect(smallIndex != nil && largeIndex != nil, "drawn \(drawn)")
        if let smallIndex, let largeIndex {
            #expect(largeIndex < smallIndex, "drawn in order \(drawn)")
        }
    }

    @Test("Nothing has been removed when the sheet first opens")
    func noUndoBarAtFirst() {
        // `removed` starts `nil`; the undo bar and the sentence it carries draw only after
        // a tap. A sheet that opens already announcing a removal would mislead before the
        // reader has touched anything.
        let drawn = Self.drawn([Self.download("one", bytes: 512_000)])

        #expect(!drawn.contains("downloads.removed %@"), "drawn \(drawn)")
        #expect(!drawn.contains("downloads.undo"), "drawn \(drawn)")
    }
}
