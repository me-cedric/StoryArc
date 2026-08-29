internal import StoryArcCore

/// Which acquisition to take, which the reader could choose instead, and which the app has
/// to refuse.
///
/// Beside the feed rather than beside the download queue: the question is about a *catalogue
/// entry*, and the answer is asked long before anything is downloaded — the grid asks it to
/// decide whether a cell is tappable, and the detail screen asks it to lay out the formats
/// as a choice.
public enum CatalogueAcquisition {
    /// `opds-catalog`: "the app selects EPUB for reflowable reading and lets the user choose
    /// another format". EPUB first, then the comic containers, then PDF — a comic offered as
    /// both CBZ and PDF is a comic, and the PDF is a worse copy of it.
    public static func best(of entry: OpdsEntry) -> OpdsAcquisition? {
        readable(in: entry).min { rank($0) < rank($1) }
    }

    /// Every acquisition this app could act on, best first.
    ///
    /// Ordered by what the app would pick rather than by what the feed listed, because this
    /// is what the detail screen shows as the choice: the default belongs at the top of it,
    /// and a reader scanning down the list is scanning down a ranking.
    public static func readable(in entry: OpdsEntry) -> [OpdsAcquisition] {
        entry.acquisitions
            .enumerated()
            .filter { _, acquisition in
                guard acquisition.kind.isFetchable else { return false }
                return PublicationFormat(mediaType: acquisition.mediaType)?.isOpenable == true
            }
            // Sorted with the feed's own order as the tie-break, because `sorted` is not
            // stable: two EPUBs from one entry would otherwise swap places between runs,
            // and the one that opens by default would swap with them.
            .sorted { left, right in
                let (first, second) = (rank(left.element), rank(right.element))
                return first == second ? left.offset < right.offset : first < second
            }
            .map(\.element)
    }

    /// The formats offered as a plain download that this app cannot open.
    ///
    /// `opds-catalog`: an entry with nothing readable is "listed but marked unreadable,
    /// naming the formats offered". These are the names — a media type verbatim when it maps
    /// to no format at all, and CB7 when it maps to one the decoder does not exist for.
    public static func unreadable(in entry: OpdsEntry) -> [String] {
        let offered = entry.acquisitions
            .filter { $0.kind.isFetchable }
            .filter { PublicationFormat(mediaType: $0.mediaType)?.isOpenable != true }
            .map { PublicationFormat(mediaType: $0.mediaType)?.displayName ?? $0.mediaType }
            .filter { !$0.isEmpty }
        // Ordered and deduplicated: a server that offers the same type twice offers one
        // format, and a list that says "PDF, PDF" reads as a bug in the app.
        return Array(Set(offered)).sorted()
    }

    /// The ways of obtaining this the app will not follow, each named once.
    ///
    /// `opds-catalog`: an indirect acquisition — "an OPDS-LCP or borrow flow" — makes the app
    /// "state that the acquisition type is not supported rather than failing silently". A
    /// screen can only state it if something hands it the list, so this is that list.
    public static func unsupported(in entry: OpdsEntry) -> [OpdsAcquisition.Kind] {
        var seen: [OpdsAcquisition.Kind] = []
        for acquisition in entry.acquisitions where !acquisition.kind.isFetchable {
            if !seen.contains(acquisition.kind) { seen.append(acquisition.kind) }
        }
        return seen
    }

    private static func rank(_ acquisition: OpdsAcquisition) -> Int {
        switch PublicationFormat(mediaType: acquisition.mediaType) {
        case .epub: 0
        case .cbz, .cbt, .cbr: 1
        case .pdf: 2
        default: 3
        }
    }
}
