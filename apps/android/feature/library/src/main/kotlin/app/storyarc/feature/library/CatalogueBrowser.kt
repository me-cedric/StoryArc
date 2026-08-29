package app.storyarc.feature.library

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.catalogue.OpdsClient
import app.storyarc.core.catalogue.OpdsCredential
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.catalogue.OpdsError
import app.storyarc.core.catalogue.OpdsFeed
import app.storyarc.core.catalogue.OpdsRefusal
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.CredentialStore
import java.io.IOException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * One page of a catalogue, and how to reach the next.
 *
 * `opds-catalog`'s second requirement: navigation feeds are "browsable sections" and
 * acquisition feeds are "publication grids", following facets and pagination. A page is one
 * of these; entering a section makes another. iOS's `CatalogueBrowser` is the same object.
 */
class CatalogueBrowser(
    private val context: Context,
    val title: String,
    private val root: String,
    val credential: OpdsCredential?,
    val pins: CertificatePins,
) : ViewModel() {

    /** What the page is doing. */
    sealed interface State {
        data object Idle : State
        data object Loading : State
        data object Ready : State
        data class Failed(val message: String) : State
    }

    private val _state = MutableStateFlow<State>(State.Idle)
    val state: StateFlow<State> = _state.asStateFlow()

    /** The feed as it arrived, for its title, sections and facets. */
    private val _feed = MutableStateFlow<OpdsFeed?>(null)
    val feed: StateFlow<OpdsFeed?> = _feed.asStateFlow()

    /**
     * Publications from this page and every page followed after it.
     *
     * Accumulated rather than replaced: `opds-catalog` forbids a visible "load more", so the
     * second page has to arrive underneath the first without the grid resetting.
     */
    private val _entries = MutableStateFlow<List<OpdsEntry>>(emptyList())
    val entries: StateFlow<List<OpdsEntry>> = _entries.asStateFlow()

    /**
     * Everything on this page a local search can look through.
     *
     * The grid *and* every group: an OPDS 2.0 feed can put its whole catalogue in named
     * groups and leave the top level empty, and a search that only looked at [entries] would
     * answer "nothing" for a page full of publications.
     */
    val searchable: List<OpdsEntry>
        get() = _entries.value + _feed.value?.groups.orEmpty().flatMap { it.publications }

    /** Shared with the cells, which fetch covers through the same credential. */
    val client = OpdsClient(pins)
    private var next: String? = null

    /** A page already being fetched, so a fast scroll asks once. */
    private var loadingMore = false

    /** Fetches the first page. Safe to call again; it does nothing once loaded. */
    fun load() {
        if (_state.value != State.Idle) return
        viewModelScope.launch { fetch(root, appending = false) }
    }

    /** Fetches again from the top, discarding what was shown. */
    fun reload() {
        _state.value = State.Idle
        _entries.value = emptyList()
        next = null
        load()
    }

    /**
     * Fetches the next page, if the reader has scrolled near enough to want it.
     *
     * Asked per row rather than by a button, per the spec. The threshold is most of a
     * screenful: asking at the very last row means the reader waits, and asking at the first
     * means the whole catalogue arrives whether or not anyone scrolls.
     */
    fun loadMore(position: Int) {
        val target = next ?: return
        if (loadingMore || position < _entries.value.size - PREFETCH_ROWS) return
        loadingMore = true
        viewModelScope.launch {
            fetch(target, appending = true)
            loadingMore = false
        }
    }

    /** What a search can do here. */
    sealed interface SearchOutcome {
        /** The server will answer, at this address, in a page of its own. */
        data class Server(val url: String) : SearchOutcome

        /** This catalogue does not advertise search, so what is loaded was filtered. */
        data class Local(val matches: List<OpdsEntry>) : SearchOutcome

        /** The term was empty. */
        data object Cleared : SearchOutcome
    }

    /**
     * Searches the server when it advertises search, and says so when it cannot.
     *
     * `opds-catalog`: "a catalogue without search falls back to filtering the cached
     * catalogue, and says so". The fallback filters what has been fetched, which is the only
     * cache there is until downloads exist.
     */
    fun search(term: String): SearchOutcome {
        val trimmed = term.trim()
        if (trimmed.isEmpty()) return SearchOutcome.Cleared
        val url = searchUrl(trimmed)
            ?: return SearchOutcome.Local(searchable.filter { it.matches(trimmed) })
        return SearchOutcome.Server(url)
    }

    /** Where a search for this term goes, when the catalogue advertises one. */
    fun searchUrl(term: String): String? = _feed.value?.searchTemplate?.let { fill(it, term.trim()) }

    private suspend fun fetch(url: String, appending: Boolean) {
        if (!appending) _state.value = State.Loading
        try {
            val page = client.feed(url, credential)
            if (appending) {
                // Matched on identifier: a server that repeats an entry across a page
                // boundary is common when the underlying list changed mid-scroll.
                val known = _entries.value.map { it.id }.toSet()
                _entries.value = _entries.value + page.publications.filter { it.id !in known }
            } else {
                _feed.value = page
                _entries.value = page.publications
            }
            next = page.next
            _state.value = State.Ready
        } catch (refusal: OpdsRefusal.Untrusted) {
            // A certificate refused here rather than while adding the catalogue means the
            // server's certificate changed since the reader pinned it, which is the case
            // pinning exists to catch.
            _state.value = State.Failed(
                context.getString(
                    R.string.catalogue_error_changed_certificate,
                    refusal.certificate.host,
                ),
            )
        } catch (error: OpdsError) {
            _state.value = State.Failed(CatalogueMessages.describe(context, error))
        } catch (error: IOException) {
            _state.value = State.Failed(CatalogueMessages.reachability(context, error))
        }
    }

    companion object {
        private const val PREFETCH_ROWS = 6

        /**
         * Substitutes a term into whichever placeholder the template uses.
         *
         * OpenSearch says `{searchTerms}`; OPDS 2.0 templates in the wild say `{query}`,
         * `{?query}` or `{q}`. They mean the same thing, and a reader whose server picked
         * the other spelling should not find search silently broken.
         */
        fun fill(template: String, term: String): String? {
            val escaped = java.net.URLEncoder.encode(term, "UTF-8")
            var filled = template
            for (placeholder in listOf("{searchTerms}", "{?query}", "{query}", "{?q}", "{q}")) {
                filled = filled.replace(placeholder, escaped)
            }
            // A template nothing was substituted into would fetch the unfiltered feed and
            // look like a search that matched everything.
            return if (filled == template) null else filled
        }
    }
}

/** Whether a locally filtered search should keep this entry. */
internal fun OpdsEntry.matches(term: String): Boolean {
    val needle = term.lowercase()
    return title.lowercase().contains(needle) ||
        authors.any { it.lowercase().contains(needle) } ||
        series?.lowercase()?.contains(needle) == true
}

/**
 * What is needed to open a saved catalogue: an address, a name, and a secret.
 *
 * Values, so the screen that shows the page can build the browser itself. Reading the secure
 * store is the only part that is not free, and it happens once per push.
 */
data class CataloguePage(
    val title: String,
    val url: String,
    val credential: OpdsCredential?,
) {
    companion object {
        /**
         * Null when the source is not a catalogue or has no address, which is what stops a
         * folder from being opened as one.
         */
        fun of(source: Source, credentials: CredentialStore?): CataloguePage? {
            if (source.kind != SourceKind.OPDS_CATALOG) return null
            val url = source.locator ?: return null
            val credential = source.credentialReference
                ?.let { credentials?.secret(it) }
                ?.let(OpdsCredential::of)
            return CataloguePage(source.displayName, url, credential)
        }
    }
}
