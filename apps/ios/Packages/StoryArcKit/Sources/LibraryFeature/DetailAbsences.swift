internal import StoryArcCore

/// What a publication's page draws when the publication does not carry it: nothing.
///
/// `publication-detail`: "those lines are absent rather than shown empty or filled with a
/// placeholder", and "the page's composition holds together with only a cover and a title".
/// The rules are here rather than inside the two view bodies for ``seriesLine(for:)``'s
/// reason — free and pure so they can be asserted without a view, and asserted so the four
/// absences the delta names are a test rather than a reading of a `if let`.
///
/// The series line is not here: it is ``seriesLine(for:)``, shared with every other surface
/// that draws a title with a series under it, and it answers the harder question of a series
/// that merely repeats the title.

/// The description the page draws, or `nil` where there is none worth drawing.
///
/// **Blank counts as absent, and that is a fix rather than a tidy-up.** This was
/// `!summary.isEmpty`, which passes a description of three spaces — and a `Text("   ")` is
/// the delta's "shown empty" exactly: a paragraph of nothing with the page's own spacing
/// above and below it. Android has always read this as `isNotBlank()`
/// (`PublicationDetailScreen.kt`), so the same publication composed differently on the two
/// platforms, which is the class of divergence the mirrored layers exist to prevent.
///
/// A scanned description is whatever the file's metadata carried, so whitespace is not a
/// hypothetical: `ComicInfo.xml` writes `<Summary></Summary>` with the element indented onto
/// its own line often enough that the empty-but-not-blank case is the ordinary one.
func detailSummary(of publication: Publication) -> String? {
    guard let summary = publication.summary,
          !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }
    return summary
}

/// Author and year, joined only where both exist — and `nil` where neither does.
///
/// One line rather than two rows, because "Mara Quill · 2024" is one fact about a book and
/// "Author: —" is a fact the app invented. The join is the middle dot the subtitle uses on
/// Android for the same reason: an author and a year read the same way in every language
/// this app speaks, so neither half is a translated sentence.
func detailSecondaryLine(for publication: Publication) -> String? {
    var parts: [String] = []
    if let author = publication.authors.first, !author.isEmpty { parts.append(author) }
    if let year = publication.year { parts.append(String(year)) }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}
