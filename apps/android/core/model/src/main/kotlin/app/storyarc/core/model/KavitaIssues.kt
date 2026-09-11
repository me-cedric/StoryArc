package app.storyarc.core.model

/**
 * The issues of a series a Kavita server matched, joined on this device.
 *
 * **Kavita cannot answer this, and its own source says why.** A chapter is matched on
 * `EF.Functions.Like(c.TitleName, ...)`, on `c.ISBN` and on `c.Range` --
 * `API/Data/Repositories/SeriesRepository.cs` at tag v0.8.7. A chapter row carries no
 * series name, so "lantern" matches no chapter of "Green Lantern (2005)" and a reader who
 * searched for their series got fifteen series and no files. The response's `Files` group
 * looks like the answer and is not: the server fills it for an administrator only, and the
 * file it names carries neither a series nor a chapter, so it cannot be opened.
 *
 * So the join is here, over publications the library already holds. `KavitaContributor`
 * makes one [Publication] per chapter, each carrying the series name the server gave it,
 * the chapter's own title and the chapter's remote id. The server's series hit carries the
 * numeric series id the library rows lack. Together they are the issue rows.
 *
 * Pure, for the reason [KavitaFind] gives: which rows a search answers with is a decision,
 * not a screen. A new file rather than a member of [KavitaFind], because iOS's
 * `KavitaFind.swift` is three lines under its cap and ADR-0001 asks the twin to carry the
 * same name. iOS's `KavitaIssues` is that twin.
 */
object KavitaIssues {
    /** What a chapter's remote id is prefixed with. See `KavitaContributor.publication`. */
    private const val CHAPTER = "chapter:"

    /**
     * The server's hits, and the issues of every series among them that the library holds.
     *
     * The series name is matched exactly, because `KavitaContributor` writes a
     * publication's series from the same `KavitaSeries.name` the server answers a series
     * hit with. A looser match would file one series' issues under another's name.
     *
     * @param hits what the server matched.
     * @param publications what the library holds for the searched source, and nothing else:
     *   a chapter id is unique to one server, so rows from another would join wrongly.
     */
    fun joined(hits: List<KavitaHit>, publications: List<Publication>): List<KavitaHit> {
        val series = hits.filter { it.kind == KavitaHit.Kind.SERIES }
        if (series.isEmpty()) return hits

        // Identity is the chapter, not the row's words. The server names a chapter with its
        // own display name and the library with the title `KavitaNaming` wrote, so two rows
        // for one chapter carry two `KavitaHit.id`s -- and a keyed list refuses them.
        val seen = hits.mapTo(mutableSetOf()) { it.chapterKey }
        val joined = mutableListOf<KavitaHit>()
        series.forEach { matched ->
            publications.filter { it.series == matched.title }.forEach { publication ->
                val chapter = publication.kavitaChapterId ?: return@forEach
                val hit = KavitaHit(
                    kind = KavitaHit.Kind.CHAPTER,
                    title = publication.displayTitle,
                    seriesId = matched.seriesId,
                    chapterId = chapter,
                )
                if (seen.add(hit.chapterKey)) joined += hit
            }
        }
        return hits + joined
    }

    /** Which chapter of which series a row is, ignoring what the row is called. */
    private val KavitaHit.chapterKey: String get() = "$kind:$seriesId:$chapterId"

    /**
     * The Kavita chapter this publication is, or null when it is not one.
     *
     * A row from a folder, a catalogue or a share carries no server chapter, so there is
     * nothing to open and nothing to key a row on.
     */
    private val Publication.kavitaChapterId: Int?
        get() = identity.serverIdentifier?.remoteId
            ?.takeIf { it.startsWith(CHAPTER) }
            ?.removePrefix(CHAPTER)
            ?.toIntOrNull()
}
