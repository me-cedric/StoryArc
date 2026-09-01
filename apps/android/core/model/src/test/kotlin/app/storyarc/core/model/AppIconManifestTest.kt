package app.storyarc.core.model

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The join nothing else can make: [AppIconChoice] against the manifest, the icon resources,
 * and the generator that renders the same faces for iOS.
 *
 * Four files have to agree and no compiler reads any pair of them. A typo in
 * [AppIconChoice.componentClassName] is a chooser that throws on the one press it exists for;
 * a plate hex that drifts is a different Paper on each platform; an alias missing its launcher
 * filter is a face a reader can pick that puts nothing on the home screen. The Swift side has
 * `AppIconChoiceTests` asserting the asset-set names against the catalogue on disk, which is
 * the same shape of check for the same reason.
 *
 * Shaped on `:core:designsystem`'s `ArcStopsAreNotChromeTest`: the repository root is handed
 * over by `build.gradle.kts` rather than discovered, because a walk up from the working
 * directory leaves a worktree, and every file read is declared a task input or this sits
 * UP-TO-DATE while the manifest it guards changes.
 */
class AppIconManifestTest {

    private val repoRoot: File
        get() {
            val declared = System.getProperty("storyarc.repoRootDir")
            assertTrue(
                "storyarc.repoRootDir was not set. `:core:model`'s build.gradle.kts hands it " +
                    "over; without it this guard cannot find the manifest.",
                !declared.isNullOrBlank(),
            )
            return File(requireNotNull(declared))
        }

    private fun read(relative: String): String {
        val file = File(repoRoot, relative)
        assertTrue("$relative is missing — this guard reads it", file.isFile)
        return file.readText()
    }

    private val manifest get() = read("apps/android/app/src/main/AndroidManifest.xml")

    /** The whole `<activity-alias …>…</activity-alias>` block for a face, or null. */
    private fun aliasFor(face: AppIconChoice): String? {
        val name = face.componentClassName.removePrefix("app.storyarc")
        val at = manifest.indexOf("android:name=\"$name\"")
        if (at == -1) return null
        val opens = manifest.lastIndexOf("<activity-alias", at)
        val closes = manifest.indexOf("</activity-alias>", at)
        if (opens == -1 || closes == -1) return null
        return manifest.substring(opens, closes)
    }

    private val launcherFilter = "<category android:name=\"android.intent.category.LAUNCHER\" />"

    @Test
    fun `every face has its own alias, exported, with its own icon and the launcher filter`() {
        for (face in AppIconChoice.entries) {
            val alias = aliasFor(face)
            assertTrue(
                "the manifest declares no <activity-alias> called " +
                    "${face.componentClassName} — $face is a face a reader can pick and no " +
                    "component draws it",
                alias != null,
            )
            val block = alias.orEmpty()
            assertTrue("$face's alias does not target MainActivity", "android:targetActivity=\".MainActivity\"" in block)
            assertTrue("$face's alias is not exported, so no launcher can start it", "android:exported=\"true\"" in block)
            assertTrue("$face's alias carries no launcher intent filter", launcherFilter in block)
            assertTrue("$face's alias declares no icon of its own", "android:icon=\"@mipmap/" in block)
            // Exactly the default enabled, so a fresh install draws one icon and only one.
            val wanted = if (face.isDefault) "android:enabled=\"true\"" else "android:enabled=\"false\""
            assertTrue(
                "$face's alias should be declared $wanted — a fresh install must draw the " +
                    "default face and nothing else",
                wanted in block,
            )
        }
    }

    /**
     * **The rule that stops this feature bricking the app**, read off the manifest.
     *
     * An `<activity-alias>` whose target activity is disabled does not merely lose its icon:
     * it stops resolving. On an emulator, with `MainActivity` disabled and one alias enabled,
     * `am start` on the alias left no process and the MAIN/LAUNCHER intent answered "unable to
     * resolve" — while the launcher went on drawing the icon it had cached, so the only symptom
     * was an icon that did nothing.
     *
     * So the launcher entry belongs to the aliases and `MainActivity` must carry neither a
     * launcher filter nor an `android:enabled` attribute a switch could ever flip. Task 4.5
     * asks for the opposite shape; its *reason* is kept by writing
     * `COMPONENT_ENABLED_STATE_DEFAULT` to all five on a reset instead.
     */
    @Test
    fun `the activity the aliases point at is never a launcher entry and never disabled`() {
        val activity = manifest.substringAfter("<activity\n").substringBefore("</activity>")
        assertTrue("MainActivity is not where this guard thinks it is", "android:name=\".MainActivity\"" in activity)
        assertFalse(
            "MainActivity carries the launcher filter. A face switch would then have to " +
                "disable it, and every alias stops resolving when its target is disabled.",
            launcherFilter in activity,
        )
        assertFalse(
            "MainActivity declares android:enabled. It is the target of five aliases and " +
                "must never be switched off.",
            "android:enabled" in activity,
        )
    }

