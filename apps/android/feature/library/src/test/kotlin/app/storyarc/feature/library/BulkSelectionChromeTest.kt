package app.storyarc.feature.library

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import app.storyarc.core.designsystem.theme.StoryArcTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

/**
 * The chrome a selection puts up on Android, which is a **contextual top app bar**.
 *
 * **It was a bottom slab, and the bottom is not Android's to spend.** `BulkActionBar` drew a
 * `Surface` of `surfaceRaised` across the foot of the shelf, holding a count, three
 * `IconButton`s and a *Done* — a straight translation of what iOS was doing, and iOS was
 * doing it wrong too. On Android the foot of the window already belongs to the navigation
 * bar, and `native-experience` asks each app to follow "that platform's current design
 * language": Material 3 Expressive's answer to a selection is the contextual top app bar —
 * a close affordance at the start, the count as the title, the actions as top-bar actions
 * with an overflow.
 *
 * **This diverges from iOS on purpose, and ADR-0001 is why it may.** iOS *hides* its tab bar
 * and puts a floating glass capsule where the tab bar was, because that is what Photos,
 * Files and Mail do. Android does the opposite: it never puts selection chrome at the bottom,
 * so its navigation bar is untouched for the whole mode. Two platforms, one requirement, two
 * idioms — which is the point of the ADR rather than an inconsistency to be reconciled.
 *
 * **Which actions are drawn as glyphs, and which is named.** *Download* and *Mark as read*
 * are icon actions: a downward arrow and a check are glyphs a reader already knows, and a
 * top app bar's action slot has no room for text at any width. *Add to…* is in the overflow
 * with its name visible — `PlaylistAdd` is exactly the sort of glyph the design review of
 * 2026-09-01 objected to, and the action opens a chooser rather than doing something, so a
 * named row leading to a sheet is the honest shape. Every one of the three carries a
 * `contentDescription` unconditionally, which is what the requirement asks for and what
 * these tests check.
 *
 * **Compositions for what the bar holds; source text for what it replaces.** Robolectric
 * composes real widgets here, so what a reader is shown and what TalkBack is told can both be
 * asked directly of [LibrarySelectionTopBar] — and every question about the bar's own contents
 * is asked that way. The last two tests are the exception and say why in their own words: the
 * *swap* is a property of [LibraryScreen]'s `Scaffold`, not of either bar, and neither bar can
 * see the chrome it stands in for. iOS asserts its whole half structurally in
 * `BulkSelectionChromeTests`, because `swift test` has no window at all.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships an image per API level and has none for 37, so it cannot be handed the
// module's target. 34 is inside its range and above the minimum this app supports, and none
// of the questions here has an API level in it.
@Config(sdk = [34], qualifiers = "w411dp-h891dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class BulkSelectionChromeTest {

    @get:Rule
    val compose = createComposeRule()

    /** A selection holding [count] publications, in the mode. */
    private fun picking(count: Int): LibrarySelection {
        var selection = LibrarySelection().begin()
        for (index in 0 until count) selection = selection.toggle("p$index")
        return selection
    }

    /**
     * The count is the bar's title, at nought, at one and at many.
     *
     * Nought is worth its own case: the mode is entered before anything is picked, and a
     * title that only appeared on the first tap would leave the bar blank for the frame in
     * which a reader is deciding what the mode is. One and five are worth theirs because
     * `library_selected` is a plural in four languages, and a `stringResource` where a
     * `pluralStringResource` belongs reads correctly at five and wrongly at one.
     */
    @Test
    fun `the count is the title at nought, one and many`() {
        val counts = listOf(0, 1, 5)
        val expected = mutableMapOf<Int, String>()
        // One composition, driven by state: the rule accepts `setContent` once per test, and
        // a selection changing under the same bar is what a reader actually does anyway.
        val state = mutableStateOf(picking(0))
        compose.setContent {
            StoryArcTheme {
                for (count in counts) {
                    expected[count] =
                        pluralStringResource(R.plurals.library_selected, count, count)
                }
                LibrarySelectionTopBar(
                    selection = state.value,
                    onSelectionChange = {},
                    onAddToShelf = {},
                    onDownload = {},
                    onMarkRead = {},
                )
            }
        }
        compose.waitForIdle()

        for (count in counts) {
            state.value = picking(count)
            compose.waitForIdle()
            val says = expected.getValue(count)
            assertTrue("the count string for $count is empty", says.isNotBlank())
            compose.onNodeWithText(says).assertIsDisplayed()
        }
    }

    /**
     * An inert action is **drawn** inert, which asserting `enabled` does not establish.
     *
     * `assertIsNotEnabled` reads the semantics tree: it says the node will refuse a tap. It
     * says nothing about a single pixel, and for a while nothing was true about the pixels.
     * Each `Icon` passed `tint = palette.accent`, and an `IconButton` shows a disabled child
     * by lowering `LocalContentColor` — which an explicitly-tinted `Icon` never reads. So
     * `enabled = false` changed the semantics and changed nothing a reader could see:
     * cropping the action region out of the nought-picked and two-picked captures of
     * 2026-09-04 gave **byte-identical** PNGs.
     *
     * That matters because §3b.4 chose shown-and-inert over hidden, and its whole argument is
     * that a shown capsule "says what the mode is for before anything is picked". A control
     * that says it is available and is not says something worse than nothing.
     *
     * **A rendered-pixel assertion, because every source-text guard in this file would have
     * passed.** The defect was a colour that arrived by the wrong route, not a modifier that
     * was missing — and its iOS twin went unnoticed for the same reason until a screenshot
     * caught it. Robolectric in `NATIVE` graphics mode can rasterise a node, which
     * `SliderTrackTouchesItsThumbTest` already relies on, so this runs in CI with no device.
     */
    @Test
    fun `a disabled action is drawn differently from a live one`() {
        val state = mutableStateOf(picking(0))
        lateinit var downloadLabel: String
        compose.setContent {
            StoryArcTheme {
                downloadLabel = stringResource(R.string.library_bulk_download)
                LibrarySelectionTopBar(
                    selection = state.value,
                    onSelectionChange = {},
                    onAddToShelf = {},
                    onDownload = {},
                    onMarkRead = {},
                )
            }
        }
        compose.waitForIdle()

        val inert = compose.onNodeWithContentDescription(downloadLabel)
            .captureToImage().toPixelMap()
        state.value = picking(2)
        compose.waitForIdle()
        val live = compose.onNodeWithContentDescription(downloadLabel)
            .captureToImage().toPixelMap()

        assertEquals("the two captures are different sizes", inert.width, live.width)
        assertEquals("the two captures are different sizes", inert.height, live.height)
        var differing = 0
        for (y in 0 until inert.height) {
            for (x in 0 until inert.width) {
                if (inert[x, y] != live[x, y]) differing += 1
            }
        }
        // A threshold rather than "any difference at all": a single anti-aliased pixel is
        // noise, and the claim is that a reader can tell the two apart. The glyph's own
        // strokes are a few per cent of the node's box, so one per cent is comfortably below
        // a real dimming and far above a stray blend.
        val total = inert.width * inert.height
        assertTrue(
            "the inert download action is drawn identically to the live one: " +
                "$differing of $total pixels differ",
            differing > total / 100,
        )
    }

    /**
     * Every control in the bar names itself to assistive technology, whatever it draws.
     *
     * `native-experience` asks that every control be reachable and named; a bare `Icon` with
     * a null description is a control TalkBack can only call "button". Four of them: the way
     * out, the two icon actions, and the overflow that holds the third.
     */
    @Test
    fun `every control names itself to assistive technology`() {
        var stopping = ""
        var download = ""
        var markRead = ""
        var more = ""
        compose.setContent {
            StoryArcTheme {
                stopping = stringResource(R.string.library_select_stop)
                download = stringResource(R.string.library_bulk_download)
                markRead = stringResource(R.string.library_mark_read)
                more = stringResource(R.string.library_more)
                LibrarySelectionTopBar(
                    selection = picking(2),
                    onSelectionChange = {},
                    onAddToShelf = {},
                    onDownload = {},
                    onMarkRead = {},
                )
            }
        }
        compose.waitForIdle()

        for (name in listOf(stopping, download, markRead, more)) {
            assertTrue("a control in the selection bar has no name", name.isNotBlank())
            compose.onNodeWithContentDescription(name).assertIsDisplayed()
        }
    }

    /**
     * And the one action whose glyph would lie is named in words a reader can see.
     *
     * *Add to…* opens a chooser and `PlaylistAdd` does not say so. It is an overflow row with
     * its name showing, which is the same shape [LibraryOverflowMenu] uses for everything the
     * library's own bar stopped spending an icon on.
     */
    @Test
    fun `the action that cannot be a glyph is named in the overflow`() {
        var addTo = ""
        var more = ""
        var opened = false
        compose.setContent {
            StoryArcTheme {
                addTo = stringResource(R.string.shelves_add_to)
                more = stringResource(R.string.library_more)
                LibrarySelectionTopBar(
                    selection = picking(2),
                    onSelectionChange = {},
                    onAddToShelf = { opened = true },
                    onDownload = {},
                    onMarkRead = {},
                )
            }
        }
        compose.waitForIdle()

        compose.onNodeWithContentDescription(more).performClick()
        compose.waitForIdle()
        compose.onNodeWithText(addTo).assertIsDisplayed()

        compose.onNodeWithText(addTo).performClick()
        compose.waitForIdle()
        assertTrue("the named row does not reach the add-to sheet", opened)
    }

    /**
     * Nothing picked, nothing to do — and the controls say so rather than vanishing.
     *
     * Same answer as iOS, and for the same reason: chrome that appeared on the first pick
     * would arrive under a thumb that is mid-tap. The way out is not in that group — it is
     * the close affordance at the start of the bar, and it stays live throughout, because a
     * reader who picked nothing is exactly the reader who most needs to leave.
     */
    @Test
    fun `the actions are inert at nought picked and live above it`() {
        var download = ""
        var markRead = ""
        var more = ""
        var stopping = ""
        val state = mutableStateOf(picking(0))
        compose.setContent {
            StoryArcTheme {
                download = stringResource(R.string.library_bulk_download)
                markRead = stringResource(R.string.library_mark_read)
                more = stringResource(R.string.library_more)
                stopping = stringResource(R.string.library_select_stop)
                LibrarySelectionTopBar(
                    selection = state.value,
                    onSelectionChange = {},
                    onAddToShelf = {},
                    onDownload = {},
                    onMarkRead = {},
                )
            }
        }
        compose.waitForIdle()

        for (name in listOf(download, markRead, more)) {
            compose.onNodeWithContentDescription(name).assertIsNotEnabled()
        }
        compose.onNodeWithContentDescription(stopping).assertIsEnabled()

        state.value = picking(1)
        compose.waitForIdle()
        for (name in listOf(download, markRead, more)) {
            compose.onNodeWithContentDescription(name).assertIsEnabled()
        }
        compose.onNodeWithContentDescription(stopping).assertIsEnabled()
    }

    /**
     * Leaving the mode gives the shelf its own bar back, and gives back the picks with it.
     *
     * The bar cannot see the chrome it is replacing, so what is asserted here is the value it
     * hands back: a selection that is no longer active and no longer holding anything. The
     * screen swaps [LibraryTopBar] in on exactly that, and [BulkActions] holds the same two
     * properties for iOS in `LibrarySelectionTests`.
     */
    @Test
    fun `the close affordance leaves the mode and drops the picks`() {
        var handedBack: LibrarySelection? = null
        var stopping = ""
        compose.setContent {
            StoryArcTheme {
                stopping = stringResource(R.string.library_select_stop)
                LibrarySelectionTopBar(
                    selection = picking(3),
                    onSelectionChange = { handedBack = it },
                    onAddToShelf = {},
                    onDownload = {},
                    onMarkRead = {},
                )
            }
        }
        compose.waitForIdle()

        compose.onNodeWithContentDescription(stopping).performClick()
        compose.waitForIdle()

        val ended = requireNotNull(handedBack) { "the way out handed nothing back" }
        assertFalse("the shelf is still in selection mode", ended.isActive)
        assertEquals("the picks outlived the mode", 0, ended.ids.size)
    }

    /**
     * **The assertion that pins the requirement's other half: one bar, never two.**
     *
     * Everything above asks the contextual bar about itself, and the requirement is not about
     * the bar — it is that a selection *replaces* the shelf's chrome rather than adding to it.
     * On Android that is one `if/else` in [LibraryScreen]'s `topBar` slot, and an `if/else` is
     * the only shape that makes the two bars mutually exclusive by construction. Split into
     * two independent conditionals it would draw both at once and every test in this file
     * would still pass, because no test in this file had ever asked the screen anything.
     *
     * So the walk is the same one iOS makes: find the contextual bar, walk back to the `if`
     * that encloses it, insist the condition is the selection, then insist the shelf's own bar
     * is in that same statement's `else` and nowhere else in the slot.
     *
     * **This reads source text, and it is a tripwire rather than a proof.** The choice was
     * forced rather than preferred: a composition cannot reach this question. Entering
     * selection mode from the screen needs the way in, `onSelect`, which [LibraryScreen]
     * hands over as null unless `viewModel != null && publications.isNotEmpty()` — so the
     * assertion would need an `Application`, a `ContentResolver`, a document tree and a
     * populated store before it could begin, which is the same wall `SkippedScanTest` records
     * against the same view model. And a composition proves a state, where this is a claim
     * about shape: two conditionals that happen to be exclusive for the one state a test
     * composed would pass while the next state drew two bars. Text decides it exactly.
     *
     * The picture is the other half and is owed — the emulator screenshots of the contextual
     * bar over a shelf, which is what says the swap looks right rather than merely reads it.
     */
    @Test
    fun `the two top bars are one choice, not two conditionals`() {
        val topBar = slot("topBar")

        val contextual = topBar.indexOf(SELECTION_BAR)
        assertTrue(
            "`$SELECTION_BAR` is not in the Scaffold's topBar slot, so a selection puts its" +
                " chrome up somewhere other than in place of the shelf's own bar — which is" +
                " the stacked-chrome defect this change exists to remove.",
            contextual >= 0,
        )

        val opening = topBar.lastIndexOf(IF, contextual)
        assertTrue(
            "`$SELECTION_BAR` is inside no `if`, so the contextual bar is drawn whether or" +
                " not a selection is running.",
            opening >= 0,
        )
        // The branch's own block, which bounds the condition as well: everything from the
        // `if` to the brace that opens what it guards.
        val picked = block(topBar, opening)
        val condition = topBar.substring(opening, picked.first - 1)
        assertTrue(
            "The contextual bar is put up by `${condition.trim()}` rather than by the" +
                " selection. It has to be exactly the selection: any other condition can be" +
                " true while the shelf's own bar is up too.",
            condition.contains("selection.isActive"),
        )

        // From the end of that block. An `else` here is what makes the two bars one choice;
        // two `if`s in a row, which is the mutation this test exists for, leaves nothing at
        // this offset and fails below.
        val rest = topBar.substring(picked.last + 2).trimStart()
        assertTrue(
            "The `if` that puts up the contextual bar has no `else`, so the shelf's own bar" +
                " is decided by a second condition of its own. Two conditionals can both be" +
                " true — that is two top bars at once — where one `if/else` cannot.",
            rest.startsWith(ELSE),
        )

        val ordinary = rest.substring(block(rest, 0))
        assertTrue(
            "`$ORDINARY_BAR` is not in that `else`, so the shelf gets no bar back when the" +
                " selection ends.",
            ordinary.contains(ORDINARY_BAR),
        )
        assertFalse(
            "`$SELECTION_BAR` is in the `else` branch as well, so it is drawn whether or not" +
                " a selection is running.",
            ordinary.contains(SELECTION_BAR),
        )

        // And each is declared once, so a third copy cannot sit outside the `if/else` while
        // the branches above stay honest.
        assertEquals(
            "The shelf's own bar is declared more than once in the topBar slot, so one of" +
                " them is outside the choice that hides it.",
            1,
            topBar.occurrences(ORDINARY_BAR),
        )
        assertEquals(
            "The contextual bar is declared more than once in the topBar slot, so one of" +
                " them is outside the `if` that gates it.",
            1,
            topBar.occurrences(SELECTION_BAR),
        )
    }

    /**
     * And nothing at the foot of the window belongs to the selection.
     *
     * The other direction, and the one the KDoc at the top of this file is about: `native-
     * experience` asks each app to follow its own platform, and on Android the foot of the
     * window is the navigation bar's. iOS hides its tab bar and puts a floating capsule
     * exactly there; Android must not, which is why `BulkActionBar`'s `Surface` of
     * `surfaceRaised` across the foot of the shelf was removed rather than restyled.
     *
     * **An absence of a code path, which is why this is text and not a composition.** "The
     * bottom bar decides nothing about the selection" is not a claim any single composition
     * can settle — a composition reports what the inputs it was handed drew, and the inputs
     * that would draw a bottom slab are the ones a test would have to think to supply. The
     * slot either names the selection or it does not, and text answers that in one line.
     *
     * Scoped to the `Scaffold`'s `bottomBar`, which is where the slab was and the only place
     * a bar can be a bar. Chrome floated over the shelf's own content would not be caught
     * here; the emulator screenshots are what catch that.
     */
    @Test
    fun `the bottom of the window is not the selection's to spend`() {
        val bottomBar = slot("bottomBar")
        assertFalse(
            "The Scaffold's bottomBar slot names the selection. On Android the foot of the" +
                " window belongs to the navigation bar for the whole mode — a count, an" +
                " action or a way out down there is the bottom slab this change removed, and" +
                " it would stack under the contextual bar rather than replace anything.",
            Regex(SELECTION, RegexOption.IGNORE_CASE).containsMatchIn(bottomBar),
        )
    }

    /**
     * One named lambda argument of the screen's `Scaffold`, braces balanced.
     *
     * Balanced rather than read to the next `},`: every slot here holds nested lambdas, and
     * inside `topBar` the first `},` closes `onSelect`'s own branch rather than the slot.
     */
    private fun slot(name: String): String {
        val opening = screen.indexOf("$name = {")
        if (opening < 0) {
            error(
                "`$name = {` is not in LibraryScreen.kt. Either the Scaffold's slot was" +
                    " renamed or the screen no longer has one — this guard reads that slot" +
                    " and cannot say anything without it.",
            )
        }
        return screen.substring(block(screen, opening))
    }

    /** The body of the `{ … }` that opens at or after [from], as a range into [text]. */
    private fun block(text: String, from: Int): IntRange {
        var index = text.indexOf('{', from)
        if (index < 0) error("nothing opens a block after offset $from of LibraryScreen.kt")
        val start = index + 1
        var depth = 0
        while (index < text.length) {
            if (text[index] == '{') {
                depth++
            } else if (text[index] == '}') {
                depth--
                if (depth == 0) return start until index
            }
            index++
        }
        error("a block opening at offset $from of LibraryScreen.kt is never closed")
    }

    private fun String.occurrences(needle: String): Int = split(needle).size - 1

    /**
     * The screen's own source, with `//` prose removed, at the path its build script hands
     * over.
     *
     * Handed over rather than discovered, for the reason [LibrarySearchBarTest] and
     * [SmbTransferWiringTest] both set out: a walk up from the working directory escapes the
     * module, because this repository nests agent worktrees at `.claude/worktrees/<name>/`
     * and the walk then reads the parent checkout's copy of a file that was never built here.
     *
     * The prose goes because both slots explain the very shape being checked. The `topBar`
     * comment says, in words, that selecting "swaps the bar rather than adding one at the
     * foot" and names `LibrarySelectionTopBar` while doing it; the `bottomBar` comment says
     * what used to stand there. A guard that read those would pass on the documentation of
     * the change rather than on the change.
     *
     * **Line comments only, and block comments deliberately not.** The `topBar` slot hands
     * the file picker the any-type MIME wildcard, and that string's own characters open a
     * block comment as far as a text scanner is concerned — a stripper would take it for one
     * and swallow the rest of the file hunting for a close. Nothing inside either slot is a
     * block comment anyway, and the brace walk below starts at the slot rather than at the
     * top of the file, so the KDoc on the screen's own parameters never reaches it.
     */
    private val screen: String by lazy {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and" +
                    " will not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:library:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(module, SCREEN_SOURCE)
        if (!file.isFile) {
            error("$SCREEN_SOURCE is not under ${module.absolutePath} — has it moved?")
        }
        file.readText().lineSequence().joinToString("\n") { it.substringBefore("//") }
    }

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"
        const val SCREEN_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/LibraryScreen.kt"

        /** The two bars, spelled with the parenthesis so neither name contains the other. */
        const val SELECTION_BAR = "LibrarySelectionTopBar("
        const val ORDINARY_BAR = "LibraryTopBar("

        const val IF = "if ("
        const val ELSE = "else {"
        const val SELECTION = "selection"
    }

    /** The two icon actions reach their callbacks, so the bar is wired and not merely drawn. */
    @Test
    fun `the icon actions reach what they name`() {
        var downloaded = false
        var marked = false
        var download = ""
        var markRead = ""
        compose.setContent {
            StoryArcTheme {
                download = stringResource(R.string.library_bulk_download)
                markRead = stringResource(R.string.library_mark_read)
                LibrarySelectionTopBar(
                    selection = picking(2),
                    onSelectionChange = {},
                    onAddToShelf = {},
                    onDownload = { downloaded = true },
                    onMarkRead = { marked = true },
                )
            }
        }
        compose.waitForIdle()

        compose.onNodeWithContentDescription(download).performClick()
        compose.onNodeWithContentDescription(markRead).performClick()
        compose.waitForIdle()

        assertTrue("the download action is drawn and wired to nothing", downloaded)
        assertTrue("the mark-read action is drawn and wired to nothing", marked)
    }
}
