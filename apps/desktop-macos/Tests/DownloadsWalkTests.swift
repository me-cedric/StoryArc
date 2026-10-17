import Catalogue
import Foundation
import LibraryFeature
import Persistence
import StoryArcCore
import Testing

@testable import StoryArc

extension WindowWalks {
    /// Tasks 3.11 and 3.12 against the OPDS mock's slow route, which trickles a comic out over
    /// several seconds so a download can be caught on its way.
    ///
    /// The quit walk is a restoration assertion, as wave 2's window walk was: the test cannot
    /// end the process it runs in, so it takes the quit's own path (`MacQuit` with the reader
    /// agreeing), checks what a quit leaves on disk, then builds the coordinator a relaunch
    /// builds, over the same stores, and lets it resume.
    @MainActor
    @Suite("Downloads walk")
    struct DownloadsWalkTests {
        private static let slowSeconds = 6

        private func entry(_ name: String) throws -> (OpdsEntry, OpdsAcquisition) {
            let address = "http://127.0.0.1:\(MockServers.opdsPort)/files/Fine%20Print.cbz"
            let url = try #require(URL(string: "\(address)?slow=\(Self.slowSeconds)&walk=\(name)"))
            let acquisition = OpdsAcquisition(href: url, mediaType: "application/vnd.comicbook+zip", kind: .open)
            let entry = OpdsEntry(
                id: "walk-\(name)-\(UUID().uuidString)", title: "Fine Print (\(name))", acquisitions: [acquisition]
            )
            return (entry, acquisition)
        }

        private func suite() -> UserDefaults {
            UserDefaults(suiteName: "app.storyarc.mac.tests.downloads.\(UUID().uuidString)") ?? .standard
        }

        @Test("A quit during a download asks, pauses with the partial kept, and the next launch resumes it",
              .enabled(if: MockServers.isOpdsUp, "the OPDS mock is not running (pnpm opds)"))
        func quitAndRelaunch() async throws {
            let defaults = suite()
            let path = FakePathObserver()
            let downloads = MacDownloads(
                queue: .shared(), monitor: MeteredMonitor(observer: path), defaults: defaults
            )
            let (entry, acquisition) = try entry("quit")
            downloads.enqueue(entry, using: acquisition, sourceID: nil)
            let id = downloads.queue.downloadID(for: entry.id, sourceID: nil)
            defer { downloads.cancel(id) }

            let started = await Walk.until(.seconds(10)) {
                (downloads.queue.library[id]?.downloadedBytes ?? 0) > 0 ? true : nil
            }
            #expect(started == true, "the slow download never moved")
            #expect(downloads.isTransferring)

            var asked = false
            #expect(MacQuit(downloads: downloads, confirm: { asked = true; return true }).shouldQuit())
            #expect(asked, "the quit did not ask about the download")

            // What the next launch reads: the record paused, its bytes counted, and the id kept.
            let onDisk = DownloadStore().library()[id]
            #expect(onDisk?.state == .paused(.byReader))
            #expect((onDisk?.downloadedBytes ?? 0) > 0, "the partial was not kept")
            #expect(defaults.stringArray(forKey: MacDownloads.pausedForQuitKey)?.contains(id) == true)
            let token = try #require(onDisk.map { DownloadStore().resumeData(of: $0) })
            let kept = await Walk.until(.seconds(5)) { FileManager.default.fileExists(atPath: token.path) ? true : nil }
            let bytes = onDisk?.downloadedBytes ?? 0
            ConformanceLog.note("quit during a download", "paused at \(bytes) bytes, resume token \(kept == true)")

            let relaunched = MacDownloads(
                queue: .shared(), monitor: MeteredMonitor(observer: FakePathObserver()), defaults: defaults
            )
            relaunched.resumeAfterLaunch()
            #expect(defaults.stringArray(forKey: MacDownloads.pausedForQuitKey) == nil)
            let finished = await Walk.until(.seconds(Double(Self.slowSeconds * 3))) {
                relaunched.queue.library[id]?.state == .finished ? true : nil
            }
            #expect(finished == true, "the resumed download did not finish")
            ConformanceLog.note(
                "relaunch after the quit",
                "finished \(finished == true), last attempt "
                    + (relaunched.queue.library[id]?.lastAttempt?.rawValue ?? "fresh")
            )
        }

        @Test("A link turning metered mid-download pauses what the rule holds, and an unmetered one resumes it",
              .enabled(if: MockServers.isOpdsUp, "the OPDS mock is not running (pnpm opds)"))
        func meteredMidDownload() async throws {
            let path = FakePathObserver()
            let downloads = MacDownloads(
                queue: .shared(), monitor: MeteredMonitor(observer: path), defaults: suite(), wifiOnly: { true }
            )
            path.report(.unmetered)
            let (entry, acquisition) = try entry("metered")
            // Queued the way a bulk download queues, not by the reader's hand on this row.
            downloads.queue.enqueue(entry, using: acquisition)
            let id = downloads.queue.downloadID(for: entry.id, sourceID: nil)
            defer { downloads.cancel(id) }
            _ = await Walk.until(.seconds(10)) { downloads.queue.library[id]?.state == .running ? true : nil }

            path.report(.metered)
            #expect(downloads.held.contains(id))
            #expect(downloads.queue.library[id]?.state == .paused(.byReader))
            #expect(downloads.queue.library[id].flatMap(downloads.reason(for:)) == .metered)
            #expect(!downloads.isTransferring, "a held download should not make a quit ask")

            // The connection comes back unmetered: the rule lets go of what it held, by itself.
            path.report(.unmetered)
            #expect(!downloads.held.contains(id))
            let resumed = await Walk.until(.seconds(10)) {
                downloads.queue.library[id]?.state.isActive == true ? true : nil
            }
            #expect(resumed == true, "the download did not resume on an unmetered link")

            // Metered again, and the reader starts this one by hand: it runs.
            path.report(.metered)
            #expect(downloads.held.contains(id))
            downloads.startByHand(id)
            #expect(downloads.queue.library[id]?.state.isActive == true, "Download Now did not start it")
            downloads.reconsider()
            #expect(!downloads.held.contains(id), "the rule held a download the reader started by hand")
            ConformanceLog.note("metered mid-download", "held on metered, by hand ran, resumed on unmetered")
        }
    }
}
