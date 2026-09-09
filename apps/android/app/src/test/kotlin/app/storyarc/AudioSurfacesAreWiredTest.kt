package app.storyarc

import java.io.File
import org.junit.Assert.assertFalse
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

    /**
     * That the marked part and the primary action answer from one store.
     *
     * The page used to read `PlaybackHost.lastPosition`, and `PlaybackMemory` behind it holds
     * the last book played and nothing else — so a second started audiobook drew an unmarked
     * chapter list while the progress store held its position, and the action, which reads
     * that store, named a chapter the marks disagreed with.
     */
    @Test
    fun `the marked part is read from the progress store, per publication`() {
        val screens = read(APP_SCREENS)

        assertTrue(
            "The publication page no longer asks the progress store where this publication" +
                " stopped. Only the last book played is then marked.",
            screens.contains("host.dependencies.progress.progress(publication.identity)"),
        )
        assertTrue(
            "The page no longer reads the store through `ListenedPosition.resume`. The marks" +
                " and the primary action can then name different chapters.",
            screens.contains("ListenedPosition.resume(listened?.position"),
        )
        // **Both assertions above pin a read and neither pinned the wiring.** Deleting
        // `?: saved` stops the store's answer reaching the screen, and this suite stayed
        // green through it. That is the gap this feature was faulted for once already.
        assertTrue(
            "The store's answer no longer reaches `stoppedIn`, so the page marks only the" +
                " book that is playing.",
            screens.contains("?.partIndex ?: saved"),
        )
        assertTrue(
            "The store is no longer re-read when the session changes, so the mark goes stale" +
                " the moment a listener stops without leaving the page.",
            screens.contains("LaunchedEffect(publication.id, playing)"),
        )
    }

    /**
     * `audio-playback`, *Where a listening position is written*: the three moments only the
     * app layer can see, and the one that used to read a snapshot instead of the player.
     *
     * `RecordedPositionTest` pins what each write then stores. This asserts that the calls
     * exist at all, which is the half the shipped app got wrong: the tick was wired and read
     * `nowPlaying`, and nothing was wired to a pause, a settled scrub or the background.
     */
    @Test
    fun `the app writes a listening position at the moments only it can see`() {
        val ticker = read(PLAYING_BOOK)
        assertTrue(
            "The tick no longer asks the player where it is, so a book playing through one" +
                " long file writes the offset it started at.",
            ticker.contains("PlaybackHost.recordReached()"),
        )
        assertFalse(
            "The tick builds a position out of `nowPlaying` again, which only moves when the" +
                " player raises a callback — see `RecordedPositionTest`.",
            ticker.contains("PlaybackPosition(playing.partIndex"),
        )
        assertTrue(
            "Nothing writes the position when the activity leaves the foreground, which is" +
                " the last moment before the system may reclaim the process.",
            read(MAIN_ACTIVITY).contains("override fun onStop()"),
        )
        assertTrue(
            "The scrub no longer writes when the drag settles, so a place the listener chose" +
                " waits for the floor.",
            read(APP_SCREENS).contains("onSeekSettled = PlaybackHost::recordReached"),
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
        const val PLAYING_BOOK = "app/src/main/kotlin/app/storyarc/PlayingBook.kt"
        const val MAIN_ACTIVITY = "app/src/main/kotlin/app/storyarc/MainActivity.kt"

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
