internal import Foundation

internal import StoryArcCore

/// Which library supplied a row, as a reader would name it.
///
/// A name and an identifier, and nothing else about the library — no protocol, no address,
/// no product, no path. That is the same limit `DetailProvenanceLine` keeps, and for the
/// same reason: a library is called what the reader called it.
enum SearchOrigin: Equatable, Hashable, Sendable {
    /// A library the reader configured, by the name they gave it.
    case library(id: String, name: String)

    /// The app's own copy, belonging to no library the reader set up — a file another app
    /// handed over. There is no library to name, so the row says where it is instead.
    case thisDevice

    /// What the merge compares two origins by.
    var key: String {
        switch self {
        case let .library(id, _): "library:\(id)"
        case .thisDevice: "device"
        }
    }
}

/// One row of an answer to a search, and the library that supplied it.
///
/// `library-browsing`, *Mixed local and server search*: results are "merged into one ranked
/// list, **each labelled with its source**". `SearchResult` carries no source and cannot —
/// it lives in the domain, which does not know a registry — so the pairing happens here,
/// where the search already holds both.
///
/// Android's `FoundRow` mirrors it field for field.
struct FoundRow: Identifiable, Equatable, Sendable {
    let result: SearchResult
    let origin: SearchOrigin

    /// What makes this row *this* row, for a list that must not lose one.
    ///
    /// The origin is part of it: two libraries answering with the same title send two rows
    /// that `SearchResult.id` cannot tell apart, and a list keyed on that alone would drop
    /// one of them the moment both arrived.
    var id: String { "\(origin.key)|\(result.id)" }

    /// What makes two rows *the same thing to a reader*, within one library.
    ///
    /// Never across libraries — see ``SearchListing/appending(_:to:for:)``.
    var foldIdentity: String { "\(origin.key)|\(result.foldKey)" }

    /// A publication the device holds, as a labelled row.
    static func held(
        _ publication: Publication,
        kind: MatchKind,
        in registry: SourceRegistry
    ) -> FoundRow {
        // A publication whose library has since been removed reads as being on the device,
        // which is what it is: the file is here and there is no library left to name.
        let origin: SearchOrigin
        if let id = publication.sourceID, let name = registry.name(of: id) {
            origin = .library(id: id.uuidString, name: name)
        } else {
            origin = .thisDevice
        }
        return FoundRow(result: SearchResult(publication, kind: kind), origin: origin)
    }

    /// Everything the local index matched, flattened into labelled rows.
    static func held(in groups: [MatchGroup], registry: SourceRegistry) -> [FoundRow] {
        groups.flatMap { group in
            group.publications.map { held($0, kind: group.kind, in: registry) }
        }
    }

    /// What one library answered, as labelled rows.
    static func away(_ rows: [SearchResult], from source: Source) -> [FoundRow] {
        let origin = SearchOrigin.library(id: source.id.uuidString, name: source.displayName)
        return rows.map { FoundRow(result: $0, origin: origin) }
    }
}

/// One heading's worth of rows.
struct FoundGroup: Identifiable, Equatable, Sendable {
    var id: MatchKind { kind }
    let kind: MatchKind
    let rows: [FoundRow]
}

/// One question, put to everything at once, answered at whatever speed each can manage.
///
/// **This is the whole seam in one value**, and it is the shape `library-browsing`'s *Mixed
/// local and server search* asks for: "server results and local results are merged into one
/// ranked list, each labelled with its source".
///
/// Three rules, and each one is a clause of a requirement:
///
/// - **Ranked, per answer.** ``SearchRank`` orders each answer as it lands, including the
///   device's own. One ranking applied to every answerer is the only sense in which a local
///   row and a remote row are in *one* ranked list rather than two lists drawn end to end.
/// - **Append-only, across answers.** Rows keep the position they arrived at, for ever. A
///   late answer can add rows below and can add a heading below; it can never move one. The
///   cost is that a very good remote match sits under a mediocre local one, and that is the
///   right trade: the reader can see both, and the alternative is a screen that moves under
///   their thumb while they reach for it.
/// - **Labelled, so a duplicate is only ever folded within one library.** Two libraries that
///   both hold *Fine Print* are two facts, and with each row naming its library the reader
///   can tell them apart. Folding across libraries is what made a catalogue's only answer
///   disappear from the screen while its own log recorded serving it — see
///   `docs/designs/screenshots/after-2026-08-31/README.md`, which photographed exactly that.
///
/// Pure — no network, no clock, no store. Android's `SearchListing` mirrors it, and both
/// platforms hold the same table of cases against it.
///
/// It supersedes `SearchAnswers` in `StoryArcCore`, which merged unlabelled rows and folded
/// across libraries. That type could not be extended from here: it lives in a directory this
/// change does not own.
struct SearchListing: Equatable, Sendable {

    /// What was asked. Kept so a stale answer arriving after the reader typed on can be
    /// recognised and dropped by the caller.
    let term: String

