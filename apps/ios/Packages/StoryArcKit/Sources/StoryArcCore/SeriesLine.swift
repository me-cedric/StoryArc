import Foundation

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
/// the two is not a second fact about the publication. `Broken Transfer.cbz` carries no
/// metadata, so the indexer infers its title *and* its series from the filename and the two
/// are the same string.
///
/// **It lives in `StoryArcCore` rather than beside its callers because a caller here needs
/// it.** ``SearchResult`` builds a row's detail line out of the series, under the title, and
/// is a model type that cannot see `LibraryFeature`. Android moved the same rule into
/// `core/model` on 2026-09-05 for the same reason, and the two platforms answer this
/// identically or the same book reads differently on each. The `Publication` and `OpdsEntry`
/// overloads stay in `LibraryFeature`, which is where their types' surfaces are drawn.
///
/// - Parameters:
///   - series: the series as the source declares it, or `nil` where none is declared.
///   - number: the issue or volume number within it, already written the way it is shown.
///     Omitted by a caller that draws the bare series, which is what a search row does.
///   - title: the title the surface is drawing above this line.
public func seriesLine(series: String?, number: String? = nil, title: String) -> String? {
    guard let series, !isBlank(series) else { return nil }
    let line = number.map { isBlank($0) ? series : "\(series) #\($0)" } ?? series
    guard line.caseInsensitiveCompare(title) != .orderedSame else { return nil }
    return line
}

/// Whitespace is an absence, not a value.
///
/// This tested `isEmpty` on iOS and `isNotBlank` on Android until 2026-09-05, so a
/// `ComicInfo.xml` writing `<Series></Series>` indented onto its own line — which is the
/// ordinary shape of "no series", not an edge case — drew a line of spaces under the title on
/// iOS and nothing on Android. The same divergence in the same file's description rule was
/// found and fixed under task 2.4; this is the other half of it. The value itself is never
/// trimmed: what the scan collected is what the surface shows, and the trim decides only
/// whether there is anything to show.
private func isBlank(_ value: String) -> Bool {
    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}
