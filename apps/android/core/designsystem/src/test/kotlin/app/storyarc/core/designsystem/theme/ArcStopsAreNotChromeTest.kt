package app.storyarc.core.designsystem.theme

import androidx.compose.ui.graphics.Color
import app.storyarc.core.designsystem.tokens.StoryArcColor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * The mark's later arc stops and the icon plate never reach the chrome.
 *
 * `brand.arcMid`, `brand.arcLate`, `brand.arcEnd` and `brand.iconPlate` exist so the app
 * icon can be generated from tokens rather than from four hexes typed twice. They are
 * **identity**, not chrome: `design.md` §2 says colour is information and never decoration,
 * and a slider painted in the arc's third stop tells a reader nothing they can act on. Four
 * stops spread across tab bars and chips is the mark's gradient leaking out of the icon it
 * belongs to.
 *
 * `brand.accent` and `brand.secondary` *are* chrome and are exempt — that is what they are
 * for, and `the chrome accents are exempt` below is what stops this rule being satisfied by
 * banning the whole brand group.
 *
 * **This reads source text**, because the rule is about which token name appears in which
 * position and that is exactly what a compiler cannot object to: every one of these is a
 * `Color`, and assigning any of them anywhere type-checks. iOS's
 * `ArcStopsAreNotChromeTests` is the mirror of this file and enforces the same table over
 * its own tree, so each platform's own gate catches its own violation — `pnpm test:ios`
 * would not fail for a Kotlin one.
 *
 * **It reads every module, not just this one.** The controls that would break the rule live
 * in `:feature:*` and `:app`. The root is handed over by this module's `build.gradle.kts`
 * rather than discovered, for the reason recorded there and in `AdaptiveNavigationTest`: a
 * walk that climbs from the working directory escapes the checkout, because this repository
 * nests agent worktrees at `.claude/worktrees/<name>/`. That same build file declares every
 * file read here as a task input, without which this would sit UP-TO-DATE while another
 * module gained a violation.
 */
class ArcStopsAreNotChromeTest {

    /**
     * The four identity tokens, named *and referenced*.
     *
     * The reference is the load-bearing half. A guard that only holds strings passes
     * vacuously the day a token is renamed — it goes looking for a name nothing uses any
     * more, finds nothing, and reads as success. Holding the real token beside its name
     * means a rename breaks this file's **compile**, and the name it searches for cannot
     * drift from the name it checked. Demonstrated rather than assumed: renaming `arcMid`
     * in `color.json` and regenerating fails both platforms' guards at compile time.
     */
    private val identityTokens: List<Pair<String, Color>> = listOf(
        "arcMid" to StoryArcColor.Brand.arcMid,
        "arcLate" to StoryArcColor.Brand.arcLate,
        "arcEnd" to StoryArcColor.Brand.arcEnd,
        "iconPlate" to StoryArcColor.Brand.iconPlate,
    )

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

    /**
     * The module source trees, **grouped**, one entry per module.
     *
     * Grouped rather than flattened because the coverage assertion below has to be able to
     * fail on one *family* going missing, and a summed floor cannot. Both platforms' first
     * version of this guard got that wrong and a mutation caught each:
     *
     * - iOS asserted a total of more than twenty files. Pointing its largest root at a path
     *   that does not exist left the other two holding 56 between them, the floor held, and
     *   every rule passed while two thirds of the app went unread.
     * - This file asserted at least nine trees. `app` plus the eight `core` modules is
     *   exactly nine, so dropping the whole `feature` family — 154 files, and the family
     *   where a chrome accent actually lives — **passed**.
     *
     * So the floor is per group and per tree, and never a sum across groups.
     */
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

    private fun sourceTrees(): List<File> = sourceTreesByGroup().values.flatten()

    /**
     * Kotlin sources under one tree, minus the generated tokens.
     *
     * `tokens/StoryArcTokens.kt` *declares* all four and must: it is emitted from
     * `color.json` and is where the values live. A declaration is not a use, and a guard
     * that cannot tell them apart fails on the one file allowed to name them.
     */
    private fun kotlinFiles(tree: File): List<File> =
        tree.walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .filterNot { it.name == "StoryArcTokens.kt" }
            .toList()

    private fun allKotlinFiles(): List<File> = sourceTrees().flatMap(::kotlinFiles)

    /** A file's code lines, with `//` comments stripped. */
    private fun codeLines(file: File): List<String> =
        file.readText().split("\n").map { line ->
            val comment = line.indexOf("//")
            if (comment >= 0) line.substring(0, comment) else line
        }

