package app.storyarc.feature.epubreader

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That a reader who cannot open a book is refused in the language the reader chose.
 *
 * `EpubReaderViewModel` resolved its three open-failure sentences with
 * `application.getString(…)`. The language override never reaches an `Application`:
 * `InterfaceLanguage.speaking()` builds an overridden context and `EpubReaderActivity` hands
 * that to `attachBaseContext`, so the override belongs to the activity. `StoryArcApplication`
 * declares no `attachBaseContext`, nothing in the tree calls `Locale.setDefault` or
 * `LocaleManager.setApplicationLocales`, and the application's resources therefore keep the
 * system configuration. A reader who set the app to French on a German device was refused in
 * German.
 *
 * `lint` cannot see this. All three keys exist in `values`, `values-de`, `values-es` and
 * `values-fr`, so `MissingTranslation` is satisfied and the wrong catalogue is read anyway.
 *
 * The fix is the one `:feature:reader` already made: the view model holds a string-resource
 * id and the composition resolves it, because `stringResource` reads `LocalContext`, which is
 * the activity's. `ReaderFailureSaysNothingInternalTest` guards the comic reader the same way
 * and records the same reason.
 *
 * The assertion is a source guard rather than a behaviour test, because this module's unit
 * tests run without an activity: an `EpubReaderViewModel` cannot be built here.
 */
class EpubFailureSpeaksTheReadersLanguageTest {

    /**
     * The view model's own source, at the path the build script hands to the test JVM.
     *
     * Deliberately not discovered. [MODULE_DIRECTORY] is set from `projectDir` in
     * `build.gradle.kts`; a walk up from the working directory leaves the worktree, because
     * this repository nests agent worktrees at `.claude/worktrees/<name>/`. The whole of
     * `src/main/kotlin` is already declared an input of the test task there.
     */
    private val source: String by lazy {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and" +
                    " will not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:epubreader:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(module, VIEW_MODEL)
        if (!file.isFile) error("$VIEW_MODEL is not under ${module.absolutePath} — has it moved?")
        file.readText()
    }

    /** The lines that set the sentence the reader is shown. */
    private val assignments: List<String> by lazy {
        source.lines().map { it.trim() }.filter { it.startsWith("$FAILURE.value =") }
    }

    @Test
    fun `the view model still sets a failure`() {
        // A guard over an empty list passes for ever. This is the assertion that fails if the
        // failure state is renamed and the two below stop reading anything.
        assertTrue(
            "No `$FAILURE.value =` line found in $VIEW_MODEL. Has the failure state been" +
                " renamed? Rename it here too, or this guard protects nothing.",
            assignments.size >= 3,
        )
    }

    @Test
    fun `the refusal is not resolved through the application context`() {
        val offenders = assignments.filter { it.contains(APPLICATION_LOOKUP) }
        assertTrue(
            "These lines resolve a reader's sentence through the Application: $offenders." +
                " The language override is applied to an activity, so the Application's" +
                " resources stay in the system language and a reader who chose French is" +
                " refused in German.",
            offenders.isEmpty(),
        )
    }

    @Test
    fun `the refusal is a resource the composition resolves`() {
        val stated = assignments.filter { it.contains(STRING_RESOURCE) }
        assertTrue(
            "Only $stated of ${assignments.size} failure lines name a string resource." +
                " The id is resolved by `stringResource` in the composition, which reads" +
                " `LocalContext` — the activity, whose configuration carries the chosen" +
                " language.",
            stated.size == assignments.size,
        )
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.epubreader.projectDir"
        const val VIEW_MODEL =
            "src/main/kotlin/app/storyarc/feature/epubreader/EpubReaderViewModel.kt"

        /** The state that carries the sentence a reader is shown when a book will not open. */
        const val FAILURE = "_failure"

        /** How a sentence in the system's language reaches the screen. */
        const val APPLICATION_LOOKUP = "application.getString"

        /** How a sentence in the reader's language reaches the screen. */
        const val STRING_RESOURCE = "R.string."
    }
}
