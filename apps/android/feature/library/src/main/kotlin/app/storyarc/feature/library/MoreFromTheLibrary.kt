package app.storyarc.feature.library

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind

/**
 * The way to the rest of a library, at the foot of the shelf.
 *
 * `library-browsing`: what a source holds beyond what the app has read is "reachable from
 * search and from an explicit *more from this library* affordance at the foot of the
 * shelf". Search was already the other half; this is the one a reader can see.
 *
 * **Only a source that actually held something back**, which [sourcesWithMore] decides. A
 * shelf where every source gave everything draws no footer at all: an affordance that is
 * always there says nothing about this library in particular, and a reader learns to skim
 * past it.
 *
 * It leads to the source's own browser, which is the screen that already knows how to walk
 * that catalogue — an OPDS feed, a Kavita library, a share's directory tree. **The
 * publications there are drawn by that browser's cells and not by this grid's**, which is
 * the one clause of the requirement this does not yet meet; it is recorded in the change's
 * task 3.3 rather than glossed.
 */
@Composable
internal fun MoreFromTheLibrary(
    sources: List<Source>,
    isPartial: (java.util.UUID) -> Boolean,
    onBrowse: ((Source) -> Unit)?,
    modifier: Modifier = Modifier,
) {
    if (onBrowse == null) return
    val more = sourcesWithMore(sources, isPartial)
    if (more.isEmpty()) return

    Column(
        modifier = modifier.fillMaxWidth().padding(vertical = StoryArcSpace.md),
        verticalArrangement = Arrangement.spacedBy(StoryArcSpace.xs),
    ) {
        more.forEach { source ->
            TextButton(onClick = { onBrowse(source) }) {
                Text(stringResource(R.string.library_more_from, source.displayName))
            }
        }
    }
}

/**
 * Which sources have a way in worth offering.
 *
 * Two conditions, and both matter. The source must have held something back -- a shelf that
 * has everything needs no footer. And it must have a browser of its own: a local folder is
 * walked by this app and a way into one would lead back to the grid the reader is already
 * looking at, which is the same reason `SourceKind.hasItsOwnBrowser` exists.
 *
 * Pure, so the rule can be asserted without a shelf. `MoreFromTheLibraryTest` is that
 * assertion.
 */
internal fun sourcesWithMore(
    sources: List<Source>,
    isPartial: (java.util.UUID) -> Boolean,
): List<Source> = sources.filter { it.kind.hasItsOwnBrowser && isPartial(it.id) }
