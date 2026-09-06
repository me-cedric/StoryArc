import Foundation
import Testing

import Catalogue
@testable import LibraryFeature
import Persistence
import StoryArcCore

/// A transfer already running has to stop when the connection stops permitting it.
///
/// `offline-downloads`' *Wi-Fi only* says downloads "pause and state that they are waiting for
/// Wi-Fi, and resume automatically when it returns". `DownloadQueueWakingTests` proved the
/// second half. This suite is the first: `pump` only ever *started* transfers, so a reader who
/// set "download over Wi-Fi only", began a download on Wi-Fi and walked out of range kept
/// downloading over cellular. The setting they chose to protect their data stopped protecting
/// it the moment a transfer was running — which is the moment it costs them money.
///
/// The connection is injected through `NetworkCost.note(careful:cellular:)`, because an
/// `NWPath` cannot be built and a simulator reports Wi-Fi whatever the host is on.
///
/// Nothing here waits on a transfer, which goes to an address that resolves to nothing. The
/// claim is what the record says, and `pump` marks it before the transfer's task gets a turn:
/// both the queue and the test are on the main actor. `DownloadQueueWakingTests` makes the
/// same argument. Android asserts the same six claims in `DownloadQueueConnectionTest`.
@Suite("A running download stops when the connection stops permitting it")
@MainActor
struct DownloadQueueConnectionTests {

    /// A store of its own, in a fresh defaults suite and an empty directory.
    private func store(holding downloads: [Download]) throws -> DownloadStore {
        let name = "download-connection-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: name, directoryHint: .isDirectory)
        let store = DownloadStore(defaults: defaults, directory: directory)
        store.save(DownloadLibrary(downloads: downloads))
        return store
    }

    private func queued(id: String, fetched: Int64 = 0) -> Download {
        Download(
            id: id,
            title: "Harbour Lights 07",
            remote: URL(string: "https://example.invalid/hl07.epub")!,
            mediaType: "application/epub+zip",
            state: .queued,
            expectedBytes: 8_400_000,
            downloadedBytes: fetched
        )
    }

    /// A queue over that store, with the reader's Wi-Fi-only setting on.
    ///
    /// Nothing counts starts here: a report that repeats the last one starting no transfer is
    /// `NetworkCost`'s claim, and `DownloadQueueWakingTests` already counts it at the
    /// credential. What this suite counts is what the *record* does.
    private func queue(_ store: DownloadStore) -> DownloadQueue {
        DownloadQueue(store: store, settings: { AppSettings(downloadOverWifiOnly: true) })
    }

    /// The connection the queue is built on: cellular, which the monitor also assumes until it
    /// has an answer. Wi-Fi arrives as a report, the way it does on a device.
    private func onWifi(_ queue: DownloadQueue) {
        queue.network.note(careful: false, cellular: false)
    }

    private func onCellular(_ queue: DownloadQueue) {
        queue.network.note(careful: true, cellular: true)
    }

