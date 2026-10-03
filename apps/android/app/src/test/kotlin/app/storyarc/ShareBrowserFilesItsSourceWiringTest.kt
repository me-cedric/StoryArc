package app.storyarc

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A reader opened from a share's own browser is filed under that share, so it can report the
 * share unreachable when the path moves. A source guard, for the reason
 * `AddSourceStartsAReadWiringTest` gives: the screen needs a live `AppHost`.
 */
class ShareBrowserFilesItsSourceWiringTest {

    @Test
    fun `the share browser files what it opens under its share`() {
        val file = File(androidRoot, "app/src/main/kotlin/app/storyarc/AppScreens.kt")
        assertTrue("AppScreens.kt has moved; this test names it by path", file.isFile)
        assertTrue(
            "The share browser opens a publication without filing it under its share.",
            file.readText().contains("host.open(screen.page.filing(publication), path)"),
        )
    }

    private companion object {
        val androidRoot: File = generateSequence(File("").absoluteFile) { it.parentFile }
            .firstOrNull { File(it, "settings.gradle.kts").isFile }
            ?: error("no settings.gradle.kts above ${File("").absolutePath}")
    }
}
