package app.storyarc.feature.library

import android.content.Context
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.format.PublicationIndexer
import app.storyarc.core.kavita.KavitaClient
import app.storyarc.core.model.KavitaFind
import app.storyarc.core.model.KavitaHit
import app.storyarc.core.model.Publication
import app.storyarc.core.persistence.DownloadStore
import app.storyarc.core.persistence.KavitaCardStore
import java.io.File

/**
 * Searching one Kavita server, and what the search does when the server does not answer.
 *
 * **`kavita-server`'s two search scenarios, and the reason both were absent.** The clients
 * have had a `search` method on both platforms since the capability was built, tested on both,
 * and called by nothing: there was no field on the libraries screen, the series grid or the
 * chapter list. So the server-side scenario had no way in, and its unreachable counterpart had
 * nothing to degrade.
 *
 * One finder for the whole server rather than one per level, which is what makes this a search
 * of the *source* rather than of whichever list happens to be on screen. iOS's `KavitaFinder`
 * is the same value carried down its three pushed screens.
 *
 * The degradation follows the pattern `opds-catalog` already set in `CatalogueBrowser`: ask the
 * server when it can be asked, filter what is held when it cannot, and *say which one
 * happened*. What is held here is the cards beside downloads -- see `KavitaCardStore` for why
 * that is the only Kavita answer written to disk.
 */
class KavitaFinder {
    /** What the reader typed. Bound to the search field. */
    var term by mutableStateOf("")
        private set

    /** What the last run found. */
    var hits by mutableStateOf<List<KavitaHit>>(emptyList())
        private set

    /**
     * Whether those hits came from the device rather than the server.
     *
     * The reader is told, per the scenario: results "limited to cached content" is a different
     * answer from no results, and a reader who is not told will read the second.
     */
    var isCached by mutableStateOf(false)
        private set

    /** Whether a run has finished for the term now in the field. */
    var hasAnswered by mutableStateOf(false)
        private set

    /** Whether the results should be on screen instead of the level behind them. */
    val isShowing: Boolean get() = KavitaFind.term(term) != null

    fun type(text: String) {
        term = text
        if (text.isEmpty()) clear()
    }

    /** Asks the server, and falls back to the cache when it will not answer. */
    suspend fun run(context: Context, client: KavitaClient, sourceId: String) {
        val wanted = KavitaFind.term(term) ?: return clear()
        hasAnswered = false
        val answered = runCatching { client.find(wanted) }.getOrNull()
        if (answered != null) {
            hits = answered
            isCached = false
        } else {
            hits = KavitaFind.inCache(wanted, KavitaCardStore.open(context).all(sourceId))
            isCached = true
        }
        hasAnswered = true
    }

    /** Empties the field and everything that came of it. */
    fun clear() {
        term = ""
        hits = emptyList()
        isCached = false
        hasAnswered = false
    }
}

/** The one field, in the browser's top bar, that every level of the server shares. */
@Composable
fun KavitaSearchField(finder: KavitaFinder, onSubmit: () -> Unit, modifier: Modifier = Modifier) {
    TextField(
        value = finder.term,
        onValueChange = finder::type,
        singleLine = true,
        placeholder = { Text(stringResource(R.string.kavita_search_prompt)) },
        keyboardActions = androidx.compose.foundation.text.KeyboardActions { onSubmit() },
        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
            imeAction = ImeAction.Search,
        ),
        modifier = modifier.fillMaxWidth(),
    )
}

/** What a search of a Kavita server found, under the spec's own five headings. */
@Composable
fun KavitaHits(
    finder: KavitaFinder,
    onOpenSeries: (Int) -> Unit,
    onOpenKept: (String) -> Unit,
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(0.dp),
) {
    val palette = LocalStoryArcPalette.current
    LazyColumn(modifier = modifier, contentPadding = contentPadding) {
        if (finder.isCached) {
            // The scenario's own words: the search "states that results are limited to cached
            // content". Saying so is the whole difference between a degraded answer and a
            // wrong one.
            item(key = "cached") {
                Text(
                    text = stringResource(R.string.kavita_search_cached),
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.textSecondary,
                    modifier = Modifier.padding(bottom = StoryArcSpace.sm),
                )
            }
        }
        if (finder.hasAnswered && finder.hits.isEmpty()) {
            item(key = "empty") {
                Text(
                    text = stringResource(R.string.kavita_search_empty),
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.textSecondary,
                )
            }
        }
        KavitaFind.grouped(finder.hits).forEach { (kind, inKind) ->
            item(key = "heading-$kind") {
                Text(
                    text = stringResource(heading(kind)),
                    style = MaterialTheme.typography.labelLarge,
                    color = palette.textSecondary,
                    modifier = Modifier.padding(vertical = StoryArcSpace.xs),
                )
            }
            items(inKind, key = { it.id }) { hit ->
                HitRow(hit, onOpenSeries, onOpenKept)
            }
        }
    }
}

@Composable
private fun HitRow(hit: KavitaHit, onOpenSeries: (Int) -> Unit, onOpenKept: (String) -> Unit) {
    val palette = LocalStoryArcPalette.current
    val opens = hit.publicationId != null || hit.isOpenable
    Text(
        text = hit.title,
        style = MaterialTheme.typography.bodyLarge,
        // A person and a subject are names the server matched, not places. A row that looked
        // tappable and did nothing would be worse than one that plainly is not.
        color = if (opens) palette.textPrimary else palette.textSecondary,
        modifier = Modifier
            .fillMaxWidth()
            .then(
                if (!opens) {
                    Modifier
                } else {
                    Modifier.clickable {
                        hit.publicationId?.let(onOpenKept) ?: onOpenSeries(hit.seriesId)
                    }
                },
            )
            .defaultMinSize(minHeight = 48.dp)
            .padding(vertical = StoryArcSpace.xs),
    )
}

private fun heading(kind: KavitaHit.Kind) = when (kind) {
    KavitaHit.Kind.SERIES -> R.string.kavita_search_series
    KavitaHit.Kind.CHAPTER -> R.string.kavita_search_chapters
    KavitaHit.Kind.PERSON -> R.string.kavita_search_people
    KavitaHit.Kind.SUBJECT -> R.string.kavita_search_subjects
}

/**
 * Opens a download this device already holds, for a row that came from the cache.
 *
 * Null when the record is there and the bytes are not, which the system can arrange: the row
 * is left alone rather than opening an empty reader.
 */
internal suspend fun openKeptPublication(
    context: Context,
    publicationId: String,
): Pair<Publication, String>? {
    val store = DownloadStore.open(context)
    val download = store.library()[publicationId] ?: return null
    val file: File = store.location(download)
    if (!file.exists()) return null
    return runCatching { PublicationIndexer.index(file) to file.absolutePath }.getOrNull()
}
