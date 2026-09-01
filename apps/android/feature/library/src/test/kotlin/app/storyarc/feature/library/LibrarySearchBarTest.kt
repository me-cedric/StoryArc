package app.storyarc.feature.library

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That the search bar is composed the way material3 1.5.0-alpha26 actually asks for.
 *
 * Every claim below was checked against the **disassembled artifact** rather than against the
 * documentation's account of it — `javap` over `material3.aar` out of the Gradle cache — and
 * the ones that matter are the two absences: `SearchBarDefaults` publishes no clear
 * affordance of any kind, and no API supplies the back icon that releases focus. Both are
 * hand-written here because there is nothing to call.
 *
 * **So this reads the module's own source**, for the reason [SmbTransferWiringTest] and
 * `ReaderChromeWiringTest` both set out: what is worth pinning is which API is called with
 * which partner, a JVM unit test cannot compose a `@Composable`, and the instrumented tests
 * that could are not run by any gate. A tripwire, not a proof.
 *
 * The one rule that is not Material's, and is not dressed up as it: the suggestions before a
 * query. Material knows only historical suggestions before typing; continue-reading,
 * never-opened and next-in-series are a product choice, specified in `navigation-shell` and
 * asserted where the arithmetic lives.
 */
class LibrarySearchBarTest {

    /**
     * The module's own source, at the path its build script hands to the test JVM.
     *
     * Deliberately not discovered, and [MODULE_DIRECTORY] is set from `projectDir` in
     * `build.gradle.kts` — which is the module being built by construction. Walking up from
     * the working directory escapes the module: this repository nests agent worktrees at
     * `.claude/worktrees/<name>/`, so the walk reads the parent checkout's copy of a file that
     * was never built here.
     *
     * Missing is a failure rather than a skip: a guard that cannot find what it guards has to
     * say so, or it passes forever after the file is renamed.
     */
    private val source: String by lazy { read(SEARCH_BAR_SOURCE) }

    /** The screen that owns the `Scaffold` the bar is the top bar of. */
    private val screen: String by lazy { read(SEARCH_SCREEN_SOURCE) }

    private fun read(relative: String): String {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:library:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(module, relative)
        if (!file.isFile) {
            error("$relative is not under ${module.absolutePath} — has it moved?")
        }
        return file.readText()
    }

    /**
     * Each expanded bar gets the state its own KDoc names, and no other.
     *
     * **One shared `rememberSearchBarState` cannot be right for both.** The two factories
     * exist because the two expanded bars animate differently — only they carry the content
     * fade specs their own bar reads — and `javap` confirms all three are public and
     * distinct: `rememberSearchBarState`, `rememberContainedSearchBarState` and
     * `rememberSearchBarWithGapState` each take their own animation-spec list.
     *
     * The bar this file drew before took the generic one and handed it to both branches, so
     * whichever branch a window landed on was animating against specs written for the other.
     */
    @Test
    fun `each expanded bar is hoisted with its own state partner`() {
        // **The pairing, not the two words.** This test used to look for the two factory names
        // anywhere in the file, which every arrangement of them satisfies: swapping the two
        // states at the call sites left both names present, both bars animating against the
        // other's specs, and this test green. So each binding is matched to its factory, and
        // each bar to the binding it must be handed.
        assertTrue(
            "containedState is not made by rememberContainedSearchBarState.",
            source.contains("val containedState = rememberContainedSearchBarState()"),
        )
        assertTrue(
            "dockedState is not made by rememberSearchBarWithGapState.",
            source.contains("val dockedState = rememberSearchBarWithGapState()"),
        )
        assertTrue(
            "The full-screen contained bar is not handed containedState, so it animates" +
                " against the docked bar's specs.",
            isHanded("ExpandedFullScreenContainedSearchBar", "containedState"),
        )
        assertTrue(
            "The docked bar with a gap is not handed dockedState, so it animates against the" +
                " contained bar's specs.",
            isHanded("ExpandedDockedSearchBarWithGap", "dockedState"),
        )
    }

    /** Whether `Composable(state = binding` appears, across the line break the formatter adds. */
    private fun isHanded(composable: String, binding: String): Boolean =
        Regex(Regex.escape(composable) + BAR_TAKES_STATE + Regex.escape(binding) + WORD_END)
            .containsMatchIn(source)

