import Foundation
internal import Persistence
internal import Smb
import StoryArcCore

/// Continues a network share's walk past its first slice — the twin of
/// `continueReadingKavita` for a source with no page number of its own, only a frontier of
/// folders not yet listed.
///
/// `sources`' *More from a source than the library holds*: the first slice is what
/// `readServers()` already reads (``SmbContributor/firstSlice``); this is the rest of the
/// share's walk, continued from ``LibraryModel/smbQueues`` — the folders ``SmbContributor``
/// had not reached yet — rather than restarted at the share's root on every page, which a
/// share wider than ``SmbContributor/maxFolders`` could never walk past.
extension LibraryModel {
    func continueReadingShares() {
        for source in registry.sources where source.kind == .networkShare {
            guard partialSources[source.id] != nil else { continue }
            guard let page = SmbPage(source: source, credentials: CredentialStore()) else { continue }
            Task {
                await continueReadingShare(
                    source: source, client: SmbClient(address: page.address), address: page.address
                )
            }
        }
    }

    /// Reads one share's continuation until it finishes or a page refuses.
    ///
    /// **Stops and resumes cleanly when the source becomes unreachable.** A page that throws
    /// returns without touching ``partialSources`` or ``smbQueues``, so the very next
    /// ``continueReadingShares()`` asks for the same frontier again rather than losing the
    /// share's place — the same contract `continueReadingKavita` keeps for a server.
    private func continueReadingShare(source: Source, client: SmbClient, address: SmbAddress) async {
        await readSourceOnward(
            progress: { partialSources[source.id] },
            cursor: { smbQueues[source.id] ?? [address.path] },
            fetch: { queue in
                let page = await SmbContributor.page(source: source.id, client: client, address: address, queue: queue)
                return (page.slice, page.queue)
            },
            advance: { smbQueues[source.id] = $0 },
            land: { slice, step in
                landContinuedSlice(source: source.id, slice: slice, step: step)
                if case .continuing = step {} else { smbQueues.removeValue(forKey: source.id) }
            }
        )
    }
}

/// Merges one continued page into the library and into the shelf snapshot, and stores where
/// the read now stands. Shared by the share and the catalogue continuations — both land a
/// plain ``SourceSlice`` rather than a source-specific page type, unlike Kavita's own
/// `land`, which still needs the chapter list underneath its page.
extension LibraryModel {
    func landContinuedSlice(source sourceID: UUID, slice: SourceSlice, step: SourceReadStep) {
        for publication in slice.publications { _ = adopt(publication, from: sourceID) }
        if case .continuing(let next) = step {
            partialSources[sourceID] = next
        } else {
            partialSources.removeValue(forKey: sourceID)
        }
        cacheLibrary(claimsFreshness: false)
    }
}
