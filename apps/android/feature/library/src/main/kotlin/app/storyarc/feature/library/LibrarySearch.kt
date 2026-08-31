package app.storyarc.feature.library

import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.model.MatchGroup
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceRegistry
import app.storyarc.core.model.attributesPublications
import app.storyarc.core.persistence.CredentialStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * One search, across everything the reader has, answered at whatever speed each part of it
 * can manage.
 *
 * **What this is for, in one sentence: the reader asks once.** Before it, the library's field
 * filtered the local index and never asked a server; a catalogue's search lived inside the
 * catalogue; and a Kavita server's search was reached from a field on the Kavita screens.
 * Three fields, three answers, and a reader who had to know which of their books lived where
 * before they could look for one.
 *
 * The shape of the answer follows from one line of `library-browsing`: "locally held results
 * render immediately and remote results fill in as they arrive". So:
 *
 * - **The local answer is not awaited.** It is taken from the index the view model already
 *   holds and is on screen in the frame the reader typed in.
 * - **Nothing is awaited *together*.** Each library is asked in its own coroutine and each
 *   answer is folded in as it lands, so one slow server delays itself and nothing else.
 * - **A failure is not an error state.** It is a line under the results naming that library
 *   once, with a way to ask again. The rows already on screen are untouched, per the
 *   requirement's own words: "never replaced by an error".
 *
 * The merge itself is [SearchListing] — pure, mirrored, and where the ranking, the labelling
 * and the no-reordering promise are actually kept. This type is the part that has a clock and
 * a network in it, and deliberately has nothing else. iOS's `LibrarySearch` is the same
 * object.
 */
internal class LibrarySearch(private val scope: CoroutineScope) {

    private val _listing = MutableStateFlow(SearchListing.of(""))

    /** Everything known about the question currently being asked. */
    val listing: StateFlow<SearchListing> = _listing.asStateFlow()

    /** The fan-out for the term now in the field. Cancelled when the term changes. */
    private var remote: Job? = null

    /**
     * The reader typed.
     *
     * Local rows are in [listing] by the time this returns. The rest arrives later, or does
     * not arrive, and either way the screen already has something on it.
     */
    fun ask(
        raw: String,
        groups: List<MatchGroup>,
        registry: SourceRegistry,
        credentials: CredentialStore?,
        pins: CertificatePins,
    ) {
        remote?.cancel()
        remote = null

        val term = raw.trim()
        if (term.isEmpty()) {
            _listing.value = SearchListing.of("")
            return
        }

        val asked = registry.sources.filter(RemoteSearch::answers)
        _listing.value = SearchListing.of(
            term = term,
            // Read once, here, so a label cannot appear on the rows already on screen when
            // the second library replies. See [SearchListing.namesOrigin].
            namesOrigin = registry.attributesPublications,
            local = FoundRow.held(groups, registry),
            asking = asked.map { it.id.toString() },
        )

        if (asked.isEmpty() || credentials == null) return
        remote = scope.launch {
            // `library-browsing` asks for results that "update as they type, debounced". The
            // local half needs no debounce — it is a filter over a list in memory. This is
            // for the other half: a term typed at speed would otherwise put eight questions
            // to a server and throw seven of the answers away.
            delay(SETTLE_BEFORE_ASKING_MS)
            // A coroutine each rather than a loop of awaits: a loop would make the second
            // server wait for the first, and a reader with one slow server would experience
            // all of them as slow.
            asked.forEach { source ->
                launch { ask(source, term, credentials, pins) }
            }
        }
    }

    /** The reader gave up on the search. */
    fun clear() {
        remote?.cancel()
        remote = null
        _listing.value = SearchListing.of("")
    }

    /**
     * The reader asked a library that went quiet to try once more.
     *
     * `library-browsing`: the library that could not answer is named "with a way to try it
     * again". One library, not all of them — a reader whose home server is off does not want
     * their other three asked a second time to find that out.
     */
    fun retry(
        sourceId: String,
        sources: List<Source>,
        credentials: CredentialStore?,
        pins: CertificatePins,
    ) {
        val source = sources.firstOrNull { it.id.toString() == sourceId } ?: return
        if (credentials == null) return
        val term = _listing.value.term
        _listing.value = _listing.value.askingAgain(sourceId)
        scope.launch { ask(source, term, credentials, pins) }
    }

    /** One library asked, and its answer folded in — unless the reader has moved on. */
    private suspend fun ask(
        source: Source,
        term: String,
        credentials: CredentialStore,
        pins: CertificatePins,
    ) {
        val id = source.id.toString()
        val rows = try {
            RemoteSearch.rows(source, term, credentials, pins)
        } catch (failure: Exception) {
            // Every way a library can fail to answer is the same fact to a reader: it did
            // not. Narrowing this to the four exception types the three clients can throw
            // would be four branches that all do one thing, and a fifth escaping as a crash.
            if (failure is kotlinx.coroutines.CancellationException) throw failure
            if (_listing.value.term == term) {
                _listing.value = _listing.value.couldNotAnswer(id, source.displayName)
            }
            return
        }
        // The reader has typed on, so this answer is to a question nobody is asking any more.
        // Dropped rather than merged: rows for "bon" appearing under a field that says "bone"
        // is the one way a late answer *can* still surprise someone.
        if (_listing.value.term != term) return
        _listing.value = _listing.value.answered(id, FoundRow.away(rows, source))
    }

    private companion object {
        /** How long a reader has to stop typing before a server is troubled. */
        const val SETTLE_BEFORE_ASKING_MS = 350L
    }
}
