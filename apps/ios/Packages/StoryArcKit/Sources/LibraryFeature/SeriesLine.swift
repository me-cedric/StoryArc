internal import Catalogue
internal import StoryArcCore

// The rule itself is ``StoryArcCore.seriesLine(series:number:title:)``. It moved out of this
// file on 2026-09-05 because ``SearchResult`` builds a row's detail line out of a series,
// under a title, and is a model type that cannot see this module — the same module boundary
// that put Android's copy in `core/model` rather than in `:feature:library`. What stays here
// are the two overloads, because `Publication` and `OpdsEntry` are drawn by this module's
// surfaces and a second copy of the *comparison* is what the shared rule exists to prevent.

/// The series line for a publication the library holds.
func seriesLine(for publication: Publication) -> String? {
    seriesLine(
        series: publication.series,
        number: publication.number,
        title: publication.displayTitle
    )
}

/// The series line for an entry in a catalogue, which is not a ``Publication`` and does not
/// become one until it has been fetched.
///
/// The same rule over the other type rather than the same code written twice: `opds-catalog`
/// entries carry a series and a numeric index of their own, and ``CatalogueEntryCell`` and
/// ``CatalogueDetailHeadline`` both drew `"<series> #<index>"` under the entry's title with
/// nothing comparing the two. A feed whose titles already read `Harbour Lights #1` — which
/// is most feeds generated from filenames — said it twice on every entry.
///
/// The index is a `Double` because OPDS states it as one. Written as an integer, which is
/// what the two call sites already did, and refused rather than converted when a feed sends
/// something that is not a finite number: `Int(Double.nan)` is a crash, not a caption.
func seriesLine(for entry: OpdsEntry) -> String? {
    seriesLine(
        series: entry.series,
        number: entry.seriesIndex.flatMap { $0.isFinite ? String(Int($0)) : nil },
        title: entry.title
    )
}
