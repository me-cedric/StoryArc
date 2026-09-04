package app.storyarc.feature.library

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That the Keep reading card offers resuming as an action and not only as a target.
 *
 * `home-screen`, *Resuming is an action, not only a target*: the card "carries a named
 * action that resumes, as well as being tappable itself", and "the two do the same thing,
 * because a card that is a button with no button on it teaches nothing about what tapping
 * will do". A large piece of artwork does not read as a control, and the only reader who
 * learns that it is one is the reader who tries.
 *
 * **Text over source, which is a tripwire and not a proof.** A JVM unit test cannot compose
 * a `@Composable`, and the drawn proof of a drawn thing is a screenshot. What this catches
 * is the regression between screenshots: the button being deleted, or the two paths drifting
 * apart so that the tap and the button open the book differently. `LibrarySearchBarTest`
 * beside it reads its own source the same way and for the same reason.
 *
 * **The interesting assertion is the absence.** A publication that cannot be opened keeps
 * its card, dimmed — `home-screen` insists on it — and must *not* be offered a button that
 * would fail. Nothing else in the build would notice that guard going.
 */
class HomeHeroResumeWiringTest {

    private companion object {
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"
        const val CARDS = "src/main/kotlin/app/storyarc/feature/library/HomeCards.kt"
        const val SCREEN = "src/main/kotlin/app/storyarc/feature/library/HomeScreen.kt"
    }

    private val cards: String by lazy { read(CARDS) }
    private val screen: String by lazy { read(SCREEN) }

    /**
     * The module directory is handed over rather than discovered.
     *
     * A walk that climbs from the working directory escapes the module: this repository
     * nests agent worktrees at `.claude/worktrees/<name>/`, so the walk climbs out of the
     * checkout under test and reads the parent's copy of a file that was never built here.
     * Missing is a failure rather than a skip — a guard that cannot find what it guards
     * passes for ever after the file is renamed.
     */
    private fun read(relative: String): String {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`node scripts/gradle.mjs :feature:library:testDebugUnitTest`), which" +
                    " sets the property from the module directory.",
            )
        val file = File(module, relative)
        if (!file.isFile) {
            error("$relative is not under ${module.absolutePath} — has it moved?")
        }
        return file.readText()
    }

    @Test
    fun `the card carries a named action`() {
        assertTrue(
            "HomeKeepReadingCard draws no Button — the card is a target with no action on it.",
            cards.contains("Button(onClick = onResume)"),
        )
        assertTrue(
            "The action has no name on it.",
            cards.contains("stringResource(R.string.home_resume)"),
        )
    }

    @Test
    fun `the button and the tap are the same call`() {
        // Two routes to one book that could one day disagree about which page it opens at is
        // exactly what the scenario's "the two do the same thing" forbids. Both are
        // `onResume(entry.publication)`, passed from the same place.
        val callSites = Regex("onResume = \\{ onResume\\(entry\\.publication\\) \\}")
            .findAll(screen).count()
        val taps = Regex("\\.clickable \\{ onResume\\(entry\\.publication\\) \\}")
            .findAll(screen).count()

        assertTrue("The card takes no onResume — the button cannot be wired.", callSites > 0)
        assertTrue(
            "The hero has $callSites named actions and $taps tap targets; every card needs both.",
            callSites == taps,
        )
    }

    @Test
    fun `a book that cannot be opened is offered no action that would do nothing`() {
        assertTrue(
            "The resume button is drawn unconditionally — a publication that cannot be" +
                " opened would be offered a button that fails.",
            cards.contains("if (entry.isReadableNow) {\n            Button(onClick = onResume)"),
        )
    }
}