    /**
     * Only `MainActivity` answers a file handover.
     *
     * `local-library` puts StoryArc in the system's "open with" list, and that belongs to the
     * activity rather than to a face. An alias repeating the VIEW or SEND filters would list
     * the app more than once the moment two components were enabled — and would keep listing
     * it under a name a reader never chose.
     */
    @Test
    fun `no alias carries a file-handover filter, and the activity does`() {
        for (face in AppIconChoice.entries) {
            val block = aliasFor(face).orEmpty()
            assertFalse("$face's alias answers VIEW; that is MainActivity's job", "action.VIEW" in block)
            assertFalse("$face's alias answers SEND; that is MainActivity's job", "action.SEND" in block)
        }
        val activity = manifest.substringAfter("<activity\n").substringBefore("</activity>")
        assertTrue("MainActivity stopped answering VIEW; `local-library` needs it", "action.VIEW" in activity)
        assertTrue("MainActivity stopped answering SEND; `local-library` needs it", "action.SEND" in activity)
    }

    /**
     * Each alias's icon resource exists, and names a background colour that exists.
     *
     * `@mipmap/ic_launcher_paper` resolving to nothing is a build failure, so that half is
     * covered — but the adaptive icon naming a `@color` the values file does not hold is
     * caught here, and so is an icon file that quietly points at the wrong plate.
     */
    @Test
    fun `each face's adaptive icon exists and names a plate the values file holds`() {
        val colours = read("apps/android/app/src/main/res/values/colors.xml")
        for (face in AppIconChoice.entries) {
            val icon = Regex("android:icon=\"@mipmap/([A-Za-z0-9_]+)\"")
                .find(aliasFor(face).orEmpty())
                ?.groupValues
                ?.get(1)
            assertTrue("$face's alias names no mipmap", icon != null)
            val xml = read("apps/android/app/src/main/res/mipmap-anydpi-v26/$icon.xml")
            val plate = Regex("<background android:drawable=\"@color/([A-Za-z0-9_]+)\"")
                .find(xml)
                ?.groupValues
                ?.get(1)
            assertTrue("$icon.xml declares no background colour", plate != null)
            assertTrue(
                "$icon.xml points at @color/$plate, which colors.xml does not define",
                "name=\"$plate\"" in colours,
            )
            // The mark, and the reason "faces of one mark" is more than a slogan: every face
            // draws generated art rather than art of its own.
            assertTrue(
                "$icon.xml draws a foreground the brand generator did not write",
                "@drawable/ic_launcher_foreground" in xml || "@drawable/ic_launcher_monochrome" in xml,
            )
            // A themed icon retints the monochrome layer, and a gradient tinted flat loses the
            // mark's internal divisions. Task 4.2 is why every face points at the flat art.
            assertTrue(
                "$icon.xml's <monochrome> is not the single-colour art",
                "<monochrome android:drawable=\"@drawable/ic_launcher_monochrome\" />" in xml,
            )
        }
    }

    /**
     * The plates match the ones the iOS faces are rendered from.
     *
     * `scripts/brand-mark.swift` renders the five iOS PNGs from its own `Palette`, and this
     * platform's plates are resource literals because an adaptive icon's background has to be
     * a resource. So the same colour is written twice, in two languages, and this is the only
     * thing that can notice when one moves: Paper drifting here would ship a different Paper
     * on each platform, and the whole point of one generator is that it cannot.
     */
    @Test
    fun `every plate equals the one the brand generator renders iOS from`() {
        val generator = read("scripts/brand-mark.swift")
        val colours = read("apps/android/app/src/main/res/values/colors.xml")

        fun hexOf(resource: String): String {
            val found = Regex("name=\"$resource\">(#[0-9A-Fa-f]{6})<").find(colours)
            assertTrue("colors.xml defines no $resource", found != null)
            return requireNotNull(found).groupValues[1].uppercase()
        }

        fun generatorHex(field: String): String {
            val found = Regex("""static let $field = Ink\("(#[0-9A-Fa-f]{6})"\)""").find(generator)
            assertTrue("scripts/brand-mark.swift has no Palette.$field", found != null)
            return requireNotNull(found).groupValues[1].uppercase()
        }

        // Named on both sides, because the pairing is the claim. `arcPlate` and `arc` differ
        // by design: the generator names the token, the resource names the face.
        assertEquals("Ink's plate has drifted", generatorHex("ink"), hexOf("ic_launcher_background"))
        assertEquals("Paper's plate has drifted", generatorHex("paper"), hexOf("ic_launcher_background_paper"))
        assertEquals("Bloom's plate has drifted", generatorHex("bloom"), hexOf("ic_launcher_background_bloom"))
        assertEquals("Arc's plate has drifted", generatorHex("arcPlate"), hexOf("ic_launcher_background_arc"))
    }
}
