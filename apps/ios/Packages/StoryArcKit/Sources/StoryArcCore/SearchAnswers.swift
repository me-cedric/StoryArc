public import Foundation

/// One row of an answer to a search, whoever answered it.
///
/// `library-browsing`: results are grouped "by what the match is rather than by which
/// source answered", and "no result is labelled with the source that supplied it". So this
/// carries no server name, no icon and no badge — nothing a row could render that would
/// give away where it came from. It carries a ``route`` because opening a row still has to
/// go somewhere, and *routing* is not *labelling*: one is how the tap works, the other is
/// what the reader reads.
///
/// Android's `SearchResult` mirrors it field for field.
public struct SearchResult: Sendable, Equatable, Hashable, Identifiable {
    /// What makes this row *this* row, for a list that must not lose one.
    ///
    /// A publication the device holds is identified by the publication, so two different
    /// books that happen to share a title are two rows. Everything else is identified by
    /// what it says, because that is all a server gave us.
    public var id: String {
        if let publicationID { return "held:\(publicationID)" }
        return "away:\(foldKey)"
    }

    /// What makes two rows *the same thing to a reader*.
    ///
    /// The kind and the words, and nothing else: two answerers do not share identifiers,
    /// and a reader looking at two identical rows does not care that they were keyed
    /// differently. Used only by the merge, and only ever to drop a remote row — see
    /// ``SearchAnswers/answered(_:with:)``.
    public var foldKey: String { "\(kind.rawValue):\(title.lowercased())" }

    /// Which heading this appears under.
    public let kind: MatchKind

    /// What the row says.
    public let title: String

    /// The line under it — a series, an author, a year. Never where it came from.
    public let detail: String?

    /// The publication on this device this row opens, when the device holds it.
    ///
    /// Set for everything the local index answered, and for a remote row the device turns
    /// out to already hold. `nil` means the row leads to ``route`` instead.
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
    /// a reader which "Volume 1" they are looking at. Never the library it came from, per
    /// the requirement this whole type exists to keep.
    public init(_ publication: Publication, kind: MatchKind) {
        self.init(
            kind: kind,
            title: publication.displayTitle,
            detail: publication.series ?? publication.authors.first,
            publicationID: publication.id
        )
    }

