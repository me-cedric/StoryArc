package app.storyarc.core.model

/**
 * One row of an answer to a search, whoever answered it.
 *
 * `library-browsing`: results are grouped "by what the match is rather than by which source
 * answered", and "no result is labelled with the source that supplied it". So this carries
 * no server name, no icon and no badge — nothing a row could render that would give away
 * where it came from. It carries a [route] because opening a row still has to go somewhere,
 * and *routing* is not *labelling*: one is how the tap works, the other is what the reader
 * reads.
 *
 * iOS's `SearchResult` mirrors it field for field.
 */
data class SearchResult(
    /** Which heading this appears under. */
    val kind: MatchKind,
    /** What the row says. */
    val title: String,
    /** The line under it — a series, an author, a year. Never where it came from. */
    val detail: String? = null,
    /**
     * The publication on this device this row opens, when the device holds it.
     *
     * Set for everything the local index answered, and for a remote row the device turns
     * out to already hold. Null means the row leads to [route] instead.
     */
    val publicationId: String? = null,
    /** Where the row leads when the device does not hold it. */
    val route: SearchRoute? = null,
) {
    /**
     * What makes this row *this* row, for a list that must not lose one.
     *
     * A publication the device holds is identified by the publication, so two different
     * books that happen to share a title are two rows. Everything else is identified by what
     * it says, because that is all a server gave us.
     */
    val id: String get() = publicationId?.let { "held:$it" } ?: "away:$foldKey"

    /**
     * What makes two rows *the same thing to a reader*.
     *
     * The kind and the words, and nothing else: two answerers do not share identifiers, and
     * a reader looking at two identical rows does not care that they were keyed differently.
     * Used only by the merge, and only ever to drop a remote row — see [SearchAnswers.answered].
     */
    val foldKey: String get() = "$kind:${title.lowercase()}"

    /**
     * Whether tapping this row leads anywhere.
     *
     * A person and a tag are names a server matched, not places: a row that looked tappable
     * and did nothing would be worse than a row that plainly is not.
     */
    val isOpenable: Boolean get() = publicationId != null || route != null

    companion object {
        /**
         * A publication the device holds, as a row.
         *
         * The detail line is the series, or failing that the author: the two things that
         * tell a reader which "Volume 1" they are looking at. Never the library it came
         * from, per the requirement this whole type exists to keep.
         */
        fun held(publication: Publication, kind: MatchKind): SearchResult = SearchResult(
            kind = kind,
            title = publication.displayTitle,
            detail = publication.series ?: publication.authors.firstOrNull(),
            publicationId = publication.id,
        )

        /**
         * Everything the local index matched, flattened into rows in its own ranked order.
         *
         * The grouping is thrown away here and rebuilt by [SearchAnswers.groups], which
         * sounds wasteful and is the point: the group a row lands in has to be decided the
         * same way for a local row and a remote one, and two grouping passes is how they
         * drift.
         */
        fun held(groups: List<MatchGroup>): List<SearchResult> =
            groups.flatMap { group -> group.publications.map { held(it, group.kind) } }
    }
}

/**
 * Where a row that is not on this device leads.
 *
 * The key is opaque here on purpose — a Kavita series number and a catalogue entry's
 * identifier are not the same kind of thing, and this type has no business knowing which it
 * is holding. Whoever answered the search knows how to read its own key back.
 */
data class SearchRoute(
    /** Which configured library can open it. Used to route, never to render. */
    val sourceId: String,
    val key: String,
)

/** One heading's worth of rows. */
data class SearchResultGroup(val kind: MatchKind, val results: List<SearchResult>)

/** A library that did not answer, and the identifier needed to ask it again. */
data class SilentSource(val sourceId: String, val name: String)

/**
 * One question, put to everything at once, answered at whatever speed each can manage.
 *
 * **This is the whole seam in one value.** `library-browsing` asks that "locally held
 * results render immediately and remote results fill in as they arrive, merged into the
 * same ranked groups", and — the sentence that decides the design — that "the arrival of
 * remote results never reorders or displaces a result the reader is already reaching for".
 *
 * A ranking that re-ran on every answer would satisfy the first sentence and break the
 * second: a reader with a finger travelling towards the third row would find a different
 * book under it because a server two hundred milliseconds away finally replied. So the
 * merge here is **append-only**. Rows keep the position they arrived at, for ever. A late
 * answer can add rows below, and can add a heading below; it can never move one.
 *
 * The cost is that a very good remote match sits under a mediocre local one. That is the
 * right trade: the reader can see both, and the alternative is a screen that moves under
 * their thumb.
 *
 * Pure — no network, no clock, no store. Both platforms hold the same table of cases
 * against it. iOS's `SearchAnswers` mirrors it.
 */