    @Test
    fun `the generic state factory is not used for either branch`() {
        // Without this, adding the two above while leaving the generic one in place passes —
        // and the generic one is what was wrong.
        assertFalse(
            "rememberSearchBarState is still called. Each expanded bar names its own partner.",
            Regex("""\brememberSearchBarState\(""").containsMatchIn(source),
        )
    }

    /**
     * The contained bar's own colours reach both the bar and the input field.
     *
     * `SearchBarDefaults.containedColors(state)` interpolates the container colour **as the
     * bar expands**; it takes the state for exactly that reason. Without it the contained bar
     * is drawn with baseline colours and does not move, which looks like the animation is
     * missing rather than like the colours are wrong.
     */
    @Test
    fun `the contained colours are threaded through the app bar and the field`() {
        assertTrue(
            "SearchBarDefaults.containedColors(state) is not computed.",
            source.contains("SearchBarDefaults.containedColors(state)"),
        )
        assertTrue(
            "The contained colours are not threaded into appBarWithSearchColors.",
            source.contains("SearchBarDefaults.appBarWithSearchColors(searchColors)"),
        )
        // **The bar is only half of it, and this test's own name claimed both.** It asserted
        // nothing about the field, so dropping the field's colours entirely — the half that
        // draws the text the reader is typing — left it green. The field takes them directly
        // rather than through `appBarWithSearchColors`, which is what `design.md`'s colours row
        // described wrongly until this change corrected it.
        assertTrue(
            "The input field is not given the contained colours, so the text the reader types" +
                " is drawn with baseline ones.",
            source.contains("colors = searchColors.inputFieldColors"),
        )
        assertTrue(
            "The app bar is not given the colours built from the contained ones.",
            source.contains("colors = barColors"),
        )
    }

    /**
     * The bar is a `Scaffold`'s top bar and scrolls away with the content.
     *
     * `SearchBarDefaults.enterAlwaysSearchBarScrollBehavior()` is Material's own
     * scroll-away-and-return behaviour, and it does not exist unless it is passed: the
     * parameter defaults to none, so a bar that was never handed one simply never moves.
     */
    @Test
    fun `the bar takes a scroll behaviour`() {
        // **Two files, and the split is the point.** The behaviour is created by the screen
        // that owns the `Scaffold`, because the scaffold's content is what reports the scroll
        // to it — one made beside the bar would track a scroll nothing tells it about, and the
        // bar would never move. A first version of this test looked for it in the bar alone and
        // failed on correct code.
        assertTrue(
            "enterAlwaysSearchBarScrollBehavior is not created by the screen that owns the" +
                " Scaffold, so the bar has none to take.",
            screen.contains("enterAlwaysSearchBarScrollBehavior("),
        )
        assertTrue(
            "The screen does not connect the behaviour to its own scroll.",
            screen.contains("nestedScroll(scrollBehavior.nestedScrollConnection)"),
        )
        assertTrue(
            "The screen does not hand the behaviour to the bar.",
            screen.contains("scrollBehavior = scrollBehavior"),
        )
        assertTrue(
            "The bar does not pass the behaviour to AppBarWithSearch.",
            source.contains("scrollBehavior = scrollBehavior"),
        )
    }

    /**
     * The leading icon swaps, and the expanded one releases focus.
     *
     * Material requires that "the back icon releases focus", and **no API supplies it** —
     * `SearchBarDefaults.InputField` takes `leadingIcon` as a plain slot and has no opinion
     * about what goes in it. So the swap and the `animateToCollapsed()` call are hand-written,
     * and this is what says they still exist.
     */
    @Test
    fun `the leading icon swaps to a back arrow that collapses the bar`() {
        assertTrue(
            "No back arrow in the leading slot. Material requires one when the bar is expanded.",
            source.contains("AutoMirrored.Filled.ArrowBack"),
        )
        assertTrue(
            "The leading icon no longer collapses the bar, so it does not release focus.",
            source.contains("animateToCollapsed()"),
        )
    }

    /**
     * The query can be cleared.
     *
     * Material asks for "an optional clear icon". `SearchBarDefaults` has **no clear
     * affordance of any kind** — verified with `javap` over the whole class — so this is
     * hand-written too.
     */
    @Test
    fun `a trailing icon clears the query`() {
        assertTrue(
            "No clear control in the trailing slot.",
            source.contains("trailingIcon = "),
        )
        assertTrue(
            "The trailing control does not empty the field.",
            source.contains("clearText()"),
        )
    }

