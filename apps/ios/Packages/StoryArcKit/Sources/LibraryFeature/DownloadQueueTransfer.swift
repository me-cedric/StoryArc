public import Foundation
public import Catalogue
internal import Formats
public import StoryArcCore

/// Moving one download's bytes, from the request to the file or the failure.
///
/// Split out of ``DownloadQueue`` for the same reason ``DownloadQueueHolds`` and
/// ``DownloadQueueOutcome`` were: that file is at the 400-line cap this project enforces, and
/// the seam was already there. ``DownloadQueueHolds`` decides whether the queue may run,
/// ``DownloadQueueOutcome`` decides what a finished transfer becomes, and this is the transfer
/// itself — the retry loop, the address rules and the one attempt they share.
extension DownloadQueue {
    func start(_ download: Download, seriesHint: String?) {
        library = library.marking(download.id, as: .running)
        running[download.id] = Task { [weak self] in
            await self?.transfer(download, seriesHint: seriesHint)
        }
    }

    func transfer(_ download: Download, seriesHint: String?) async {
        while !Task.isCancelled {
            if let file = await one(download, seriesHint: seriesHint) {
                running[download.id] = nil
                finish(download.id, with: file)
                pump()
                return
            }
            // `offline-downloads`: "a failed verification re-queues it once". The bytes
            // arrived and were not a book, so ``one(_:seriesHint:)`` put the download back
            // in the queue rather than failing it. Left there for the pump to start again,
            // and — the part that matters — nobody waiting to *read* it is told it failed,
            // because it has not.
            if library[download.id]?.state == .queued {
                running[download.id] = nil
                pump()
                return
            }
            guard let failed = library[download.id], DownloadLibrary.shouldRetry(failed),
                  case let .failed(_, attempts) = failed.state
            else { break }
            try? await Task.sleep(for: DownloadLibrary.backoff(afterAttempts: attempts))
        }
        running[download.id] = nil
        finish(download.id, with: nil)
        pump()
    }

    /// One attempt, with no opinion about whether there will be another.
    func one(
        _ download: Download,
        seriesHint: String?
    ) async -> URL? {
        do {
            // Through the background session rather than an ordinary request:
            // `offline-downloads` wants a backgrounded transfer to continue "as far as the
            // platform allows", and on iOS that is what allows it.
            // The same rule ``OpdsClient`` applies, because this is the same kind of
            // address: one the catalogue chose. An acquisition href off the source's own
            // origin is fetched without the credential, and one that steps down to
            // cleartext is not fetched at all.
            guard OpdsOrigin.isFetchable(download.remote) else { throw OpdsError.refusedAddress }
            let home = origin ?? OpdsOrigin(url: download.remote)
            if home?.downgrades(download.remote) == true { throw OpdsError.refusedAddress }

            var request = URLRequest(url: download.remote)
            if let credential = credential(download.id), home?.admits(download.remote) == true {
                request.setValue(credential.header, forHTTPHeaderField: "Authorization")
            }
            let temporary = try await transfers.download(request, named: download.id)
            return try await land(download, from: temporary, seriesHint: seriesHint)
        } catch let error as PublicationIndexer.IndexError {
            // Indexing *is* the verification, so this is where `offline-downloads`' "a
            // failed verification re-queues it once" is answered — and the two ways it can
            // fail get different answers.
            //
            // **An unsupported format is not a failed verification.** The bytes are
            // exactly what the server holds; the app simply has no decoder for them.
            // Fetching them again produces the same format, so this is terminal and always
            // was.
            //
            // **Unreadable bytes are a failed verification.** A truncated archive, a
            // central directory that is not there, a file that stops mid-entry — the
            // likeliest cause is the transfer rather than the publication, and one more
            // fetch is the cheapest way to find out. Exactly one: a second identical
            // result is the server's answer, and asking a third time is asking a question
            // already answered twice.
            if case let .unsupported(format) = error {
                fail(
                    download.id,
                    reason: String(
                        format: String(
                            localized: "catalogue.acquire.unsupported",
                            bundle: .module,
                            locale: .storyArc
                        ),
                        format
                    ),
                    retryable: false
                )
            } else {
                failVerification(
                    download.id,
                    reason: String(
                        localized: "catalogue.acquire.unreadable",
                        bundle: .module,
                        locale: .storyArc
                    )
                )
            }
        } catch let error as OpdsError {
            fail(download.id, reason: CatalogueMessages.describe(error), retryable: error.isTransient)
        } catch {
            fail(download.id, reason: CatalogueMessages.reachability(error))
        }
        return nil
    }
}
