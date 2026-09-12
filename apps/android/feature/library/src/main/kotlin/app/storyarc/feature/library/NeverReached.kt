package app.storyarc.feature.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind

/**
 * The sources that were asked and have never answered, named in the order they were added.
 *
 * `library-browsing`'s *A source that has never been reached*: the library says that source
 * has not been read yet, names it, and offers to try again. Until this function the shelf
 * said nothing at all for that source. [LibraryNotice.of] returns [LibraryNotice.Nothing]
 * when no source has ever answered, [sourcesStillBeingRead] returns a count and drops every
 * name, and [LibraryAway] draws a sentence that names nobody and is reached only when the
 * shelf is empty.
 *
 * **Three states are deliberately not this sentence.**
 *
 * 1. `Connecting` is [sourcesStillBeingRead]'s. The source is being asked now, so "has not
 *    been read yet" would race the answer. This also gives the retry below its feedback: a
 *    probe marks the source `Connecting`, this list empties, and the still-being-read line
 *    takes over until the probe lands.
 * 2. `Unauthorized` needs a sign-in. `SourceConnectionState.needsUserAction` names that
 *    state alone, `UnauthorizedSourceScreen` carries it, and a *Try again* that cannot
 *    change the answer is a button that teaches a reader to distrust buttons.
 * 3. A source that answered before is away, not unread. `SourceRegistry.marking` stamps
 *    `lastSuccessfulSyncEpochMillis` on every `Connected` answer and keeps the stamp through
 *    a later refusal, so a null stamp is the record that nothing ever arrived.
 *
 * A local folder is never named. It is marked connected the moment it is added, so it is
 * never a place that has failed to answer.
 *
 * Pure, so the rule can be asserted without a shelf. `NeverReachedTest` is that assertion;
 * iOS's `sourcesNeverReached(in:)` is the twin.
 */
internal fun sourcesNeverReached(sources: List<Source>): List<String> = sources
    .filter {
        it.kind != SourceKind.LOCAL_FOLDER &&
            it.lastSuccessfulSyncEpochMillis == null &&
            it.state is SourceConnectionState.Unreachable
    }
    .map { it.displayName }

/**
 * The line that names a source the library has never read, and offers to ask it again.
 *
 * Drawn like [UnavailableFolders], because it is the same shape: a sentence naming a place,
 * with one action beside it. Offline is a normal state, so this is secondary text and not an
 * error — see AGENTS.md §2.
 *
 * One row for all of them rather than one row each. `SearchResultsView.silentNotice` records
 * what the other arrangement costs: three servers configured and none answering produced
 * three notices with three *Try again* buttons, and the notices outnumbered the answers.
 * Joining the names keeps one sentence and adds no string to translate.
 *
 * iOS's `NeverReachedNotice` is the twin.
 */
@Composable
internal fun NeverReachedNotice(
    names: List<String>,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(StoryArcSpace.md),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.md),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = stringResource(R.string.library_source_never_reached, names.joinToString(", ")),
            style = MaterialTheme.typography.labelLarge,
            color = palette.textSecondary,
            modifier = Modifier.weight(1f),
        )
        Button(onClick = onRetry) { Text(stringResource(R.string.source_offline_retry)) }
    }
}

/**
 * The one line the foot of the shelf has to say, and in what order.
 *
 * Two things can want this strip and exactly one gets it. A folder that is no longer
 * available comes first: `local-library` asks for it by name, the reader picked that folder
 * themselves, and re-picking it is the only action that restores those rows.
 *
 * A composable rather than two conditions inside `LibraryScreen`'s `Scaffold`, so the order
 * can be asserted. `LibraryFootNoticesTest` is that assertion. iOS ranks the same two the
 * same way in `LibraryView.bottomBar`, which also carries the bulk-selection bar — that bar
 * is a top bar on this platform, for the reason `LibrarySelectionTopBar` records.
 *
 * The strip is drawn whatever the shelf holds, which is what `library-browsing` asks for:
 * "the rest of the library is complete and usable while it says so".
 */
@Composable
internal fun LibraryFootNotices(
    unavailableFolders: List<String>,
    sources: List<Source>,
    onRepickFolder: () -> Unit,
    onRetrySources: () -> Unit,
) {
    val neverReached = sourcesNeverReached(sources)
    when {
        unavailableFolders.isNotEmpty() ->
            UnavailableFolders(names = unavailableFolders, onRepick = onRepickFolder)

        neverReached.isNotEmpty() ->
            NeverReachedNotice(names = neverReached, onRetry = onRetrySources)
    }
}
