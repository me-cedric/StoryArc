public import Foundation

/// Which source the library is showing.
///
/// `library-browsing`'s first requirement: the app "SHALL present a single library
/// spanning every source", and "SHALL let the user narrow it to one source". Both halves
/// are this one value — the library is everything unless a scope says otherwise.
///
/// Two cases rather than an optional identifier. `nil` reads as "no source" where the
/// meaning is "all of them", and this value is written down and read back: a name survives
/// a round trip through a preference file in a way a null does not.
///
/// Android's `LibraryScope` mirrors it.
public enum LibraryScope: Sendable, Equatable, Hashable, Codable {
    case allSources
    case source(UUID)

    /// The source this narrows to, or `nil` when it narrows to nothing.
    public var sourceID: UUID? {
        if case let .source(id) = self { return id }
        return nil
    }

    /// What storage calls this scope.
    ///
    /// A name rather than a position, for the reason `LibraryPreferences` gives for storing
    /// every other enum by name: an ordinal is a line number in a source file, and moving a
    /// case would silently change what a reader's stored preference means. It is also the
    /// key the per-scope layout hangs off, which is why it is one string and not two
    /// stored fields.
    public var storageKey: String {
        switch self {
        case .allSources: "all"
        case let .source(id): id.uuidString
        }
    }

    /// A scope read back from storage.
    ///
    /// Anything that is not a source identifier is every source. A stored scope naming a
    /// source the reader has since removed would otherwise open the library on an empty
    /// shelf with nothing to explain it, which is the silent narrowing `library-browsing`
    /// forbids — and "all sources" is the one answer that is never wrong.
    public init(storageKey: String) {
        self = UUID(uuidString: storageKey).map(LibraryScope.source) ?? .allSources
    }

    /// Whether a publication is part of what this scope shows.
    ///
    /// A publication with no source is only ever in "all sources". It came from somewhere
    /// the reader did not configure — a file another app handed over — and attributing it
    /// to whichever source happens to be selected would be a guess.
    public func contains(_ publication: Publication) -> Bool {
        guard case let .source(id) = self else { return true }
        return publication.sourceID == id
    }

    /// The same scope, or every source when the one it names has gone.
    ///
    /// Asked when the library is drawn rather than when a source is removed. Removal
    /// happens in one place and the scope is read in several, and the case that matters —
    /// a scope restored at launch that points at a source removed in the last session —
    /// has no removal to hang off at all.
    public func resolved(in registry: SourceRegistry) -> LibraryScope {
        guard case let .source(id) = self else { return self }
        return registry[id] == nil ? .allSources : self
    }

    /// Stored as its key, so the format is the one thing the two platforms have to agree
    /// on rather than Swift's own enum encoding.
    public init(from decoder: any Decoder) throws {
        self.init(storageKey: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageKey)
    }
}

extension LibraryIndex {
    /// The publications the by-library filter leaves on the shelf, before any other filter.
    ///
    /// **Its second caller has gone, and the reason is worth keeping.** This was separate
    /// from ``arrange(_:query:locale:progress:)`` so the continue-reading row could take the
    /// same narrowing and none of the rest, on the old `library-browsing` sentence requiring
    /// a scope to apply to "the view, its search, and its filters".
    /// `one-library-three-destinations` replaced that sentence and moved the row: narrowing
    /// to one library is a filter that "narrows what the shelf lists and nothing else", and
    /// Keep reading belongs to the home destination. So the row takes the whole library and
    /// this is the shelf listing's alone — used by `arrange` while nothing is being searched
    /// for, and by nothing else.
    public static func inScope(
        _ publications: [Publication],
        _ scope: LibraryScope
    ) -> [Publication] {
        guard scope != .allSources else { return publications }
        return publications.filter(scope.contains)
    }
}

extension SourceRegistry {
    /// Whether the library should say where each publication came from.
    ///
    /// `library-browsing`: a publication "shows its source only when more than one source
    /// is configured". With one source the label is on every row and distinguishes nothing
    /// from nothing, which is noise wearing the clothes of information.
    public var attributesPublications: Bool { sources.count > 1 }

    /// What a source is called, for a row that carries its name.
    ///
    /// `nil` for a publication no source claims, which a row draws as nothing at all rather
    /// than as "Unknown" — the reader is not missing a fact, there is no fact.
    public func name(of id: Source.ID?) -> String? {
        guard let id else { return nil }
        return self[id]?.displayName
    }

    /// Every scope the library can be narrowed to, in the reader's own order.
    ///
    /// The registry's order, because `sources` makes that order meaningful and a selector
    /// that reshuffled it would undo an arrangement the reader made by hand.
    public var scopes: [LibraryScope] {
        [.allSources] + sources.map { LibraryScope.source($0.id) }
    }
}
