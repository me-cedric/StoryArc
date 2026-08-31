internal import Foundation

/// OPDS 2.0, which is a Readium Web Publication Manifest with catalogue groups.
///
/// Decoded against the wire shapes in ``OpdsWireFeed`` and then mapped, rather than making
/// ``OpdsFeed`` decodable directly. The two dialects would otherwise both have to fit one
/// set of coding keys, and neither would read as the format it is.
enum OpdsJson {
    static func parse(_ data: Data, baseURL: URL) throws -> OpdsFeed {
        let wire: OpdsWireFeed
        do {
            wire = try JSONDecoder().decode(OpdsWireFeed.self, from: data)
        } catch {
            throw OpdsError.malformed(reason: String(describing: error))
        }
        // A JSON document with no metadata is some other API's response, not a catalogue.
        guard let metadata = wire.metadata else {
            throw OpdsError.notAFeed(received: .unrecognised(contentType: "application/json"))
        }

        let resolve = { (href: String) in OpdsDocument.resolve(href, relativeTo: baseURL) }

        // Groups hold the same three things a feed does. A named one becomes a section of
        // its own; an unnamed one is poured into the feed, because a section with no title
        // is a heading nobody can read. OPDS 2.0 uses groups where OPDS 1.2 used separate
        // feeds.
        let wireGroups = wire.groups ?? []
        let unnamed = wireGroups.filter { $0.metadata?.title == nil }

        let navigation = ((wire.navigation ?? []) + unnamed.flatMap { $0.navigation ?? [] })
            .compactMap { section($0, resolve: resolve) }

        let publications = ((wire.publications ?? []) + unnamed.flatMap { $0.publications ?? [] })
            .compactMap { entry($0, resolve: resolve) }

        let groups = wireGroups.compactMap { group($0, resolve: resolve) }

        let facets = (wire.facets ?? []).flatMap { facet in
            facet.links.compactMap { link -> OpdsFacet? in
                guard let href = resolve(link.href), let title = link.title else { return nil }
                return OpdsFacet(
                    group: facet.metadata?.title ?? title,
                    title: title,
                    href: href,
                    count: link.properties?.numberOfItems
                )
            }
        }

        let links = wire.links ?? []
        let search = links.first { $0.rel?.contains("search") == true }
        let isTemplated = search?.templated == true

        return OpdsFeed(
            title: metadata.title,
            navigation: navigation,
            publications: publications,
            groups: groups,
            facets: facets,
            next: links.first { $0.rel?.contains("next") == true }.flatMap { resolve($0.href) },
            // A templated link says so, and its href holds the braces. One that does not is
            // a description document, the same as in OPDS 1.2.
            searchTemplate: isTemplated
                ? search.flatMap { OpdsDocument.resolveTemplate($0.href, relativeTo: baseURL) }
                : nil,
            searchDescription: isTemplated ? nil : search.flatMap { resolve($0.href) }
        )
    }

    /// A named group, which the browser shows as a section of its own.
    ///
    /// Nil for a group with no title: there is nothing to head it with, and its contents
    /// have already been poured into the feed by the caller.
    private static func group(
        _ wire: OpdsWireGroup,
        resolve: (String) -> URL?
    ) -> OpdsGroup? {
        guard let title = wire.metadata?.title else { return nil }
        return OpdsGroup(
            title: title,
            navigation: (wire.navigation ?? []).compactMap { section($0, resolve: resolve) },
            publications: (wire.publications ?? []).compactMap { entry($0, resolve: resolve) },
            // `self` is where the standard puts "the rest of this group", and a group that
            // points at itself is the one case where following a self link is not a loop:
            // the group is an excerpt of the page it names.
            more: wire.links?
                .first { $0.rel?.contains("self") == true }
                .flatMap { resolve($0.href) }
        )
    }

    /// A navigation link, which is a section when it has somewhere to go and a name to
    /// show. Shared by the feed's own navigation and by every group's.
    private static func section(
        _ link: OpdsWireLink,
        resolve: (String) -> URL?
    ) -> OpdsSection? {
        guard let href = resolve(link.href), let title = link.title else { return nil }
        return OpdsSection(title: title, href: href, count: link.properties?.numberOfItems)
    }

    private static func entry(
        _ wire: OpdsWirePublication,
        resolve: (String) -> URL?
    ) -> OpdsEntry? {
        guard let title = wire.metadata.title else { return nil }
        // The largest declared image is the cover and the smallest is the thumbnail. Where
        // only one is offered it serves as both, which is better than showing nothing in a
        // grid while a detail screen has art.
        let images = (wire.images ?? []).sorted { ($0.width ?? 0) > ($1.width ?? 0) }

        return OpdsEntry(
            id: wire.metadata.identifier ?? title,
            title: title,
            authors: wire.metadata.author?.names ?? [],
            summary: wire.metadata.description,
            series: wire.metadata.belongsTo?.series?.names.first,
            seriesIndex: wire.metadata.belongsTo?.series?.position,
            updated: wire.metadata.modified.flatMap(OpdsDates.parse),
            cover: images.first.flatMap { resolve($0.href) },
            thumbnail: images.last.flatMap { resolve($0.href) },
            acquisitions: (wire.links ?? []).compactMap { acquisition($0, resolve: resolve) }
        )
    }

    private static func acquisition(
        _ link: OpdsWireLink,
        resolve: (String) -> URL?
    ) -> OpdsAcquisition? {
        guard let href = resolve(link.href) else { return nil }
        let relations = link.rel ?? []
        // OPDS 2.0 lets an acquisition link carry no relation at all, in which case being
        // in `links` with a readable type is the whole signal.
        guard let kind = relations.lazy.compactMap(OpdsAcquisition.Kind.named).first
            ?? (relations.isEmpty ? OpdsAcquisition.Kind.direct : nil)
        else { return nil }
        return OpdsAcquisition(href: href, mediaType: link.type ?? "", kind: kind, length: link.size)
    }
}