    /// Whether a row says which library supplied it.
    ///
    /// `library-browsing`, *Unified library*: a publication "shows its source only when more
    /// than one source is configured". With one library the label is on every row and
    /// distinguishes nothing from nothing.
    ///
    /// Decided once, from the registry, when the question is asked — not from the rows that
    /// have arrived. A label that appeared when the second library answered would give every
    /// row on screen an extra line at once, which is the displacement the append-only rule
    /// exists to prevent, arriving by another door.
    let namesOrigin: Bool

    /// Every row, in the order it arrived. Never sorted again.
    private(set) var rows: [FoundRow]

    /// Which libraries have not answered yet, in the order they were asked.
    private(set) var waiting: [String]

    /// The libraries that could not answer, by the name a reader would recognise.
    ///
    /// `library-browsing`: a source that fails is "named once, quietly, with a way to try it
    /// again". Once — so a retry that fails again does not stack a second line up.
    private(set) var silent: [SilentSource]

    /// A library that did not answer, and the identifier needed to ask it again.
    struct SilentSource: Sendable, Equatable, Identifiable {
        var id: String { sourceID }
        let sourceID: String
        let name: String
    }

    /// The state a search starts in: what the device could answer instantly, and the list of
    /// everyone else who was asked.
    init(
        term: String,
        namesOrigin: Bool = false,
        local: [FoundRow] = [],
        asking: [String] = []
    ) {
        self.term = term
        self.namesOrigin = namesOrigin
        waiting = asking
        silent = []
        rows = Self.appending(local, to: [], for: term)
    }

    /// Whether anything is still expected. Drives the quiet progress line, and nothing else.
    var isWaiting: Bool { !waiting.isEmpty }

    /// Rows under their headings, in the order each heading first had something to put under
    /// it.
    ///
    /// A heading order fixed by the enum would be a second opinion about ranking, and the two
    /// would disagree the first time a person matched better than a title.
    var groups: [FoundGroup] {
        var order: [MatchKind] = []
        var members: [MatchKind: [FoundRow]] = [:]
        for row in rows {
            if members[row.result.kind] == nil { order.append(row.result.kind) }
            members[row.result.kind, default: []].append(row)
        }
        return order.map { FoundGroup(kind: $0, rows: members[$0] ?? []) }
    }

    /// A library answered. Its rows are ranked among themselves and go on the end; nothing
    /// already shown moves.
    ///
    /// Answering twice is not an error — a library can be asked again after it failed — so
    /// this is idempotent in the only way that matters: rows already present are dropped
    /// rather than duplicated.
    func answered(_ sourceID: String, with incoming: [FoundRow]) -> SearchListing {
        var copy = self
        copy.rows = Self.appending(incoming, to: rows, for: term)
        copy.waiting.removeAll { $0 == sourceID }
        copy.silent.removeAll { $0.sourceID == sourceID }
        return copy
    }

    /// A library could not answer.
    ///
    /// `library-browsing`: "the results already shown stay usable and are never replaced by
    /// an error". So this touches nothing but the notice — there is no failure state for the
    /// screen as a whole, because there is no moment at which the reader would rather have an
    /// error than the eleven rows they can already see.
    func couldNotAnswer(_ sourceID: String, named name: String) -> SearchListing {
        var copy = self
        copy.waiting.removeAll { $0 == sourceID }
        guard !copy.silent.contains(where: { $0.sourceID == sourceID }) else { return copy }
        copy.silent.append(SilentSource(sourceID: sourceID, name: name))
        return copy
    }

    /// The reader asked a silent library to try again.
    ///
    /// It leaves the notice and rejoins the queue, so the line under the results goes back to
    /// saying that something is still coming.
    func askingAgain(_ sourceID: String) -> SearchListing {
        var copy = self
        copy.silent.removeAll { $0.sourceID == sourceID }
        guard !copy.waiting.contains(sourceID) else { return copy }
        copy.waiting.append(sourceID)
        return copy
    }

    /// One answer, ranked, then appended to what is already there.
    ///
    /// **A row is folded only against a row from the same library, and a row the device
    /// holds is never folded at all.**
    ///
    /// The second half is the older rule and it stands: two books that share a title are two
    /// books, and losing one of them from a search is worse than showing a reader two rows
    /// that read alike.
    ///
    /// The first half is the fix this type exists for. A cross-library fold reads as
    /// de-duplication and is really deletion: the reader is shown one row and told nothing,
    /// and a library that answered has silently had its answer thrown away. Within one
    /// library it is still right — a server that matched a series by its own name and again
    /// through one of its chapters sent two rows for one thing, and a chapter downloaded from
    /// a catalogue carries that catalogue's identity, so the server's copy of a book already
    /// on the device folds into the copy that opens with no network.
    private static func appending(
        _ incoming: [FoundRow],
        to existing: [FoundRow],
        for term: String
    ) -> [FoundRow] {
        var seen = Set(existing.map(\.foldIdentity))
        var merged = existing
        for row in SearchRank.ordered(incoming, for: term) {
            let isNew = seen.insert(row.foldIdentity).inserted
            guard isNew || row.result.publicationID != nil else { continue }
            merged.append(row)
        }
        return merged
    }
}
