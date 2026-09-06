import Foundation
import SwiftUI
import Testing

@testable import SettingsFeature

import Persistence
import StoryArcCore

/// The downloads screen says why the queue is waiting, and what ends the wait.
///
/// `offline-downloads` requires a held queue to *say* what it is waiting for, because the three
/// situations have three different remedies. `DownloadQueue.held` answered the question from
/// the day it was written and nothing on either platform drew it: a reader whose queue was
/// waiting saw a list that had simply stopped.
///
/// Six claims. Each of the three reasons draws its own two sentences, and a queue that is not
/// held draws none of them — a screen that explains an absent problem is the noise this row
/// exists to avoid.
///
/// **The view's own body is built and read, not its source file**, for the reason
/// `SourceProgressNoteTests` gives at length: a row commented out satisfies a text match and
/// fails a reader. The walk is that suite's, and it proves the sentence is looked up under the
/// right condition — never that the pixels were legible. Android composes `DownloadsGroup`
/// under Robolectric to answer the same six claims.
@MainActor
@Suite("The iOS downloads screen names the hold and its remedy")
struct DownloadsHeldNoteTests {

    /// A key every rendering of this screen looks up, so a walk that found nothing at all
    /// cannot be read as "the sentence is absent".
    private static let anyField = "downloads.total"

    private static func download(_ id: String, state: Download.State, bytes: Int64 = 0) -> Download {
        Download(
            id: id,
            title: id,
            remote: URL(filePath: "/nowhere/\(id).cbz"),
            mediaType: "application/vnd.comicbook+zip",
            state: state,
            downloadedBytes: bytes
        )
    }

    /// Every localization key `DownloadsSettings` looks up for one library and one policy.
    ///
    /// Reflection into SwiftUI's own value tree, exactly as `SourceProgressNoteTests` does it
    /// and for the same reason: `Text` keeps the `LocalizedStringKey` it was given, and nothing
    /// public exposes it.
    private static func lookups(
        holding downloads: [Download],
        limit: Int64? = nil
    ) -> Set<String> {
        var settings = AppSettings()
        settings.maximumDownloadBytes = limit
        let view = DownloadsSettings(
            bytesOnDisk: 0,
            downloads: DownloadLibrary(downloads: downloads),
            settings: .constant(settings)
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

    @Test("A queue waiting for Wi-Fi says so, and says it starts again by itself")
    func waitingForWifi() {
        let keys = Self.lookups(holding: [
            Self.download("one", state: .paused(.waitingForWiFi)),
        ])

        #expect(keys.contains("downloads.paused.waitingForWiFi"), "looked up \(keys.sorted())")
        #expect(keys.contains("downloads.held.waitingForWifi.note"), "looked up \(keys.sorted())")
    }

    @Test("A queue held by a full device says so, and says it starts again by itself")
    func outOfSpace() {
        let keys = Self.lookups(holding: [
            Self.download("one", state: .paused(.outOfSpace)),
        ])

        #expect(keys.contains("downloads.paused.outOfSpace"), "looked up \(keys.sorted())")
        #expect(keys.contains("downloads.held.outOfSpace.note"), "looked up \(keys.sorted())")
    }

    @Test("A queue at the reader's own limit says so, and names both ways out")
    func storageFull() {
        let keys = Self.lookups(
            holding: [
                Self.download("kept", state: .finished, bytes: 2_000),
                Self.download("wanted", state: .queued),
            ],
            limit: 1_000
        )

        #expect(keys.contains("downloads.held.storageFull"), "looked up \(keys.sorted())")
        #expect(keys.contains("downloads.held.storageFull.note"), "looked up \(keys.sorted())")
    }

    @Test("A queue that is not held says nothing about being held")
    func nothingWhenRunning() {
        // The other half of every claim above. A sentence drawn whatever the queue is doing is
        // no information at all, and on a queue that is running it is false.
        let keys = Self.lookups(holding: [Self.download("one", state: .running)])

        #expect(keys.contains(Self.anyField), "the walk found nothing: \(keys.sorted())")
        for held in DownloadHold.allCases {
            #expect(!keys.contains(held.remedyKeyName), "a running queue looked up \(keys.sorted())")
        }
        #expect(!keys.contains("downloads.held.storageFull"), "looked up \(keys.sorted())")
    }

    @Test("An empty queue says nothing, whatever the limit is")
    func nothingWhenEmpty() {
        let keys = Self.lookups(holding: [], limit: 1)

        #expect(keys.contains(Self.anyField), "the walk found nothing: \(keys.sorted())")
        #expect(!keys.contains("downloads.held.storageFull"), "looked up \(keys.sorted())")
    }

    @Test("No two reasons share a sentence")
    func eachReasonHasItsOwnWords() {
        // Three remedies, three situations. Two reasons wearing one sentence would be a
        // stalled list that explains neither, which is the state this row was built to end.
        let states = Set(DownloadHold.allCases.map(\.stateKeyName))
        let remedies = Set(DownloadHold.allCases.map(\.remedyKeyName))

        #expect(states.count == DownloadHold.allCases.count)
        #expect(remedies.count == DownloadHold.allCases.count)
        #expect(states.isDisjoint(with: remedies))
    }
}

extension DownloadHold {
    /// The key behind ``stateKey``, as a string a test can compare.
    ///
    /// `LocalizedStringKey` hides the key it holds, and the walk above reads it by reflection.
    /// A second spelling of the same three keys would drift, so these two read the real
    /// properties back through the same mirror the walk uses.
    fileprivate var stateKeyName: String { Self.name(of: stateKey) }

    fileprivate var remedyKeyName: String { Self.name(of: remedyKey) }

    private static func name(of key: LocalizedStringKey) -> String {
        for child in Mirror(reflecting: key).children where child.label == "key" {
            if let name = child.value as? String { return name }
        }
        return ""
    }
}
