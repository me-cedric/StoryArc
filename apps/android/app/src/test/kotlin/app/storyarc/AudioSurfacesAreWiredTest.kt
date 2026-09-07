package app.storyarc

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That the car shelf is published, and that the publication page is handed its audio.
 *
 * **Both halves were written and neither was called.** `PlaybackHost.publishCarLibrary` had no
 * caller in the shipped app, so a car saw one row whatever the library held.
 * `PublicationDetailScreen` took chapters, a stopped-in part and a chapter verb, and the one
 * call site passed none of them — so four of the five audio scenarios were code no listener
 * could reach. Every unit test, `lint` and both compile gates were green throughout.
 *
 * That is the shape `WhatsNewWiringTest` describes at length one file away, and the reason it
 * reads Kotlin source: `AppShell` and `HostedScreen` are `@Composable`, `:app` declares no
 * Compose test rule, and the instrumented suites that could compose them are compiled by
 * `pnpm build:android:tests` and run by an emulator this gate does not have.
 * `app/build.gradle.kts` declares every `.kt` under the Gradle root as an input of this task,
 * so an edit in another module cannot leave this UP-TO-DATE.
 *
 * A tripwire, not a proof. It asserts that the calls are declared. `CarLibraryTest` pins what
 * a car then sees, and `PublicationChaptersTest` pins what the page then draws.
 */
class AudioSurfacesAreWiredTest {

    @Test
    fun `the shell publishes the car shelf whenever the library changes`() {
        assertTrue(
            "AppShell no longer follows the library for the car shelf. A head unit then lists" +
                " whatever was published last, which in a fresh install is nothing.",
            read(APP_SHELL).contains("CarShelf.follow("),
        )
        assertTrue(
            "CarShelf no longer writes the shelf. PlaybackService reads a file nothing fills," +
                " and a car sees the one row it saw before.",
            read(CAR_SHELF).contains("PlaybackHost.publishCarLibrary("),
        )
    }

    @Test
    fun `the publication page is handed its chapters, the saved part and a way into one`() {
        val screens = read(APP_SCREENS)

        for (argument in listOf("chapters = chapters,", "stoppedIn = stoppedIn,")) {
            assertTrue(
                "The publication page is no longer passed `$argument`. The page then draws no" +
                    " chapter list and marks no part, and its own tests stay green because" +
                    " they compose the pane directly.",
                screens.contains(argument),
            )
        }
        assertTrue(
            "Choosing a chapter no longer starts the book there. The row still draws, and" +
                " pressing it does nothing.",
            screens.contains("host.listenFrom("),
        )
    }

    private fun read(path: String): String {
        val file = File(androidRoot, path)
        if (!file.isFile) error("$path is not under ${androidRoot.absolutePath} — has it moved?")
        return file.readText()
    }

    private companion object {
        const val APP_SHELL = "app/src/main/kotlin/app/storyarc/AppShell.kt"
        const val APP_SCREENS = "app/src/main/kotlin/app/storyarc/AppScreens.kt"
        const val CAR_SHELF = "app/src/main/kotlin/app/storyarc/CarShelf.kt"

        /**
         * The Gradle root, found by walking up from the working directory, per
         * `WhatsNewWiringTest`: the walk stops at the first ancestor holding the settings
         * script, so it cannot climb out of an agent worktree into the parent checkout.
         */
        val androidRoot: File = generateSequence(File("").absoluteFile) { it.parentFile }
            .firstOrNull { File(it, "settings.gradle.kts").isFile }
            ?: error("no settings.gradle.kts above ${File("").absolutePath}")
    }
}
