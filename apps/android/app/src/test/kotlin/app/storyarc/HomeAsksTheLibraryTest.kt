package app.storyarc

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Home asks the library whether a publication can be opened, rather than deciding for itself.
 *
 * Home used to decide, and it got **both** of the two mistakes `isReadableNow` in
 * `:feature:library` was written to prevent. That function's own comment names them: it
 * "deliberately does not use `SourceConnectionState.canFetch`", because every network source
 * is probed when the library appears and treating "still asking" as "cannot be reached" greys
 * the whole shelf on every launch and un-greys it a second later; and it deliberately does not
 * consult the format, because dimming a publication no decoder will open "would conflate 'your
 * network is down' with 'this file is a CB7'". Home's copy read
 * `registry.sources.firstOrNull { … }?.state?.canFetch == true` and `publication.isOpenable`.
 *
 * The cost was measured on an emulator rather than argued about. With a picked folder
 * answering, Home labelled four part-read publications "Can't be opened right now" and went on
 * saying so for fifty-two seconds, while the library one tap away drew the same publications
 * undimmed. Two screens, one question, two answers — and the wrong one was on the screen a
 * reader sees first.
 *
 * This reads Kotlin source, for the reason `ShelvesAskOneRuleTest` gives at length: the thing
 * worth pinning is a property of the **call site**, and a test of `isReadableNow` cannot see
 * who declined to call it. `LibraryMarksTest` already owns the rule's behaviour. `:app`
 * declares no Robolectric or Compose test rule, so composing `HomeDestination` is not
 * available to the unit gate.
 *
 * `app/build.gradle.kts` declares the Kotlin tree as an input of this task, so this fails on
 * an incremental run and not only on a clean one.
 */
class HomeAsksTheLibraryTest {

    private val home = "app/src/main/kotlin/app/storyarc/HomeDestination.kt"

    @Test
    fun `home asks the library whether a publication can be opened`() {
        assertTrue(
            "$home no longer asks host.library.isReadableNow",
            read(home).contains("host.library.isReadableNow("),
        )
    }

    /**
     * And no screen in this module builds the verdict out of a connection state again.
     *
     * `canFetch` is a legitimate question elsewhere — `PublicationProvenance` asks it to
     * decide whether a publication could be downloaded, and `LibraryStates` to decide whether
     * *every* source is down — so this is not a ban on the property. It is a ban on reading it
     * inside `:app`, which is where the second implementation of readability lived and where
     * no screen has any business deciding this at all.
     *
     * Matched on the access rather than the name so the paragraphs above, which say `canFetch`
     * several times, do not fail the test that guards them.
     */
    @Test
    fun `no screen decides readability from a connection state`() {
        val offenders = File(androidRoot, "app/src/main")
            .walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .filter { file ->
                file.readText().contains("state.canFetch") || file.readText().contains("state?.canFetch")
            }
            .map { it.name }
            .toList()
        assertTrue(
            "these read a connection state to decide what a reader may open: $offenders",
            offenders.isEmpty(),
        )
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