    @Test
    fun `The walk reaches every module group, and none of them is empty`() {
        val groups = sourceTreesByGroup()

        // One floor per group. A group the walk cannot see is a group this rule does not
        // cover, and `feature` is the one where a chrome accent actually lives.
        MINIMUM_TREES_PER_GROUP.forEach { (group, floor) ->
            val trees = groups[group].orEmpty()
            assertTrue(
                "expected at least $floor source tree(s) under '$group' of" +
                    " ${androidRoot.absolutePath}, found ${trees.size} — has the layout moved?",
                trees.size >= floor,
            )
            trees.forEach { tree ->
                assertTrue(
                    "almost no Kotlin under ${tree.absolutePath} — has the layout moved?",
                    kotlinFiles(tree).size >= 2,
                )
            }
        }

        // And the group set itself, so a family renamed or dropped is visible rather than
        // absorbed into a total that still looks healthy.
        assertEquals(MINIMUM_TREES_PER_GROUP.keys, groups.keys)
    }

    @Test
    fun `No app source names an identity token outside a brand surface`() {
        val offenders = mutableListOf<String>()
        for (file in allKotlinFiles()) {
            if (file.name in BRAND_SURFACES) continue
            codeLines(file).forEachIndexed { index, line ->
                identityTokens.forEach { (name, _) ->
                    if (line.contains(".$name")) offenders += "${file.name}:${index + 1} — $name"
                }
            }
        }

        assertTrue(
            "These name one of the mark's identity tokens in app code: $offenders." +
                " `arcMid`, `arcLate`, `arcEnd` and `iconPlate` belong to the mark, the app" +
                " icons and brand surfaces. A control that wants the brand's colour wants" +
                " the palette's `accent`; a second emphasis wants" +
                " `StoryArcColor.Brand.secondary`. If this really is a brand surface" +
                " drawing the mark, add its filename to BRAND_SURFACES — and note the" +
                " accent rule still applies inside it.",
            offenders.isEmpty(),
        )
    }

    @Test
    fun `No identity token sits in an accent position, brand surface or not`() {
        // The durable half of the rule. The check above is absolute *today* because no
        // screen draws the mark yet; the moment one does and joins BRAND_SURFACES, this is
        // what still holds inside it. A page may draw the arc and must not accent a control
        // with it.
        val positions = listOf(
            "accent =", "accentMuted =", "primary =", "secondary =", "tertiary =",
            "containerColor =", "indicatorColor =", "tint =", "selectedColor =",
        )

        val offenders = mutableListOf<String>()
        for (file in allKotlinFiles()) {
            codeLines(file).forEachIndexed { index, line ->
                val trimmed = line.trim()
                if (positions.none { trimmed.contains(it) }) return@forEachIndexed
                identityTokens.forEach { (name, _) ->
                    if (trimmed.contains(".$name")) offenders += "${file.name}:${index + 1} — $name"
                }
            }
        }

        assertTrue(
            "These put one of the mark's identity tokens in a chrome accent position:" +
                " $offenders. An accent is `StoryArcColor.Brand.accent`, which is one value" +
                " on every appearance and is gated on both canvases. The arc's later stops" +
                " are gated by nothing, because nothing is meant to be read against them.",
            offenders.isEmpty(),
        )
    }

    @Test
    fun `The chrome accents are exempt, and the app actually uses them`() {
        // Without this the two rules above are satisfied by an app that names no brand
        // token at all, which is how a guard ends up protecting an empty room.
        val usesAccent = allKotlinFiles().count { file ->
            val code = codeLines(file).joinToString("\n")
            code.contains("Brand.accent") || code.contains("palette.accent") ||
                code.contains(".accent")
        }
        assertTrue(
            "Nothing reaches the chrome accent any more, which is how the rules above get" +
                " satisfied by removing the brand rather than by placing it correctly.",
            usesAccent > 0,
        )

        // And the exemption is a value rather than only prose: no chrome token is forbidden.
        val forbidden = identityTokens.map { it.first }.toSet()
        assertFalse(forbidden.contains("accent"))
        assertFalse(forbidden.contains("accentMuted"))
        assertFalse(forbidden.contains("secondary"))
        assertFalse(forbidden.contains("secondaryStrong"))
        assertEquals(4, forbidden.size)
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from Gradle's own `rootDir`. */
        const val ROOT_DIRECTORY = "storyarc.android.rootDir"

        /**
         * The floor per module group. Today: one `app`, eight `core` modules, four `feature` modules.
         *
         * Deliberately below the real counts — this catches a group that moved or was
         * renamed, not a repository that gained or lost a module. A `LinkedHashMap`, so the
         * key-set assertion reads in a stable order.
         */
        val MINIMUM_TREES_PER_GROUP = linkedMapOf("app" to 1, "core" to 6, "feature" to 3)

        /**
         * Files allowed to name an identity token: the brand surfaces.
         *
         * **Empty today, and that is the current truth rather than an oversight** — no
         * screen draws the mark from tokens yet. The icon chooser of §5.3 is the one that
         * will, and it belongs here by filename when it lands. The accent rule above still
         * applies inside an allowed file, so being on this list buys the right to *draw*
         * the brand, not the right to accent a control with it.
         */
        val BRAND_SURFACES = emptySet<String>()
    }
}
