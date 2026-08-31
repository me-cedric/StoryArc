import Foundation
import Testing

@testable import StoryArcCore

/// `offline-downloads`: "its integrity is verified before it is marked available offline,
/// and a failed verification re-queues it once". Android's `DownloadVerificationTest`
/// asserts the same cases.
///
/// "Once" is the whole rule and the only number in it, so every case here is about the
/// boundary: the first corrupt arrival is re-fetched, the second is not, and the count it
/// keeps is not the one the network failures use.
@Suite("A failed verification is re-queued exactly once")
struct DownloadVerificationTests {
    private let unreadable = "the file could not be read"

    private func library(_ download: Download) -> DownloadLibrary {
        DownloadLibrary(downloads: [download])
    }

    private func download(
        verificationFailures: Int = 0,
        state: Download.State = .running
    ) -> Download {
        Download(
            id: "urn:one",
            title: "One",
            remote: URL(filePath: "/nowhere/one.cbz"),
            mediaType: "application/vnd.comicbook+zip",
            state: state,
            verificationFailures: verificationFailures
        )
    }

    @Test("The first corrupt arrival goes back in the queue")
    func firstFailureRequeues() {
        let after = library(download()).failingVerification("urn:one", reason: unreadable)

        #expect(after["urn:one"]?.state == .queued)
        #expect(after["urn:one"]?.verificationFailures == 1)
    }

    @Test("The second corrupt arrival is failed with the reason")
    func secondFailureIsFinal() {
        let after = library(download())
            .failingVerification("urn:one", reason: unreadable)
            .failingVerification("urn:one", reason: unreadable)

        #expect(
            after["urn:one"]?.state
                == .failed(reason: unreadable, attempts: DownloadLibrary.attemptLimit)
        )
        #expect(after["urn:one"]?.verificationFailures == 2)
    }

    @Test("A third is not asked for either")
    func thirdStaysFailed() {
        let after = (0..<3).reduce(library(download())) { each, _ in
            each.failingVerification("urn:one", reason: unreadable)
        }

        #expect(
            after["urn:one"]?.state
                == .failed(reason: unreadable, attempts: DownloadLibrary.attemptLimit)
        )
    }

    @Test("The re-queue is asked for before it is spent, and refused after")
    func predicateMatchesTheState() {
        #expect(DownloadLibrary.shouldRequeueAfterVerification(download()))
        #expect(!DownloadLibrary.shouldRequeueAfterVerification(download(verificationFailures: 1)))
        #expect(!DownloadLibrary.shouldRequeueAfterVerification(download(verificationFailures: 2)))
    }

    @Test("A verification failure does not spend a transfer attempt")
    func theTwoCountsAreSeparate() {
        // Three failed transfers and one corrupt arrival are four different events. Sharing
        // a counter would let a flaky network burn the verification's only second chance
        // before the bytes ever landed, or let three corrupt files be re-fetched.
        let flaky = library(download())
            .failing("urn:one", reason: "the server did not answer")
            .failing("urn:one", reason: "the server did not answer")

        let corrupt = flaky.failingVerification("urn:one", reason: unreadable)

        #expect(corrupt["urn:one"]?.state == .queued)
        #expect(corrupt["urn:one"]?.verificationFailures == 1)
        // And the other way: the transfer count is untouched by the corrupt arrival, so a
        // download that goes back to the network still has the attempt it had left.
        #expect(DownloadLibrary.shouldRetry(flaky["urn:one"] ?? download()))
    }

    @Test("Only the named download is touched")
    func othersAreLeftAlone() {
        var other = download()
        other = Download(
            id: "urn:two",
            title: "Two",
            remote: other.remote,
            mediaType: other.mediaType,
            state: .queued
        )
        let both = DownloadLibrary(downloads: [download(), other])

        let after = both.failingVerification("urn:one", reason: unreadable)

        #expect(after["urn:two"]?.verificationFailures == 0)
        #expect(after["urn:two"]?.state == .queued)
    }

    @Test("One, from the spec's own word")
    func theLimitIsOne() {
        #expect(DownloadLibrary.verificationLimit == 1)
    }
}