    @Test("A running transfer is paused when the connection becomes cellular")
    func runningStopsOnCellular() throws {
        let id = "running-stops-\(UUID().uuidString)"
        let queue = queue(try store(holding: [queued(id: id)]))
        onWifi(queue)
        #expect(queue.library[id]?.state == .running)

        onCellular(queue)

        #expect(
            queue.library[id]?.state == .paused(.waitingForWiFi),
            "The transfer kept running over cellular with Wi-Fi-only on."
        )
        #expect(queue.held == .waitingForWifi)
    }

    @Test("Pausing for the connection keeps the record and the bytes counted against it")
    func pausingKeepsWhatWasFetched() throws {
        // `offline-downloads` pauses rather than cancels, and "the bytes stay and the
        // transfer resumes from them". The record is what carries that count, so losing it
        // is losing the claim. What the app cannot yet do is resume *from* those bytes: no
        // Range request exists in either tree, so the next attempt starts at zero.
        let id = "bytes-survive-\(UUID().uuidString)"
        let queue = queue(try store(holding: [queued(id: id, fetched: 4_000_000)]))
        onWifi(queue)
        onCellular(queue)

        let paused = try #require(queue.library[id])
        #expect(paused.state == .paused(.waitingForWiFi))
        #expect(paused.downloadedBytes == 4_000_000)
        #expect(paused.expectedBytes == 8_400_000)
    }

    @Test("A paused download starts again when Wi-Fi returns, with no screen opened")
    func wifiReturnsResumes() throws {
        let id = "wifi-returns-\(UUID().uuidString)"
        let queue = queue(try store(holding: [queued(id: id)]))
        onWifi(queue)
        onCellular(queue)
        #expect(queue.library[id]?.state == .paused(.waitingForWiFi))

        onWifi(queue)

        #expect(queue.library[id]?.state == .running)
        #expect(queue.held == nil)
    }

    @Test("A download the reader allowed on cellular is not paused, and the grant is its own")
    func grantSurvivesTheHold() throws {
        // `offline-downloads` grants the override "for that item only". A hold that took the
        // granted download with it would refuse the reader the thing they just agreed to pay
        // for; a hold that released the queue behind it would spend the allowance they did
        // not agree to.
        let granted = "granted-\(UUID().uuidString)"
        let other = "other-\(UUID().uuidString)"
        let queue = queue(try store(holding: [queued(id: other)]))
        onWifi(queue)
        queue.enqueue(
            OpdsEntry(id: granted, title: "Harbour Lights 08"),
            using: OpdsAcquisition(
                href: URL(string: "https://example.invalid/hl08.epub")!,
                mediaType: "application/epub+zip",
                kind: .open
            ),
            overridingMeteredConnection: true
        )

        onCellular(queue)

        #expect(queue.library[granted]?.state != .paused(.waitingForWiFi))
        #expect(
            queue.library[other]?.state == .paused(.waitingForWiFi),
            "The grant released a download the reader never agreed to pay for."
        )
    }

    @Test("A queue relaunched on cellular is held again, and says so")
    func theHoldComesBack() throws {
        // The store carries no pause reason on either platform — a paused record comes back
        // queued — so this is not a restore. The queue asks the connection in its `init` and
        // reaches the same answer, which is what makes the reason true rather than remembered:
        // a phone relaunched on Wi-Fi shows no hold at all.
        let id = "relaunch-\(UUID().uuidString)"
        let store = try store(holding: [queued(id: id)])
        let first = queue(store)
        onWifi(first)
        onCellular(first)
        #expect(first.library[id]?.state == .paused(.waitingForWiFi))

        let second = queue(store)

        #expect(second.library[id]?.state == .paused(.waitingForWiFi))
        #expect(second.held == .waitingForWifi)
    }

    @Test("A connection that drops and returns ten times moves the row ten times, not more")
    func flappingDoesNotThrash() throws {
        // What ten transitions in ten seconds do, stated. Each *change* moves the record
        // exactly once, and nothing else: `NetworkCost` drops a report that says what the
        // last one said, and a pass that alters no record returns the same library, so the
        // store is not written at all — asserted on the rule itself in `DownloadWifiHoldTests`.
        //
        // So the reader pays ten writes for ten real transitions, and five fresh starts. With
        // no Range request anywhere in the app those five begin at zero, which is the part of
        // this that costs them data rather than disk.
        //
        // Read synchronously, with no yield: `NWPathMonitor` is live in a host test and
        // reports the machine's own connection whenever it likes, so a claim that waits is a
        // claim about the build machine.
        let id = "flapping-\(UUID().uuidString)"
        let queue = queue(try store(holding: [queued(id: id)]))
        var seen: [Download.State] = []

        for _ in 0..<5 {
            onWifi(queue)
            seen.append(try #require(queue.library[id]?.state))
            onCellular(queue)
            seen.append(try #require(queue.library[id]?.state))
        }

        let expected: [Download.State] = (0..<5)
            .flatMap { _ in [Download.State.running, .paused(.waitingForWiFi)] }
        #expect(seen == expected, "Ten transitions did not move the row exactly ten times.")
    }
}