    /// Everything the local index matched, flattened into rows in its own ranked order.
    ///
    /// The grouping is thrown away here and rebuilt by ``SearchAnswers/groups``, which
    /// sounds wasteful and is the point: the group a row lands in has to be decided the same
    /// way for a local row and a remote one, and two grouping passes is how they drift.
    public static func held(in groups: [MatchGroup]) -> [SearchResult] {
        groups.flatMap { group in
            group.publications.map { SearchResult($0, kind: group.kind) }
        }
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

/// One heading's worth of rows.
public struct SearchResultGroup: Sendable, Equatable, Identifiable {
    public var id: MatchKind { kind }
    public let kind: MatchKind
    public let results: [SearchResult]

    public init(kind: MatchKind, results: [SearchResult]) {
        self.kind = kind
        self.results = results
    }
}

/// One question, put to everything at once, answered at whatever speed each can manage.
///
/// **This is the whole seam in one value.** `library-browsing` asks that "locally held
/// results render immediately and remote results fill in as they arrive, merged into the
/// same ranked groups", and — the sentence that decides the design — that "the arrival of
/// remote results never reorders or displaces a result the reader is already reaching for".
///
/// A ranking that re-ran on every answer would satisfy the first sentence and break the
/// second: a reader with a finger travelling towards the third row would find a different
/// book under it because a server two hundred milliseconds away finally replied. So the
/// merge here is **append-only**. Rows keep the position they arrived at, for ever. A late
/// answer can add rows below, and can add a heading below; it can never move one.
///
/// The cost is that a very good remote match sits under a mediocre local one. That is the
/// right trade: the reader can see both, and the alternative is a screen that moves under
/// their thumb.
///
/// Pure — no network, no clock, no store. Both platforms hold the same table of cases
/// against it. Android's `SearchAnswers` mirrors it.
public struct SearchAnswers: Sendable, Equatable {
    /// What was asked. Kept so a stale answer arriving after the reader typed on can be
    /// recognised and dropped by the caller.
    public let term: String

    /// Every row, in the order it arrived. Never sorted again.
    public private(set) var results: [SearchResult]

    /// Which libraries have not answered yet, in the order they were asked.
    public private(set) var waiting: [String]

    /// The libraries that could not answer, by the name a reader would recognise.
    ///
    /// `library-browsing`: a source that fails is "named once, quietly, with a way to try
    /// it again". Once — so a retry that fails again does not stack a second line up.
    public private(set) var silent: [SilentSource]

    /// A library that did not answer, and the identifier needed to ask it again.
    public struct SilentSource: Sendable, Equatable, Identifiable {
        public var id: String { sourceID }
        public let sourceID: String
        public let name: String

        public init(sourceID: String, name: String) {
            self.sourceID = sourceID
            self.name = name
        }
    }

    /// The state a search starts in: what the device could answer instantly, and the list
    /// of everyone else who was asked.
    public init(term: String, local: [SearchResult] = [], asking: [String] = []) {
        self.term = term
        self.waiting = asking
        self.silent = []
        self.results = Self.appending(local, to: [])
    }

    /// Whether anything is still expected. Drives the quiet progress line, and nothing else.
    public var isWaiting: Bool { !waiting.isEmpty }

    /// Rows under their headings, in the order each heading first had something to put
    /// under it.
    ///
    /// A heading order fixed by the enum would be a second opinion about ranking, and the
    /// two would disagree the first time a person matched better than a title.
    public var groups: [SearchResultGroup] {
        var order: [MatchKind] = []
        var members: [MatchKind: [SearchResult]] = [:]
        for result in results {
            if members[result.kind] == nil { order.append(result.kind) }
            members[result.kind, default: []].append(result)
        }
        return order.map { SearchResultGroup(kind: $0, results: members[$0] ?? []) }
    }

    /// A library answered. Its rows go on the end; nothing already shown moves.
    ///
    /// Answering twice is not an error — a source can be asked again after it failed — so
    /// this is idempotent in the only way that matters: rows already present are dropped
    /// rather than duplicated.
    public func answered(_ sourceID: String, with rows: [SearchResult]) -> SearchAnswers {
        var copy = self
        copy.results = Self.appending(rows, to: results)
        copy.waiting.removeAll { $0 == sourceID }
        copy.silent.removeAll { $0.sourceID == sourceID }
        return copy
    }

    /// A library could not answer.
    ///
    /// `library-browsing`: "the results already shown stay usable and are never replaced by
    /// an error". So this touches nothing but the notice — there is no failure state for
    /// the screen as a whole, because there is no moment at which the reader would rather
    /// have an error than the eleven rows they can already see.
    public func couldNotAnswer(_ sourceID: String, named name: String) -> SearchAnswers {
        var copy = self
        copy.waiting.removeAll { $0 == sourceID }
        guard !copy.silent.contains(where: { $0.sourceID == sourceID }) else { return copy }
        copy.silent.append(SilentSource(sourceID: sourceID, name: name))
        return copy
    }

    /// The reader asked a silent library to try again.
    ///
    /// It leaves the notice and rejoins the queue, so the line under the results goes back
    /// to saying that something is still coming.
    public func askingAgain(_ sourceID: String) -> SearchAnswers {
        var copy = self
        copy.silent.removeAll { $0.sourceID == sourceID }
        guard !copy.waiting.contains(sourceID) else { return copy }
        copy.waiting.append(sourceID)
        return copy
    }

    /// Rows appended to what is already there, first spelling wins.
    ///
    /// **Only a remote row is ever dropped.** A row the device can open is never folded
    /// away, because two books that share a title are two books and losing one of them from
    /// a search is worse than showing a reader two rows that read alike. A remote row that
    /// says the same thing as a row already on screen *is* a duplicate — it is the copy on
    /// the server of the copy in the reader's hand — and folding it is the whole reason the
    /// merge knows about `foldKey` at all.
    ///
    /// The same rule de-duplicates *within* one answer: a server that matched one series by
    /// its own name and again through one of its chapters sent two rows for one thing.
    private static func appending(
        _ rows: [SearchResult],
        to existing: [SearchResult]
    ) -> [SearchResult] {
        var seen = Set(existing.map(\.foldKey))
        var merged = existing
        for row in rows {
            let isNew = seen.insert(row.foldKey).inserted
            guard isNew || row.publicationID != nil else { continue }
            merged.append(row)
        }
        return merged
    }
}
