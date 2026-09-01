public import Foundation

/// What a publication being read aloud is divided into.
///
/// `design.md`'s table gives *part* one meaning per source: "a chapter marker, or a file" for
/// a narrated audiobook, "a resource in the publication's reading order" for read-aloud. The
/// narrated half is `AudiobookReader`'s; this is the other one.
///
/// **Strings rather than Readium types, and deliberately.** ADR-0005 keeps Readium behind
/// `StoryArcEpub`, and this rule has to be assertable by `pnpm test:ios` — which builds this
/// package on the host, with no simulator and no navigator. `SpokenSource` is the thin
/// adapter that reads Readium's `readingOrder` and `tableOfContents` and hands them over.
public enum SpokenParts {

    /// The reading order as parts, named by the publication's own navigation where it names
    /// them.
    ///
    /// - Parameters:
    ///   - hrefs: the reading order's resources, in playing order.
    ///   - titles: the navigation, as href → title. Entries pointing at an anchor inside a
    ///     resource are ignored: one of several anchors names none of the whole, which is
    ///     the rule `EpubReaderModel.currentEntry(in:)` already applies to marking the
    ///     reader's place. A name that is wrong everywhere is worse than no name.
    ///
    /// Never invents a duration. A synthesised voice does not know how long it will speak,
    /// and `design.md` requires a source that does not know to show "position without a total
    /// rather than inventing one" — a zero here would be a scrub control pinned at the end.
    public static func of(readingOrder hrefs: [String], titledBy titles: [String: String]) -> [PlaybackPart] {
        let named = titles.reduce(into: [String: String]()) { found, entry in
            let (href, title) = entry
            guard !title.isEmpty, !href.contains("#") else { return }
            let resource = resource(of: href)
            // First wins. A publication is free to point at one resource twice, and the
            // earlier entry is the one its own navigation puts first.
            if found[resource] == nil { found[resource] = title }
        }

        return hrefs.enumerated().map { index, href in
            PlaybackPart(index: index, title: named[resource(of: href)], duration: nil)
        }
    }

    /// An href without the query or fragment that a link or a search may have added.
    ///
    /// The same normalisation `TotalProgression.index(of:in:)` does, and for the same reason
    /// stated there: a locator's href is not always spelled the way the reading order spells
    /// it, and neither a query nor a fragment is part of a resource's identity.
    private static func resource(of href: String) -> String {
        String(href.prefix { $0 != "#" && $0 != "?" })
    }
}
