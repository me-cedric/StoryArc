package app.storyarc.feature.library

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That the share browser still *asks* before it fetches a whole publication, and still routes
 * both decisions through the pair a test can drive.
 *
 * `StreamingOfferTest` pins the rule -- what the app owes a reader for a publication it cannot
 * read where it lies. `ShareOpeningTest` pins what the browser feeds that rule and what it
 * does with the answer, by calling `offerOrOpen` and `openWhatArrived` directly. Neither can
 * pin the wiring, and the wiring is where the defect lived: `openFromShare` copied the entire
 * file down whenever the format's decoder wanted a path, with `entry.length` already in hand
 * and nothing said to the reader.
 *
 * **So this test reads the source text, and that is a deliberate second choice**, for
 * `:feature:epubreader`'s `ReaderChromeWiringTest`'s reason. The honest test drives the
 * browser against a real share and watches what crosses the wire, which needs `pnpm smb`
 * and a booted emulator; `.github/workflows/android.yml` boots one for
 * `:core:format:connectedDebugAndroidTest` and nothing else. A guard that runs beats a better
 * one that does not.
 *
 * **What it is allowed to assert, and what it is not.** Its earlier form claimed to check
 * that "what arrives is judged before the reader is sent to it" and actually checked that
 * `StreamingOffer.of(` appeared before `onOpen(` in the file. Deleting the judgement and
 * calling `onOpen` unconditionally kept that order and passed. Textual order is not a
 * behaviour, so the behaviour is asserted in `ShareOpeningTest` and what is left here is the
 * one thing text can honestly say: that the composable delegates instead of deciding for
 * itself. iOS keeps the same guard in `SmbTransferWiringTests.swift`.
 */
class SmbTransferWiringTest {

    /**
     * The browser's source, at the path the module's build script hands to the test JVM.
     *
     * Deliberately not discovered, and [MODULE_DIRECTORY] is set from `projectDir` in
     * `build.gradle.kts` -- which is the module being built by construction. Missing is a
     * failure rather than a skip: a guard that cannot find what it guards has to say so, or it
     * passes forever after the file is renamed.
     */
    private val source: String by lazy {
        val module = System.getProperty(MODULE_DIRECTORY)?.let(::File)
            ?: error(
                "$MODULE_DIRECTORY is unset. This test reads the module's own source and will" +
                    " not go looking for it elsewhere — run it through Gradle" +
                    " (`pnpm gradle :feature:library:testDebugUnitTest`), which sets the" +
                    " property from the module directory.",
            )
        val file = File(module, BROWSER_SOURCE)
        if (!file.isFile) {
            error("$BROWSER_SOURCE is not under ${module.absolutePath} — has it moved?")
        }
        file.readText()
    }

    /** Everything the tap reaches before the reader has answered anything. */
    private val beforeTheAnswer: String by lazy {
        val start = source.indexOf("fun openOrOffer(")
        val end = source.indexOf("fun transfer(")
        if (start < 0 || end < start) {
            error("SmbBrowserScreen no longer has both openOrOffer and transfer")
        }
        source.substring(start, end)
    }

    @Test
    fun `a tap on a share transfers nothing`() {
        // The regression, exactly: a whole-file copy reachable from the tap. `network-share`
        // asks the first page of a 400 MB comic to cost megabytes, and `publication-formats`
        // asks for an offer before the ones that cannot be read that way.
        assertTrue(
            "SmbBrowserScreen fetches from the tap again. The transfer belongs behind the" +
                " reader's answer to smb_download_first_title — `publication-formats`" +
                " requires the app to state the size and \"offer to download it\", not to" +
                " take it.",
            !beforeTheAnswer.contains("fetchAndIndex("),
        )
    }

    @Test
    fun `both decisions go through the pair that is tested`() {
        // Once for what was found on the share, once for what arrived from it. Deciding
        // inline again is what put the judgement somewhere only a text search could reach.
        assertEquals(
            "The tap should reach offerOrOpen, which ShareOpeningTest drives.",
            1,
            source.split("offerOrOpen(").size - 1,
        )
        assertEquals(
            "The transfer's answer should reach openWhatArrived, which ShareOpeningTest" +
                " drives.",
            1,
            source.split("openWhatArrived(").size - 1,
        )
    }

    @Test
    fun `the browser never opens a publication it decided about itself`() {
        // The mutation this test exists for: calling `onOpen(publication, local)` from the
        // composable bypasses the tested decision entirely, and `ShareOpeningTest` would stay
        // green because the function it drives is still correct. `onOpen = onOpen` as an
        // argument is not a call and does not match.
        assertTrue(
            "SmbBrowserScreen invokes onOpen itself. Opening belongs to offerOrOpen and" +
                " openWhatArrived, which judge the publication first — see ShareOpeningTest.",
            !source.contains("onOpen("),
        )
    }

    @Test
    fun `the size is stated before the transfer is agreed to`() {
        assertTrue(
            "The dialog must state the size the share reported, through the same call the" +
                " metered confirmation and the storage rows use.",
            source.contains("R.string.smb_download_first_body") &&
                source.contains("Formatter.formatShortFileSize("),
        )
    }

    @Test
    fun `a share that stated no size has a sentence of its own`() {
        // `offline-downloads` asks for an absence rather than a zero, and the dialog formats
        // a non-optional Long — so without this branch a zero-length entry reads "0 B".
        assertTrue(
            "The download offer must have the second body the metered confirmation already" +
                " has, for the entry whose length the share did not state.",
            source.contains("R.string.smb_download_first_body_unstated"),
        )
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"
        const val BROWSER_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/SmbBrowserScreen.kt"
    }
}
