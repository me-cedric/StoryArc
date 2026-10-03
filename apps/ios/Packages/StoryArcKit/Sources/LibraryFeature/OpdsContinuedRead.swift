import Catalogue
import Foundation
internal import Persistence
import StoryArcCore

/// Continues an OPDS catalogue's feed past its first page, by following the feed's own
/// `next` link — the twin of `continueReadingShares` for a source with no walk of its own,
/// only a chain of pages the server hands forward one at a time.
///
/// `sources`' *More from a source than the library holds*: the first slice is one feed page,
/// which `readServers()` already reads; this is the rest of the chain, continued from
/// ``LibraryModel/opdsNext`` — the `next` link ``OpdsContributor`` last read — rather than
/// re-asked for the catalogue's root feed on every page, which would read the same first
/// page forever.
extension LibraryModel {
    func continueReadingCatalogues() {
        for source in registry.sources where source.kind == .opdsCatalog {
            guard partialSources[source.id] != nil else { continue }
            guard let page = CataloguePage(source: source, credentials: CredentialStore()) else { continue }
            Task { await continueReadingCatalogue(source: source, page: page) }
        }
    }

    /// Reads one catalogue's continuation until it finishes or a page refuses.
    ///
    /// **Stops and resumes cleanly when the source becomes unreachable.** A page that throws
    /// returns without touching ``partialSources`` or ``opdsNext``, so the very next
    /// ``continueReadingCatalogues()`` asks for the same link again rather than losing the
    /// catalogue's place.
    private func continueReadingCatalogue(source: Source, page: CataloguePage) async {
        await readSourceOnward(
            progress: { partialSources[source.id] },
            cursor: { opdsNext[source.id] },
            fetch: { url in
                guard let url, let fetched = try? await OpdsContributor.page(source: source.id, page: page, url: url)
                else { return nil }
                return (fetched.slice, fetched.next)
            },
            advance: { next in
                if let next { opdsNext[source.id] = next } else { opdsNext.removeValue(forKey: source.id) }
            },
            land: { slice, step in landContinuedSlice(source: source.id, slice: slice, step: step) }
        )
    }
}
