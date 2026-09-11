package app.storyarc.feature.reader

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That a reader who cannot open a book is told so in their own language, and told nothing else.
 *
 * `ReaderViewModel` assigned `cause.message` to the sentence the reader is shown, so any prose
 * thrown anywhere in `core/format` reached the screen. That prose is English, it is written for
 * a maintainer, and it says things like *no file descriptor for content://…* and *page has no
 * size*. `localization` requires every sentence a reader is shown to resolve through a
 * catalogue in four languages, and an exception message resolves through none.
 *
 * **This deliberately removes information the reader could see, and moves it rather than drops
 * it.** The catch writes the exception to `logcat` under the tag `StoryArcReader`, which
 * `adb logcat -s StoryArcReader` reads and no reader sees. The diagnostic export still does not
 * carry it, so a maintainer needs the cable or the reader's own report. For two days the cause
 * went nowhere at all, and the last test here is what fails if it does again.
 *
 * The assertion is a source guard rather than a behaviour test, because this module's unit
 * tests run on a bare JVM with no Android framework — a `ReaderViewModel` cannot be built here.
 * `SolidArchiveHasNoNoticeTest` reads the same tree the same way and records the same reason.
 */
class ReaderFailureSaysNothingInternalTest {

    /**
     * The view model's own source, at the path the build script hands to the test JVM.
     *
     * Deliberately not discovered. [MODULE_DIRECTORY] is set from `projectDir` in
     * `build.gradle.kts`; a walk up from the working directory leaves the worktree, because
     * this repository nests agent worktrees at `.claude/worktrees/<name>/`.
     */
    private val source: String by lazy {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own sources and will" +
                    " not go looking for them elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:reader:testDebugUnitTest`), which sets the" +
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
            assignments.size >= 2,
        )
    }

    @Test
    fun `the reader is never shown an exception's own message`() {
        val offenders = assignments.filter { line -> MAINTAINER_PROSE.any { line.contains(it) } }
        assertTrue(
            "These lines put internal text on the reader's screen: $offenders. `core/format`" +
                " throws English written for a maintainer — `not a pdf`, `cannot open file`," +
                " `no file descriptor for …`, `page has no size` — and a reader of French is" +
                " shown it verbatim. A sentence written for a maintainer is not the reader's.",
            offenders.isEmpty(),
        )
    }

    @Test
    fun `the refusal's cause reaches a maintainer`() {
        // The other half of the trade above. The reader is told a sentence they can read, and
        // the cause goes to `logcat`, which is where a maintainer reaches it on this platform.
        // For two days it went nowhere at all: every catch here discarded the exception with
        // `catch (_: Exception)`, so a refusal could be reported and never diagnosed.
        val catches = source.lines().map { it.trim() }.filter { it.startsWith("} catch (") }
        assertTrue(
            "No catch found in $VIEW_MODEL. This guard reads the catches around the two open" +
                " paths; if they have moved, move it with them.",
            catches.size >= 2,
        )
        val discarded = catches.filter { it.contains("(_:") }
        assertTrue(
            "These catches discard the exception: $discarded. A refusal whose cause is known" +
                " to nobody cannot be diagnosed from a report — see `reader_cannot_open`.",
            discarded.isEmpty(),
        )
        val logged = source.lines().count { it.trim().startsWith("$LOG_CALL(") }
        assertTrue(
            "$logged of ${catches.size} catches hand the cause to $LOG_CALL. The sentence the" +
                " reader sees says nothing internal, so the log is the only record left.",
            logged == catches.size,
        )
    }

    @Test
    fun `the reader is shown a translated refusal instead`() {
        val stated = assignments.filter { it.contains(STRING_RESOURCE) }
        assertTrue(
            "Only $stated of ${assignments.size} failure lines name a string resource. Every" +
                " sentence a reader is shown resolves through `values/strings.xml`, so `lint`" +
                " fails the day one of the four languages is missing it.",
            stated.size == assignments.size,
        )
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.reader.projectDir"
        const val VIEW_MODEL =
            "src/main/kotlin/app/storyarc/feature/reader/ReaderViewModel.kt"

        /** The state that carries the sentence a reader is shown when a book will not open. */
        const val FAILURE = "_failure"

        /** How an exception's own prose reaches a screen. */
        val MAINTAINER_PROSE = listOf(".message", "\"")

        /** How a translated sentence reaches a screen on Android. */
        const val STRING_RESOURCE = "R.string."

        /** How the cause reaches a maintainer on Android. */
        const val LOG_CALL = "Log.w"
    }
}
