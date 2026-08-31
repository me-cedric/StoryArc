package app.storyarc.feature.library

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * That the share browser still *asks* before it fetches a whole publication.
 *
 * `StreamingOfferTest` pins the rule -- what the app owes a reader for a publication it cannot
 * read where it lies. It cannot pin the wiring, and the wiring is where the defect lived:
 * `openFromShare` copied the entire file down whenever the format's decoder wanted a path,
 * with `entry.length` already in hand and nothing said to the reader. Putting that copy back
 * inside the tap leaves `StreamingOffer` compiled, used elsewhere, and every one of its own
 * tests green.
 *
 * **So this test reads the source text, and that is a deliberate second choice**, for
 * `:feature:epubreader`'s `ReaderChromeWiringTest`'s reason. The honest test drives the
 * browser against a real share and watches what crosses the wire, which needs `pnpm smb`
 * and a booted emulator; `.github/workflows/android.yml` boots one for
 * `:core:format:connectedDebugAndroidTest` and nothing else. A guard that runs beats a better
 * one that does not. It is a tripwire, not a proof: it says the transfer is behind the
 * reader's answer, never that the dialog rendered. iOS keeps the same guard in
 * `SmbTransferWiringTests.swift`.
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
    fun `the offer that does the deciding is the shared rule`() {
        // Twice: once for what was found on the share, once for what arrived from it.
        val decisions = source.split("StreamingOffer.of(").size - 1
        assertEquals(
            "SmbBrowserScreen should ask StreamingOffer twice — what to do with what it found" +
                " on the share, and whether what arrived can be opened.",
            2,
            decisions,
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
    fun `what arrives is judged before the reader is sent to it`() {
        val transfer = source.substring(source.indexOf("fun transfer("))
        val decision = transfer.indexOf("StreamingOffer.of(")
        val opening = transfer.indexOf("onOpen(")
        // A solid RAR4 indexes as REFUSED only once its bytes are local, so this order is the
        // whole of "does not hold for solid RAR4, which is refused whether local or remote".
        // Opening first is what used to send a reader who had waited for the file to a reader
        // that cannot render page one.
        assertTrue(
            "transfer opens the publication before asking whether it can be opened.",
            decision >= 0 && opening >= 0 && decision < opening,
        )
    }

    private companion object {
        /** Set by this module's `build.gradle.kts`, from its own `projectDir`. */
        const val MODULE_DIRECTORY = "storyarc.library.projectDir"
        const val BROWSER_SOURCE =
            "src/main/kotlin/app/storyarc/feature/library/SmbBrowserScreen.kt"
    }
}