    /**
     * Narrowing is filter chips, not a segmented control.
     *
     * Material retired the segmented button in the Expressive update, and its named
     * replacement is specified for "two to five toggleable views" — a fixed, known set. Our
     * sources are open and growing: a device, folders, OPDS catalogues, Kavita servers and SMB
     * shares, however many of each the reader has added. Material's own search page lists
     * "filter chips to narrow down results".
     *
     * iOS diverges here and uses its segmented scope bar, which is current and idiomatic
     * there. That divergence is deliberate and design.md carries it.
     */
    @Test
    fun `narrowing is filter chips`() {
        assertTrue("No FilterChip in the search bar.", source.contains("FilterChip("))
        assertFalse(
            "A segmented control is back. Material retired it, and its replacement is" +
                " specified for a fixed set of two to five views — our sources are neither.",
            source.contains("SingleChoiceSegmentedButtonRow") ||
                source.contains("MultiChoiceSegmentedButtonRow"),
        )
    }

    /**
     * Result rows are list items grouped by gap, not by rules.
     *
     * Material: "use segmented gaps and filled list items to define a list group"; dividers
     * are for uncontained lists. The container is transparent so the rows sit on the expanded
     * bar's own surface rather than painting a second one over it.
     */
    @Test
    fun `result rows are list items without dividers`() {
        assertTrue("Result rows are not ListItems.", source.contains("ListItem("))
        assertFalse(
            "Rows are separated by dividers. Material groups with gaps and filled items.",
            source.contains("HorizontalDivider("),
        )
    }

    /**
     * The chips reach the fan-out rather than only being drawn.
     *
     * They were drawn, their state was carried through three composables, and **nothing read
     * it**: `ask` filtered nothing and asked everyone whatever the reader had chosen. The
     * arithmetic is asserted in [SearchScopeTest]; this is the wiring between the control and
     * it, which no JVM test can compose its way to.
     *
     * Two halves, and both are needed. The scope has to be *passed*, and the effect has to be
     * *keyed* on it — an unkeyed effect would leave a fan-out already in flight running, and
     * `library-browsing` removes the could-not-answer notice "because nothing is then being
     * waited for", which is only true once that fan-out is cancelled.
     */
    @Test
    fun `the scope chips reach the search that runs`() {
        assertTrue(
            "The scope is not passed to LibrarySearch.ask, so the chips narrow nothing.",
            source.contains("search.ask(query.search, groups, registry, credentials, pins, searchScope)"),
        )
        assertTrue(
            "The effect that asks is not keyed on the scope, so changing it re-asks nothing.",
            source.contains("LaunchedEffect(query.search, searchScope)"),
        )
    }

    /**
     * The screen's scope outlives the process, and is not the shelf's.
     *
     * `library-browsing` asks the choice to persist "until changed", and a launch is not a
     * change. This was a `rememberSaveable`, which dies with the process. The store keeps the
     * two axes under separate keys — asserted in `:core:persistence`'s own suite — and this is
     * what says the screen still reaches for the search one.
     */
    @Test
    fun `the scope is the model's, written down, and not remembered in the composition`() {
        assertTrue(
            "The screen does not read the model's search scope.",
            screen.contains("viewModel.searchScope"),
        )
        assertTrue(
            "Changing the chips does not reach the model, so nothing is written down.",
            screen.contains("viewModel::setSearchScope"),
        )
        assertFalse(
            "The scope is remembered in the composition again. rememberSaveable dies with the" +
                " process, and `until changed` outlives one.",
            // The call form, not the word: the comment above the line explains what was there
            // before and why it went, and a bare substring match would be tripped by its own
            // explanation.
            Regex("""rememberSaveable\s*[({]""").containsMatchIn(screen),
        )
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"
        const val SEARCH_BAR_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/LibrarySearchBar.kt"
        const val SEARCH_SCREEN_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/SearchScreen.kt"

        /** `(` then an optional line break, then `state = `. */
        const val BAR_TAKES_STATE = """\(\s*state\s*=\s*"""
        const val WORD_END = """\b"""
    }
}
