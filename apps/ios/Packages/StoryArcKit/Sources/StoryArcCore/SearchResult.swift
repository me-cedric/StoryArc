/// One row of an answer to a search, whoever answered it.
///
/// What the row *says*: a kind, a title, a line under it, and where a tap leads. It carries
/// no source, because the domain has no registry to name one with — the search pairs each
/// row with the library that supplied it in `LibraryFeature`'s `FoundRow`, which is what
/// `library-browsing`'s *Mixed local and server search* means by "each labelled with its
/// source".
///
/// Android's `SearchResult` mirrors it field for field.
public struct SearchResult: Sendable, Equatable, Hashable, Identifiable {
    /// What makes this row *this* row, for a list that must not lose one.
    ///
    /// A publication the device holds is identified by the publication, so two different
    /// books that happen to share a title are two rows. Everything else is identified by
    /// what it says, because that is all a server gave us.
    ///
    /// Not unique on its own once two libraries have answered — two servers holding the same
    /// title send rows this cannot tell apart. `FoundRow.id` puts the origin in front of it
    /// for exactly that reason, and that is what a list is keyed on.
    public var id: String {
        if let publicationID { return "held:\(publicationID)" }
        return "away:\(foldKey)"
    }

    /// What makes two rows *the same thing to a reader*.
    ///
    /// The kind and the words, and nothing else: two answerers do not share identifiers, and
    /// a reader looking at two identical rows does not care that they were keyed
    /// differently. Used only by the merge, and only ever within one library — see
    /// `SearchListing.appending(_:to:for:)`, which is where the rule that a duplicate is
    /// never folded *across* libraries is kept.
    public var foldKey: String { "\(kind.rawValue):\(title.lowercased())" }

    /// Which heading this appears under.
    public let kind: MatchKind

    /// What the row says.
    public let title: String

    /// The line under it — a series, an author, a year. Where it came from is a separate
    /// line, drawn from the origin the search paired this with.
    public let detail: String?

    /// The publication on this device this row opens, when the device holds it.
    ///
    /// Set for everything the local index answered. `nil` means the row leads to ``route``
    /// instead — and a remote row never gets one, because the publication page resolves
    /// against the library's own set and would open on "this one is gone".
    public let publicationID: String?

    /// Where the row leads when the device does not hold it.
    public let route: SearchRoute?

    public init(
        kind: MatchKind,
        title: String,
        detail: String? = nil,
        publicationID: String? = nil,
        route: SearchRoute? = nil
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.publicationID = publicationID
        self.route = route
    }

    /// Whether tapping this row leads anywhere.
    ///
    /// A person and a tag are names a server matched, not places: a row that looked
    /// tappable and did nothing would be worse than a row that plainly is not.
    public var isOpenable: Bool { publicationID != nil || route != nil }
}

extension SearchResult {
    /// A publication the device holds, as a row.
    ///
    /// The detail line is the series, or failing that the author: the two things that tell
    /// a reader which "Volume 1" they are looking at. Never the library it came from — that
    /// is the origin's own line, and `FoundRow` is what pairs the two.
    public init(_ publication: Publication, kind: MatchKind) {
        self.init(
            kind: kind,
            title: publication.displayTitle,
            // The series only where it says something the title does not. A standalone whose
            // series was inferred from its own filename — `Broken Transfer.cbz` has a series
            // equal to its own title — would otherwise make the row repeat itself, title
            // above and title below, and fall through to neither the series nor the author.
            // The bare series rather than the composed line, because that is what the row
            // has always drawn; `seriesLine(for:)`'s composed overload belongs to the
            // captions that draw a number.
            detail: seriesLine(series: publication.series, title: publication.displayTitle)
                ?? publication.authors.first,
            publicationID: publication.id
        )
    }
}

/// Where a row that is not on this device leads.
///
/// The key is opaque here on purpose — a Kavita series number and a catalogue entry's
/// identifier are not the same kind of thing, and this type has no business knowing which
/// it is holding. Whoever answered the search knows how to read its own key back.
public struct SearchRoute: Sendable, Equatable, Hashable {
    /// Which configured library can open it. Used to route, never to render.
    public let sourceID: String
    public let key: String

    public init(sourceID: String, key: String) {
        self.sourceID = sourceID
        self.key = key
    }
}
