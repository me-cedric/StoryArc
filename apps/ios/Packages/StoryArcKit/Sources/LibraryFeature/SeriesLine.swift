internal import Catalogue
internal import StoryArcCore

/// The line that names the series something belongs to, or `nil` when it would only repeat
/// the title back at the reader.
///
/// Free and pure so it can be asserted without a view, and shared so that every surface
/// drawing a title with a series under it answers this the same way: one composition, one
/// comparison, one answer.
///
/// **The comparison is the whole of the bug this exists to prevent.** The shelf's guard used
/// to test the *bare* series against the title while the string it returned was the
/// *composed* `"<series> #<number>"` — so a publication titled `Ashfall #1` with series
/// `Ashfall` and number `1` passed the guard and printed the same words twice, once in
/// primary and once in tertiary, on every cover of a numbered series. The catalogue was
/// worse: it composed the same line under `Text(entry.title)` with **no comparison at all**,
/// so an entry whose title already carried its number duplicated unconditionally. Composing
/// first and comparing the string that is really drawn is the fix, in one place.
///
/// Case-insensitive, for ``HomeShelfCard``'s reason: a title inferred from a filename is
/// often the series and the number joined back together, and a difference of case between
/// the two is not a second fact about the publication.
///
/// - Parameters:
///   - series: the series as the source declares it, or `nil` where none is declared.
///   - number: the issue or volume number within it, already written the way it is shown.
///   - title: the title the surface is drawing above this line.
func seriesLine(series: String?, number: String?, title: String) -> String? {
    guard let series, !series.isEmpty else { return nil }
    let line = number.map { "\(series) #\($0)" } ?? series
    guard line.caseInsensitiveCompare(title) != .orderedSame else { return nil }
    return line
}

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
