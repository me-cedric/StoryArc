package app.storyarc.feature.epubreader

import android.view.ActionMode
import android.view.Menu
import android.view.MenuItem
import app.storyarc.core.model.HighlightColour

/**
 * What the text-selection bar offers.
 *
 * `ebook-reader`: on a selection, "highlight in several colours, add a note, copy, and
 * search-in-publication are offered". Android's own answer to a text selection is an
 * `ActionMode`, and Readium hands one over to be configured -- so this is the platform's
 * bar with this app's actions in it, rather than a floating panel drawn over the page.
 *
 * That is a deliberate divergence from iOS, which refuses the system menu and shows a
 * popover of colour swatches. The reason is that each platform's readers reach for a
 * different thing: an iOS reader expects a bubble above the words, an Android reader expects
 * the bar at the top. What both offer is the four things the spec names.
 *
 * The colours are named rather than drawn. An `ActionMode` item is a title and an icon, and
 * five swatches in a row is not a shape it has; a named colour is also the thing a screen
 * reader can say, which a swatch is not.
 */
internal class SelectionActions(
    private val onHighlight: (HighlightColour) -> Unit,
    private val onNote: () -> Unit,
    private val onSearch: () -> Unit,
) : ActionMode.Callback {

    override fun onCreateActionMode(mode: ActionMode, menu: Menu): Boolean = true

    /**
     * Called every time the bar appears, which is why the items are added here.
     *
     * Readium puts its own items in first — copy among them, which is why this adds none:
     * the spec asks for copy to be offered and the platform is already offering it.
     */
    override fun onPrepareActionMode(mode: ActionMode, menu: Menu): Boolean {
        if (menu.findItem(NOTE) != null) return false
        HighlightColour.entries.forEachIndexed { index, colour ->
            menu.add(Menu.NONE, COLOUR + index, Menu.NONE, colour.labelRes)
        }
        menu.add(Menu.NONE, NOTE, Menu.NONE, R.string.annotations_note)
        menu.add(Menu.NONE, SEARCH, Menu.NONE, R.string.epub_search)
        return true
    }

    override fun onActionItemClicked(mode: ActionMode, item: MenuItem): Boolean = when {
        item.itemId == NOTE -> {
            onNote()
            mode.finish()
            true
        }
        item.itemId == SEARCH -> {
            onSearch()
            mode.finish()
            true
        }
        item.itemId - COLOUR in HighlightColour.entries.indices -> {
            onHighlight(HighlightColour.entries[item.itemId - COLOUR])
            mode.finish()
            true
        }
        // Not ours — Readium's own, or the platform's copy. Left alone rather than
        // swallowed, which is what keeps copy working.
        else -> false
    }

    override fun onDestroyActionMode(mode: ActionMode) = Unit

    private companion object {
        /**
         * Ids of our own, in a range nothing else uses.
         *
         * Fixed rather than generated: `onPrepareActionMode` runs every time the bar
         * appears and looks for [NOTE] to decide whether it has already added its items,
         * which only works if the id is the same each time.
         */
        const val COLOUR = 0x5704_0000
        const val NOTE = COLOUR + 100
        const val SEARCH = COLOUR + 101
    }
}
