package app.storyarc.feature.library

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Publication
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceKind

/**
 * How many sources have not put anything on the shelf yet.
 *
 * **The silence this ends.** A reader adds a Kavita server, opens the library, and sees the
 * shelf they already had. Nothing says the server is still being read, and `KavitaClient`
 * waits twenty seconds before giving up -- so for twenty seconds the app is indistinguishable
 * from one that ignored the source. `92deec66` ended the same silence one level down, in the
 * Kavita browser; this is the shelf's half of it.
 *
 * **Only a source that is still being asked.** A source that answered and holds nothing is
 * not waiting, and saying so for ever would be worse than saying nothing: the reader would
 * learn to ignore a line that is usually wrong. One that is unreachable is a different
 * sentence, which `LibraryAway` and the source's own screen already carry.
 *
 * A local folder is never counted. Its publications arrive from a walk this app is running
 * and the scan indicator already says so.
 *
 * Pure, so the rule can be asserted without a shelf. `StillBeingReadTest` is that assertion;
 * iOS's `StillBeingRead` is the twin.
 */
internal fun sourcesStillBeingRead(sources: List<Source>, publications: List<Publication>): Int {
    val answered = publications.mapNotNull { it.sourceId }.toSet()
    return sources.count { source ->
        source.kind != SourceKind.LOCAL_FOLDER &&
            source.state is SourceConnectionState.Connecting &&
            source.id !in answered
    }
}

/**
 * The line that says a source is still being read, or nothing when none is.
 *
 * Above the shelf and not over it, like every other notice here: `library-browsing` asks
 * that a notice "does not float over the shelf's content in a way that obscures a cover".
 * No source is named, for the reason a cover names none -- the shelf does not say where a
 * publication came from, and a notice that named the one library still answering would put
 * the same fact back on the same screen.
 */
@Composable
internal fun StillBeingReadNotice(
    sources: List<Source>,
    publications: List<Publication>,
    modifier: Modifier = Modifier,
) {
    val waiting = sourcesStillBeingRead(sources, publications)
    if (waiting == 0) return
    val palette = LocalStoryArcPalette.current

    Text(
        text = pluralStringResource(R.plurals.library_still_being_read, waiting, waiting),
        style = MaterialTheme.typography.labelLarge,
        color = palette.textSecondary,
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = StoryArcSpace.gutter, vertical = StoryArcSpace.xs),
    )
}