data class SearchAnswers(
    /**
     * What was asked. Kept so a stale answer arriving after the reader typed on can be
     * recognised and dropped by the caller.
     */
    val term: String,
    /** Every row, in the order it arrived. Never sorted again. */
    val results: List<SearchResult> = emptyList(),
    /** Which libraries have not answered yet, in the order they were asked. */
    val waiting: List<String> = emptyList(),
    /**
     * The libraries that could not answer, by the name a reader would recognise.
     *
     * `library-browsing`: a source that fails is "named once, quietly, with a way to try it
     * again". Once — so a retry that fails again does not stack a second line up.
     */
    val silent: List<SilentSource> = emptyList(),
) {
    /** Whether anything is still expected. Drives the quiet progress line, and nothing else. */
    val isWaiting: Boolean get() = waiting.isNotEmpty()

    /**
     * Rows under their headings, in the order each heading first had something to put under
     * it.
     *
     * A heading order fixed by the enum would be a second opinion about ranking, and the two
     * would disagree the first time a person matched better than a title.
     */
    val groups: List<SearchResultGroup>
        get() {
            val members = LinkedHashMap<MatchKind, MutableList<SearchResult>>()
            results.forEach { members.getOrPut(it.kind) { mutableListOf() }.add(it) }
            return members.map { (kind, rows) -> SearchResultGroup(kind, rows.toList()) }
        }

    /**
     * A library answered. Its rows go on the end; nothing already shown moves.
     *
     * Answering twice is not an error — a source can be asked again after it failed — so
     * this is idempotent in the only way that matters: rows already present are dropped
     * rather than duplicated.
     */
    fun answered(sourceId: String, rows: List<SearchResult>): SearchAnswers = copy(
        results = appending(rows, results),
        waiting = waiting.filterNot { it == sourceId },
        silent = silent.filterNot { it.sourceId == sourceId },
    )

    /**
     * A library could not answer.
     *
     * `library-browsing`: "the results already shown stay usable and are never replaced by
     * an error". So this touches nothing but the notice — there is no failure state for the
     * screen as a whole, because there is no moment at which the reader would rather have an
     * error than the eleven rows they can already see.
     */
    fun couldNotAnswer(sourceId: String, name: String): SearchAnswers {
        val stillWaiting = waiting.filterNot { it == sourceId }
        if (silent.any { it.sourceId == sourceId }) return copy(waiting = stillWaiting)
        return copy(waiting = stillWaiting, silent = silent + SilentSource(sourceId, name))
    }

    /**
     * The reader asked a silent library to try again.
     *
     * It leaves the notice and rejoins the queue, so the line under the results goes back to
     * saying that something is still coming.
     */
    fun askingAgain(sourceId: String): SearchAnswers = copy(
        waiting = if (waiting.contains(sourceId)) waiting else waiting + sourceId,
        silent = silent.filterNot { it.sourceId == sourceId },
    )

    companion object {
        /**
         * The state a search starts in: what the device could answer instantly, and the list
         * of everyone else who was asked.
         */
        fun of(
            term: String,
            local: List<SearchResult> = emptyList(),
            asking: List<String> = emptyList(),
        ): SearchAnswers = SearchAnswers(
            term = term,
            results = appending(local, emptyList()),
            waiting = asking,
        )

        /**
         * Rows appended to what is already there, first spelling wins.
         *
         * **Only a remote row is ever dropped.** A row the device can open is never folded
         * away, because two books that share a title are two books and losing one of them
         * from a search is worse than showing a reader two rows that read alike. A remote
         * row that says the same thing as a row already on screen *is* a duplicate — it is
         * the copy on the server of the copy in the reader's hand — and folding it is the
         * whole reason the merge knows about `foldKey` at all.
         *
         * The same rule de-duplicates *within* one answer: a server that matched one series
         * by its own name and again through one of its chapters sent two rows for one thing.
         */
        private fun appending(
            rows: List<SearchResult>,
            existing: List<SearchResult>,
        ): List<SearchResult> {
            val seen = existing.mapTo(mutableSetOf()) { it.foldKey }
            return existing + rows.filter { seen.add(it.foldKey) || it.publicationId != null }
        }
    }
}
