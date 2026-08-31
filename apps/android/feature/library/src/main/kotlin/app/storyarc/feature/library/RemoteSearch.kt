package app.storyarc.feature.library

import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.catalogue.OpdsClient
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.catalogue.OpenSearchDescription
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.model.KavitaHit
import app.storyarc.core.model.MatchKind
import app.storyarc.core.model.SearchResult
import app.storyarc.core.model.SearchRoute
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.CredentialStore

/**
 * Putting one question to a configured library that lives somewhere else.
 *
 * Each kind of library is asked in its own dialect and answers in the one shape the merge
 * understands. Nothing here decides *when* to ask or *what to do* with a failure — that is
 * [LibrarySearch]'s job, and keeping the two apart is what lets the interesting rule (a late
 * answer never moves a row) be tested without a network.
 *
 * iOS's `RemoteSearch` asks the same two kinds the same two ways.
 */
internal object RemoteSearch {

    /**
     * Whether this library can be asked a question at all.
     *
     * A folder cannot: its contents are already in the local index, so asking it would be
     * asking the device about itself. A network share cannot either — SMB has no search, and
     * walking a whole share per keystroke is not a search, it is an outage.
     */
    fun answers(source: Source): Boolean = when (source.kind) {
        SourceKind.KAVITA_SERVER, SourceKind.OPDS_CATALOG -> true
        SourceKind.LOCAL_FOLDER, SourceKind.NETWORK_SHARE -> false
    }

    /** A library that had nothing to say and no way to say why. */
    class Unanswered : Exception()

    /**
     * What this library says about the term.
     *
     * Throws when it cannot say anything, which is the case the caller turns into the quiet
     * "could not answer" notice. It never returns an empty list *instead* of throwing: a
     * server that answered "nothing" and a server that did not answer are different facts,
     * and a reader deciding whether to keep waiting needs them kept apart.
     */
    suspend fun rows(
        source: Source,
        term: String,
        credentials: CredentialStore,
        pins: CertificatePins,
    ): List<SearchResult> {
        KavitaPage.of(source, credentials)?.let { page ->
            return kavitaRows(KavitaClient(page.address).find(term), page.id)
        }
        CataloguePage.of(source, credentials)?.let { page ->
            return catalogueRows(entries(term, page, pins), source)
        }
        // No page could be built, which means the secret this library needs is not in the
        // secure store any more. Indistinguishable from being away, as far as a search goes.
        throw Unanswered()
    }

    /**
     * What a Kavita server matched, as rows.
     *
     * A person and a subject carry no route because Kavita answers them with a name alone —
     * there is nowhere for the row to go, and [SearchResult.isOpenable] is how the list knows
     * not to pretend otherwise.
     */
    fun kavitaRows(hits: List<KavitaHit>, sourceId: String): List<SearchResult> = hits.map { hit ->
        SearchResult(
            kind = kindOf(hit.kind),
            title = hit.title,
            route = if (hit.isOpenable) {
                SearchRoute(sourceId, hit.seriesId.toString())
            } else {
                null
            },
        )
    }

    /**
     * Which heading a Kavita match belongs under.
     *
     * A chapter is a publication: it is the thing a reader opens and reads, whatever the
     * server calls it. The mapping is here rather than on `KavitaHit` because it is a fact
     * about *this* screen's four headings, not about Kavita.
     */
    fun kindOf(hit: KavitaHit.Kind): MatchKind = when (hit) {
        KavitaHit.Kind.SERIES -> MatchKind.SERIES
        KavitaHit.Kind.CHAPTER -> MatchKind.PUBLICATION
        KavitaHit.Kind.PERSON -> MatchKind.PERSON
        KavitaHit.Kind.SUBJECT -> MatchKind.TAG
    }

    /** What a catalogue matched, as rows. */
    fun catalogueRows(entries: List<OpdsEntry>, source: Source): List<SearchResult> =
        entries.map { entry ->
            SearchResult(
                kind = MatchKind.PUBLICATION,
                title = entry.title,
                detail = entry.series ?: entry.authors.firstOrNull(),
                route = SearchRoute(source.id.toString(), entry.id),
            )
        }

    /**
     * The entries a catalogue offers for this term.
     *
     * Two requests in the worst case, and only because OPDS is built that way: the root feed
     * is what says whether the server can search at all, and where. A catalogue that cannot
     * search falls back to filtering the feed it just fetched, which is what `opds-catalog`
     * already asks of the browser — the same answer, reached without the reader having to
     * walk in first.
     *
     * The client is built here rather than a [CatalogueBrowser] being borrowed: a browser is
     * a `ViewModel` with a page, a scroll position and a lifecycle, and a search that lasts
     * one keystroke has no business owning one.
     *
     * `internal` rather than private so `RemoteSearchOpdsTest` can drive it against a real
     * server on the loopback interface. [rows] cannot be: it needs a `CredentialStore`, which
     * needs a `Context`, which a JVM unit test does not have — and this is the half worth
     * proving, because it is two requests and a template substitution between them.
     */
    internal suspend fun entries(
        term: String,
        page: CataloguePage,
        pins: CertificatePins,
    ): List<OpdsEntry> {
        // The origin the reader saved, not the one the feed names: a search address chosen by
        // the server is not a licence to send the reader's credential somewhere else.
        val client = OpdsClient(pins, page.origin)
        val root = client.feed(page.url, page.credential)

        val template = root.searchTemplate ?: root.searchDescription?.let { document ->
            OpenSearchDescription.template(client.bytes(document, page.credential), document)
        }
        val address = template?.let { CatalogueBrowser.fill(it, term.trim()) }
            ?: return (root.publications + root.groups.flatMap { it.publications })
                .distinctBy { it.id }
                .filter { it.matches(term) }

        val answered = client.feed(address, page.credential)
        return (answered.publications + answered.groups.flatMap { it.publications })
            .distinctBy { it.id }
    }
}
