package app.storyarc.core.designsystem.theme

import app.storyarc.core.model.AppIconChoice
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Nothing but the platform records which icon is in use.
 *
 * `native-experience`'s *The platform is the only record*: the app "asks the platform rather
 * than a preference of its own, so there is no second record that can disagree", and "nothing
 * about the choice is written to preferences, a backup, a log or a diagnostic".
 * `AppIconSwitcher.applied()` is a query over component states for exactly that reason, and
 * `brand-identity-and-app-icons` was archived with nothing asserting the rest of the app keeps
 * to it.
 *
 * **This reads source text**, for the reason [ArcStopsAreNotChromeTest] does: the rule is about
 * where a name appears, and that is exactly what a compiler cannot object to. A field of type
 * [AppIconChoice] on `AppSettings` type-checks; a `SharedPreferences` write in the switcher
 * type-checks; a `[Settings]` line in the diagnostic type-checks. Each is one line, and each is
 * what this fails on. iOS's `AppIconChoiceIsNotRecordedTests` is the mirror and enforces the
 * same table over its own tree, so each platform's own gate catches its own violation.
 *
 * **In this module for the reason the arc-stops guard is.** The three places a record could
 * hide are three modules — `:core:model`, `:core:persistence`, `:feature:settings` — and this
 * module's `build.gradle.kts` is the one that hands its tests the Android root and declares
 * every module's main sources as a task input, without which a violation added elsewhere would
 * leave the guard UP-TO-DATE.
 *
 * The type is **named and referenced**: `AppIconChoice.entries` below makes a rename of the
 * type break this file's compile rather than leave it searching for a name nothing uses.
 */
class AppIconChoiceIsNotRecordedTest {

    private val androidRoot: File by lazy {
        val root = System.getProperty(ROOT_DIRECTORY)?.let(::File)
            ?: error(
                "$ROOT_DIRECTORY is unset. This test reads the app's own sources and will" +
                    " not go looking for them elsewhere — run it through Gradle" +
                    " (`pnpm gradle :core:designsystem:testDebugUnitTest`), which sets the" +
                    " property from the Android root directory.",
            )
        if (!root.isDirectory) error("$ROOT_DIRECTORY is not a directory: ${root.absolutePath}")
        root
    }

    private val settings: File get() = File(androidRoot, "core/model/src/main/kotlin/app/storyarc/core/model/AppSettings.kt")
    private val persistence: File get() = File(androidRoot, "core/persistence/src/main")
    private val diagnostic: File
        get() = File(androidRoot, "feature/settings/src/main/kotlin/app/storyarc/feature/settings/Diagnostic.kt")
    private val owners: List<File>
        get() = listOf("AppIconGroup.kt", "AppIconSwitcher.kt")
            .map { File(androidRoot, "feature/settings/src/main/kotlin/app/storyarc/feature/settings/$it") }

    /** The module source trees, grouped, one entry per module — [ArcStopsAreNotChromeTest]'s walk. */
    private fun sourceTreesByGroup(): Map<String, List<File>> {
        val app = listOf(File(androidRoot, "app/src/main")).filter { it.isDirectory }
        val libraries = listOf("core", "feature").associateWith { group ->
            File(androidRoot, group).listFiles().orEmpty()
                .sortedBy { it.name }
                .map { File(it, "src/main") }
                .filter { it.isDirectory }
        }
        return mapOf("app" to app) + libraries
    }

    private fun kotlinFiles(tree: File): List<File> =
        tree.walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .filterNot { it.name == "StoryArcTokens.kt" }
            .toList()

    private fun allKotlinFiles(): List<File> = sourceTreesByGroup().values.flatten().flatMap(::kotlinFiles)

    /**
     * A file's code, with `/* */` blocks and `//` tails removed.
     *
     * Every file this reads explains in prose why the choice is *not* stored, and names the
     * stores it does not reach in order to say so. A guard that read the prose would fail on
     * the documentation of the rule — and KDoc is a block comment, which the `//` rule alone
     * would leave in.
     */
    private fun code(file: File): String =
        BLOCK_COMMENT.replace(file.readText(), "")
            .lines()
            .joinToString("\n") { it.substringBefore("//") }

    /** The lines of [file]'s code that mention [word], case-insensitively, numbered for the report. */
    private fun linesMentioning(word: String, file: File): List<String> =
        code(file).lines().withIndex()
            .filter { (_, line) -> line.contains(word, ignoreCase = true) }
            .map { (index, _) -> "${file.name}:${index + 1}" }

