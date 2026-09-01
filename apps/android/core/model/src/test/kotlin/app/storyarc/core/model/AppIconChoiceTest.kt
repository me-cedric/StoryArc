package app.storyarc.core.model

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The five faces and the components that draw them.
 *
 * iOS's `AppIconChoiceTests` asserts the same table, bar the component names — that platform
 * has an API and needs no aliases. The names are the load-bearing part on this side: nothing
 * in the compiler connects `MainActivityPaper` here to an `<activity-alias>` in the manifest,
 * which is what `AppIconManifestTest` is for.
 */
class AppIconChoiceTest {

    @Test
    fun `five faces, in the order the chooser draws them`() {
        assertEquals(
            listOf(
                AppIconChoice.INK,
                AppIconChoice.PAPER,
                AppIconChoice.BLOOM,
                AppIconChoice.ARC,
                AppIconChoice.MONO,
            ),
            AppIconChoice.entries.toList(),
        )
    }

    @Test
    fun `Ink is the default, and it is the only one that says so`() {
        assertEquals(AppIconChoice.INK, AppIconChoice.DEFAULT)
        assertTrue(AppIconChoice.INK.isDefault)
        AppIconChoice.entries.filter { it != AppIconChoice.INK }.forEach {
            assertFalse("$it claims to be the default", it.isDefault)
        }
    }

    /**
     * **No face may name the activity the aliases point at**, and this is the assertion that
     * stops the whole feature bricking the app.
     *
     * An `<activity-alias>` whose target is disabled stops resolving: with `MainActivity` off,
     * `am start` on an enabled alias left no process and the MAIN/LAUNCHER intent answered
     * "unable to resolve", while the launcher went on drawing the icon it had cached. Task 4.5
     * asks for the default to *be* `MainActivity`, which is exactly the shape that breaks — so
     * every face is an alias of its own and the target is never written to.
     */
    @Test
    fun `no face names the activity the aliases point at`() {
        assertEquals("app.storyarc.MainActivity", AppIconChoice.TARGET_ACTIVITY)
        AppIconChoice.entries.forEach {
            assertNotEquals(
                "$it names the alias target; disabling it makes the app unlaunchable",
                AppIconChoice.TARGET_ACTIVITY,
                it.componentClassName,
            )
        }
        assertEquals("app.storyarc.MainActivityInk", AppIconChoice.INK.componentClassName)
    }

    @Test
    fun `every face names its own component, and no two share one`() {
        val names = AppIconChoice.entries.map { it.componentClassName }
        assertEquals(names.size, names.toSet().size)
        names.forEach { assertTrue("$it is not in the app's package", it.startsWith("app.storyarc.")) }
        assertEquals("app.storyarc.MainActivityPaper", AppIconChoice.PAPER.componentClassName)
        assertEquals("app.storyarc.MainActivityBloom", AppIconChoice.BLOOM.componentClassName)
        assertEquals("app.storyarc.MainActivityArc", AppIconChoice.ARC.componentClassName)
        assertEquals("app.storyarc.MainActivityMono", AppIconChoice.MONO.componentClassName)
    }

    /**
     * The chooser stores nothing, but the type is serialisable because a diagnostic or a
     * what-changed note may name it. Asserted so the wire form cannot drift into something a
     * future reader has to guess at. Not the same casing iOS writes, and deliberately not:
     * nothing crosses between the platforms, and [AppearanceMode] already differs the same
     * way for the same reason.
     */
    @Test
    fun `the wire form is the face name`() {
        AppIconChoice.entries.forEach { face ->
            val json = Json.encodeToString(AppIconChoice.serializer(), face)
            assertEquals("\"${face.name}\"", json)
            assertEquals(face, Json.decodeFromString(AppIconChoice.serializer(), json))
        }
    }
}
