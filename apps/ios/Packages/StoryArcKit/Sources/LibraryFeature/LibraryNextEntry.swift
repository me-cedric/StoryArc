public import StoryArcCore

extension LibraryModel {
    /// What to offer when a publication is finished.
    ///
    /// A reading list wins over a series. `collections-and-reading-lists`: when a reader
    /// finishes an entry in a list, "the next entry in list order is offered, regardless of
    /// series or source" — a crossover read in publication order is exactly a case where
    /// the series' own next issue is the wrong answer.
    ///
    /// The first list containing it decides, when a publication is in several. Any rule
    /// here is arbitrary; this one is at least the reader's own order, since the lists are
    /// in the order they made them.
    ///
    /// Falls back to the series, which is what `comic-reader` asks for and what a reader
    /// who keeps no lists will always get.
    public func next(after publication: Publication) -> Publication? {
        for list in shelves.lists where list.entries.contains(publication.id) {
            // An entry whose publication is gone does not stop the flow: the spec says an
            // unavailable entry "does not break the ordering or the next flow", so the
            // search walks forward past every unavailable entry in this list before
            // trying the next list or falling back to the series.
            var cursor = publication.id
            while let nextID = list.next(after: cursor) {
                if let found = publications.first(where: { $0.id == nextID }) { return found }
                cursor = nextID
            }
        }
        return LibraryIndex.next(after: publication, in: publications)
    }

    /// What the reader came from, for `comic-reader`'s previous-chapter action.
    ///
    /// The mirror of ``next(after:)`` and resolved the same way, list before series: a
    /// reader who arranged a crossover expects to walk back through their own order, not
    /// through the issue numbers it cuts across.
    public func previous(before publication: Publication) -> Publication? {
        for list in shelves.lists where list.entries.contains(publication.id) {
            var cursor = publication.id
            while let previousID = list.previous(before: cursor) {
                if let found = publications.first(where: { $0.id == previousID }) { return found }
                cursor = previousID
            }
        }
        return LibraryIndex.previous(before: publication, in: publications)
    }
}
