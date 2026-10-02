package app.storyarc

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A continuity handover or quick action that names a publication no longer on the shelf must
 * not leave the reader stranded: giving up has to land somewhere.
 *
 * `:app` declares no Robolectric or Compose test rule — `HomeAsksTheLibraryTest` says why —
 * so this reads the wait inside `AppIntents` as text, the way that test reads `HomeDestination`.
 *
 * 19.4: before this, the wait for `wanted` set `wanted = null` on giving up and called nothing,
 * and a publication whose location could not be resolved opened nothing either. On a cold
 * launch with an empty shelf, or a publication the library could not place, the reader was
 * left on whichever destination the app happened to open to rather than on the library.
 */
class AppIntentsLandOnLibraryTest {

    private val path = "app/src/main/kotlin/app/storyarc/AppIntents.kt"

    @Test
    fun `giving up after the resolve attempts lands on the library`() {
        val wait = waitBlock()
        assertTrue(
            "$path: the resolve loop giving up no longer lands the reader on the library",
            wait.trim().endsWith("host.navigate { open(AppDestination.LIBRARY) }"),
        )
    }

    @Test
    fun `a publication with no resolvable location also lands on the library`() {
        val wait = waitBlock()
        // Twice: once for a location the library could not resolve, once for giving up —
        // both are "this reader is not getting into a reader", and both get the same landing.
        assertTrue(
            "$path: a publication the library cannot place a location for opens nothing and goes nowhere",
            wait.contains("if (location != null)") &&
                wait.split("host.navigate { open(AppDestination.LIBRARY) }").size == 3,
        )
    }

    private fun waitBlock(): String {
        val source = read(path)
        val start = source.indexOf("LaunchedEffect(wanted) {")
        assertTrue("$path: the wait for `wanted` is gone", start >= 0)
        val end = source.indexOf("\n    }", start)
        assertTrue("$path: the wait's closing brace could not be found", end >= 0)
        return source.substring(start, end)
    }

    private fun read(path: String): String {
        val file = File(androidRoot, path)
        assertTrue("$path has moved; this test names it by path", file.isFile)
        return file.readText()
    }

    private companion object {
        /**
         * `apps/android`, found rather than hardcoded — the first ancestor holding the settings
         * file. Nothing above `apps/android` has one; the repository's build is pnpm's.
         */
        val androidRoot: File = generateSequence(File("").absoluteFile) { it.parentFile }
            .firstOrNull { File(it, "settings.gradle.kts").isFile }
            ?: error("no settings.gradle.kts above ${File("").absolutePath}")
    }
}
