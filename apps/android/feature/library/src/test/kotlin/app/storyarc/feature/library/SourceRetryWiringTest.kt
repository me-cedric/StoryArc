package app.storyarc.feature.library

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That the two occasions `sources` names really do reach the decision that was written for
 * them, and that the backoff loop really does ask whether anyone is reading.
 *
 * `SourceReachabilityTest` in `:core:model` pins the decisions themselves -- sixteen cases,
 * mirrored name for name with iOS's `SourceReachabilityTests`. Every one of them passed for
 * as long as **nothing called any of them**, which is exactly the shape of the hole this
 * change exists to close: a guard that is asserted and never consulted is indistinguishable
 * from a guard that works.
 *
 * **So this test reads the source text, and that is a deliberate second choice**, for
 * `SmbTransferWiringTest`'s reason. The honest test drops a real network under a real device
 * and watches whether a request goes out; `ConnectivityManager.NetworkCallback` needs both,
 * and a test that needs a device is a test nobody runs -- which is the same argument that put
 * `SourceReachability` in `:core:model` in the first place. A guard that runs beats a better
 * one that does not.
 *
 * **What text may honestly say.** Not that the behaviour is right: it may say that a call
 * exists, that a call does *not* exist, and that one call sits inside another. Each assertion
 * below was checked by making the mutation it names and watching this test fail.
 */
class SourceRetryWiringTest {

    private fun read(path: String): String {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:library:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(module, path)
        if (!file.isFile) error("$path is not under ${module.absolutePath} — has it moved?")
        return file.readText()
    }

    private val retry: String by lazy { read(RETRY_SOURCE) }
    private val triggers: String by lazy { read(TRIGGERS_SOURCE) }

    /** The body of the backoff loop, from its `while` to the end of the function. */
    private val loop: String by lazy {
        val start = retry.indexOf("while (isActive)")
        val end = retry.indexOf("fun LibraryViewModel.stopRetrying()")
        if (start < 0 || end < start) error("SourceRetry.kt no longer has the backoff loop")
        retry.substring(start, end)
    }

    @Test
    fun `the backoff loop asks whether a reader is reading, after the wait`() {
        // The defect, exactly: the loop probed every configured server every 5 s, then 10, up
        // to every 5 minutes, straight through a chapter. `sources`' automatic recovery
        // "does not present a notification or interrupt reading".
        val wait = loop.indexOf("delay(SourceProbe.delayAfter(")
        val guard = loop.indexOf("if (isReading()) continue")
        val probe = loop.lastIndexOf("probeAndWait(")
        assertTrue("The loop no longer waits on SourceProbe.delayAfter.", wait >= 0)
        assertTrue(
            "The backoff loop does not consult isReading(). `sources` forbids automatic" +
                " recovery from interrupting reading, and this loop runs while a reader is" +
                " on a page.",
            guard >= 0,
        )
        assertTrue(
            "isReading() is asked before the wait rather than after it. A reader opens a" +
                " publication *while* the loop is waiting, so an answer from five minutes" +
                " ago is the wrong one.",
            guard > wait && guard < probe,
        )
    }

    @Test
    fun `an unprompted probe goes through the decision that holds the reading guard`() {
        val start = retry.indexOf("fun LibraryViewModel.probe(")
        assertTrue("SourceRetry.kt no longer has probe().", start >= 0)
        val body = retry.substring(start)
        val decision = body.indexOf("SourceReachability.shouldProbe(")
        val probe = body.indexOf("probeAndWait(")
        assertTrue(
            "A trigger reaches probeAndWait without passing SourceReachability.shouldProbe," +
                " which is where the reading guard, the \"something is away\" condition and" +
                " the refused-credential clause all live.",
            decision >= 0 && decision < probe,
        )
    }

    @Test
    fun `both occasions are reported through one call`() {
        // One call site, deliberately. `RetryTrigger` names two occasions as one type
        // precisely so that a third cannot be added without answering the same question, and
        // two call sites is how one of them ends up without the guard.
        assertEquals(
            "SourceRetryTriggers should hand every occasion to the same reporter.",
            2,
            triggers.split("latest(").size - 1,
        )
        assertTrue(
            "SourceRetryTriggers decides for itself. It must report the occasion and let" +
                " SourceReachability.shouldProbe decide — see LibraryViewModel.probe.",
            !triggers.contains("shouldProbe("),
        )
    }

    @Test
    fun `a regained network is read as an edge, not as every path report`() {
        // A monitor reports every change — one Wi-Fi swapped for another, a VPN attaching.
        // `SourceReachability.triggers` is the edge detector; collecting NetworkPaths without
        // it would turn "retries immediately, once" into a probe per hop.
        assertTrue(
            "The connectivity signal must reach SourceReachability.triggers rather than" +
                " being acted on report by report.",
            triggers.contains("SourceReachability.triggers(NetworkPaths.satisfied("),
        )
    }

    @Test
    fun `the connectivity signal is collected only while the activity is started`() {
        // The reading guard's other half. The EPUB reader is an activity of its own, so while
        // a reader is in a chapter the navigation state this app can see holds a library, not
        // a book: `isReading()` answers false and cannot answer otherwise. Suspending the
        // collection is what keeps a dropped Wi-Fi mid-chapter from probing every server.
        assertTrue(
            "SourceRetryTriggers collects the connectivity signal outside" +
                " repeatOnLifecycle(STARTED), so it keeps firing while the EPUB reader — an" +
                " activity of its own — is in front of this one.",
            triggers.contains("repeatOnLifecycle(Lifecycle.State.STARTED)"),
        )
    }

    @Test
    fun `returning to the foreground is its own trigger`() {
        // It is *not* the effect above restarting. That restarts on start, and for a rotation
        // too, so it says nothing about the app having been away. iOS made the identical
        // mistake in prose: `retryUnreachableSources` claimed returning to the foreground was
        // free because "returning is what starts it again", and a `.task` fires on appear.
        assertTrue(
            "Nothing fires RETURNED_TO_FOREGROUND. One of the two occasions `sources` names" +
                " is missing, which is the state both platforms were in until 2026-09-03.",
            triggers.contains("RetryTrigger.RETURNED_TO_FOREGROUND"),
        )
        assertTrue(
            "The foreground trigger is not tied to a resume.",
            triggers.contains("Lifecycle.Event.ON_RESUME"),
        )
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"
        const val RETRY_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/SourceRetry.kt"
        const val TRIGGERS_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/SourceRetryTriggers.kt"
    }
}
