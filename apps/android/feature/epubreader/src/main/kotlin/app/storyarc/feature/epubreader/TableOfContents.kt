package app.storyarc.feature.epubreader

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.designsystem.tokens.StoryArcSpace
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.util.Url

/**
 * The four ways of asking *where in this book do I go*.
 *
 * `ebook-reader` puts bookmarks "alongside the table of contents", and searching inside the
 * book is another way of asking the same question. One sheet with four panels rather than
 * four sheets, because a reader who opened the wrong one would have to close it to ask again.
 *
 * A type rather than an `Int`, because `EpubMenuSheet` names one per row: that is what turns
 * four panels into four one-action doors, and `tab == 2` is not a name.
 */
internal enum class ContentsTab {
    CONTENTS,
    BOOKMARKS,
    SEARCH,
    ANNOTATIONS,
}

/**
 * The publication's own navigation, to its full depth.
 *
 * `ebook-reader` asks for the publication's own navigation rather than a list this app
 * derives, so the tree comes straight from Readium and nothing here re-reads the EPUB.
 *
 * A tree is flattened into one indented list instead of being drawn with expanders.
 * A reader who opens the contents wants the whole map at once, and an entry hidden
 * behind a collapsed parent is an entry that cannot be reached in one tap.
 * ponytail: indentation; expanders only if a publication turns up deep enough to need
 * them.
 */
@Composable
internal fun TableOfContents(
    entries: List<Link>,
    currentResource: Url?,
    onGo: (Link) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    val rows = remember(entries) { entries.flattenedEntries() }
    val current = remember(rows, currentResource) { rows.indexOfResource(currentResource) }

    if (rows.isEmpty()) {
        Column(
            modifier = modifier.fillMaxWidth().padding(StoryArcSpace.gutter),
            verticalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        ) {
            Text(
                text = stringResource(R.string.epub_contents),
                style = MaterialTheme.typography.titleMedium,
                color = palette.textPrimary,
            )
            // Many EPUBs declare no navigation document at all. A sheet that opened on
            // nothing would read as a broken sheet rather than as a bare publication.
            Text(
                text = stringResource(R.string.epub_contents_none),
                style = MaterialTheme.typography.bodySmall,
                color = palette.textSecondary,
            )
        }
        return
    }

    LazyColumn(
        // The heading occupies index 0, so the row to open on sits one further down.
        // Marking the reader's place is worth nothing if the mark is a thousand rows
        // below the fold.
        state = rememberLazyListState(initialFirstVisibleItemIndex = current + 1),
        modifier = modifier.fillMaxWidth(),
        contentPadding = PaddingValues(bottom = StoryArcSpace.xl),
    ) {
        item {
            Text(
                text = stringResource(R.string.epub_contents),
                style = MaterialTheme.typography.titleMedium,
                color = palette.textPrimary,
                modifier = Modifier.padding(
                    horizontal = StoryArcSpace.gutter,
                    vertical = StoryArcSpace.md,
                ),
            )
        }

        itemsIndexed(rows) { index, row ->
            ContentsRow(
                row = row,
                isCurrent = index == current,
                onGo = { onGo(row.link) },
            )
        }
    }
}

@Composable
private fun ContentsRow(
    row: ContentsEntry,
    isCurrent: Boolean,
    onGo: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalStoryArcPalette.current
    val label = row.link.title?.takeIf { it.isNotBlank() }
        ?: stringResource(R.string.epub_contents_untitled)
    val here = stringResource(R.string.epub_contents_here)

    Row(
        modifier = modifier
            .fillMaxWidth()
            // Material's 48dp touch-target floor, per `native-experience`. Stated, not
            // composed from two spacing tokens: 32 plus 16 happens to be 48 today, and a
            // change to either would drop the floor without anything saying so.
            .heightIn(min = 48.dp)
            .clickable(role = Role.Button, onClick = onGo)
            // Without the merge a screen reader reads the title and the place marker as
            // two unrelated pieces of text on the way past.
            .semantics(mergeDescendants = true) {
                if (isCurrent) stateDescription = here
            }
            .padding(
                start = StoryArcSpace.gutter + StoryArcSpace.lg * row.indentSteps,
                end = StoryArcSpace.gutter,
                top = StoryArcSpace.sm,
                bottom = StoryArcSpace.sm,
            ),
        horizontalArrangement = Arrangement.spacedBy(StoryArcSpace.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = if (isCurrent) palette.textPrimary else palette.textSecondary,
            fontWeight = if (isCurrent) FontWeight.SemiBold else FontWeight.Normal,
            modifier = Modifier.weight(1f),
        )

        if (isCurrent) {
            // The reader's place is a word, not a weight and not a colour: weight alone
            // is invisible to anyone who cannot compare it with a neighbouring row.
            // The row already announces the same word as its state, so this copy is
            // taken out of the accessibility tree rather than spoken twice.
            Text(
                text = here,
                style = MaterialTheme.typography.labelLarge,
                color = palette.accent,
                modifier = Modifier.clearAndSetSemantics {},
            )
        }
    }
}

/** One row of the flattened tree, with the nesting it came from. */
internal data class ContentsEntry(val link: Link, val depth: Int) {
    /**
     * Indentation stops after a few levels.
     *
     * Nesting in an EPUB navigation document has no declared ceiling, and an entry six
     * levels down would otherwise be indented past the width of the sheet, leaving a
     * title one word wide.
     */
    val indentSteps: Int get() = depth.coerceAtMost(MAX_INDENT_DEPTH)
}

private const val MAX_INDENT_DEPTH = 4

internal fun List<Link>.flattenedEntries(depth: Int = 0): List<ContentsEntry> =
    flatMap { link ->
        listOf(ContentsEntry(link, depth)) + link.children.flattenedEntries(depth + 1)
    }

/**
 * The entry that owns the resource being read, or -1 when none of them can claim it.
 *
 * Matched on the resource with its fragment removed, because a locator reports the
 * resource a reader is in and not the anchor they passed on the way through it. Then one
 * more test that matters more than it looks: an entry pointing at the *whole* resource
 * owns it, and an entry pointing at an anchor inside the resource is one of several.
 * Nothing in a locator says which anchor the reader has scrolled past, so none of them is
 * marked.
 *
 * Without that test, a publication whose whole text is one content document —
 * `book.xhtml#ch1`, `book.xhtml#ch2`, and so on — marks its first chapter wherever the
 * reader actually is. A mark that is wrong everywhere is worse than no mark, because the
 * reader cannot tell which it is.
 */
internal fun List<ContentsEntry>.indexOfResource(resource: Url?): Int {
    if (resource == null) return -1
    val at = indexOfFirst { it.link.url().removeFragment().isEquivalent(resource) }
    if (at < 0) return -1
    return if (this[at].link.url().fragment == null) at else -1
}
