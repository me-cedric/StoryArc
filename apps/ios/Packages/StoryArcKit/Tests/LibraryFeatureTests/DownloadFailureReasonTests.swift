import Foundation
import Testing

@testable import LibraryFeature
import Catalogue
import Persistence
import StoryArcCore

/// A stored failure reason keeps no language — `localization` 15.9.
///
/// The queue used to compose `offline-downloads`' "plain-language reason" at the moment of
/// failure and write that sentence into the record. The record outlives the moment: a reader
/// who switched the app to French afterwards kept reading an English refusal on every failed
/// row, for ever. Android asserts the same in `DownloadQueueFailureLanguageTest.kt`.
@Suite("What a failed download's record keeps")
@MainActor
struct DownloadFailureReasonTests {
    private func store() throws -> DownloadStore {
        let name = "download-failure-reason-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory
            .appending(path: name, directoryHint: .isDirectory)
        return DownloadStore(defaults: defaults, directory: directory)
    }

    private func download(failing reason: String) -> Download {
        Download(
            id: "hl09",
            title: "Harbour Lights 09",
            remote: URL(string: "https://example.invalid/hl09.epub")!,
            mediaType: "application/epub+zip",
            state: .failed(reason: reason, attempts: 3)
        )
    }

    @Test("A reason with an argument comes back exactly as it went in")
    func argumentsSurviveTheRoundTrip() {
        for reason: DownloadFailure in [
            .unsupportedFormat("7-Zip"),
            .notAFeed("text/plain"),
            .notAFeed(nil),
            .http(503),
            .unreadable,
            .unknown,
        ] {
            #expect(DownloadFailure(stored: reason.stored) == reason)
        }
    }

    @Test("The queue writes a code onto the record, not a sentence")
    func theRecordKeepsACode() throws {
        let queue = DownloadQueue(store: try store(), settings: { AppSettings() })
        queue.record(download(failing: ""))

        queue.fail("hl09", reason: CatalogueMessages.reason(.refusedAddress))

        guard case let .failed(reason, _) = queue.library["hl09"]?.state else {
            Issue.record("The download is not failed.")
            return
        }
        #expect(reason == DownloadFailure.refusedAddress.stored)
        // The sentence is still reachable, and is chosen at the moment the row is drawn.
        #expect(DownloadFailureWords.sentence(stored: reason) == CatalogueMessages.describe(.refusedAddress))
    }

    @Test("A sentence an older build stored is read as the generic reason")
    func anOlderBuildsSentenceBecomesTheGenericReason() throws {
        let store = try store()
        // Exactly what a build before this change wrote: the English sentence of the day.
        store.save(DownloadLibrary(downloads: [download(failing: "The server did not answer in time.")]))

        guard case let .failed(reason, attempts) = store.library()["hl09"]?.state else {
            Issue.record("The download did not come back failed.")
            return
        }
        #expect(reason == DownloadFailure.unknown.stored)
        // The count is the record's and is not what the migration is about.
        #expect(attempts == 3)
        let drawn = DownloadFailureWords.sentence(stored: reason)
        #expect(drawn == DownloadFailureWords.sentence(.unknown))
        // And not the sentence that was stored, which is the whole defect: it is in the
        // language the app spoke that day and nothing could translate it.
        #expect(drawn != "The server did not answer in time.")
        #expect(!drawn.isEmpty)
    }
}