    @Test
    fun `The walk reaches every module group and the three places a record could hide`() {
        val groups = sourceTreesByGroup()
        MINIMUM_TREES_PER_GROUP.forEach { (group, floor) ->
            val trees = groups[group].orEmpty()
            assertTrue(
                "expected at least $floor source tree(s) under '$group' of" +
                    " ${androidRoot.absolutePath}, found ${trees.size} — has the layout moved?",
                trees.size >= floor,
            )
        }
        assertEquals(MINIMUM_TREES_PER_GROUP.keys, groups.keys)

        assertTrue("AppSettings.kt has moved: ${settings.absolutePath}", settings.isFile)
        assertTrue("Diagnostic.kt has moved: ${diagnostic.absolutePath}", diagnostic.isFile)
        assertTrue("almost no stores under ${persistence.absolutePath}", kotlinFiles(persistence).size >= 10)
        owners.forEach { assertTrue("${it.name} has moved", it.isFile) }
    }

    @Test
    fun `Only the faces, the switcher and the chooser name the choice`() {
        // The reference. Five faces is `AppIconChoiceTest`'s claim; here it only has to compile.
        assertEquals(5, AppIconChoice.entries.size)

        val offenders = mutableListOf<String>()
        val holdersSeen = mutableSetOf<String>()
        for (file in allKotlinFiles()) {
            val names = code(file).contains("AppIconChoice")
            when {
                file.name in HOLDERS -> if (names) holdersSeen += file.name
                names -> offenders += file.name
            }
        }

        assertTrue(
            "These name `AppIconChoice` outside the three files that own it: $offenders." +
                " The platform is the only record of which icon is in use. A screen that needs" +
                " the face asks `AppIconSwitcher.applied()`; nothing stores, logs or reports it.",
            offenders.isEmpty(),
        )
        // Non-vacuous: the holders exist and do name it, so a rename cannot pass by absence.
        assertEquals("the files that own the choice no longer all name it", HOLDERS, holdersSeen)
    }

    @Test
    fun `AppSettings holds no icon field`() {
        val hits = linesMentioning("icon", settings)
        assertTrue(
            "AppSettings names the icon at $hits — a stored choice is a second record that can disagree",
            hits.isEmpty(),
        )
    }

    @Test
    fun `No preference key names the icon`() {
        val hits = kotlinFiles(persistence).flatMap { linesMentioning("icon", it) }
        assertTrue("a store names the icon at $hits — the component states are the record", hits.isEmpty())
    }

    @Test
    fun `The diagnostic says nothing about the icon`() {
        val hits = linesMentioning("icon", diagnostic)
        assertTrue("the diagnostic names the icon at $hits — nothing about the choice goes into a report", hits.isEmpty())
    }

    @Test
    fun `The chooser and the switcher reach no store and no log`() {
        val offenders = owners.flatMap { file ->
            val code = code(file)
            assertTrue("${file.name} is empty", code.isNotBlank())
            STORAGE_WORDS.filter { code.contains(it) }.map { "${file.name} — $it" }
        }
        assertTrue("the icon's owners reach storage or a log: $offenders", offenders.isEmpty())
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from Gradle's own `rootDir`. */
        const val ROOT_DIRECTORY = "storyarc.android.rootDir"

        /** The floor per module group, as [ArcStopsAreNotChromeTest] has it. */
        val MINIMUM_TREES_PER_GROUP = linkedMapOf("app" to 1, "core" to 6, "feature" to 3)

        /**
         * The three files allowed to name the choice: the faces, the switcher that asks the
         * platform, and the chooser that draws the answer.
         */
        val HOLDERS = setOf("AppIconChoice.kt", "AppIconSwitcher.kt", "AppIconGroup.kt")

        /**
         * Words that reach a preference, a file or a log. None belongs in the two files that own
         * the choice: the switcher asks `PackageManager` and the chooser asks the switcher.
         */
        val STORAGE_WORDS = listOf(
            "SharedPreferences", "getSharedPreferences", "SettingsStore", "DataStore", ".edit()", "Log.", "println(",
        )

        val BLOCK_COMMENT = Regex("""/\*.*?\*/""", RegexOption.DOT_MATCHES_ALL)
    }
}
