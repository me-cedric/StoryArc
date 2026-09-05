package app.storyarc

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That Android's shell docks **no** bar for a voice, and that the absence stays deliberate.
 *
 * `ebook-reader`'s *The transport on Android*: while a read-aloud session runs and the
 * publication is closed, "the transport is the system media notification and the lock-screen
 * controls the session already publishes", **and** "no docked bar is added inside the app".
 * `read-aloud-beyond-the-reader` task 3.3 asks for that to be *explicitly asserted*, "so the
 * divergence is not read as an omission and 'fixed' later". Until this file it was asserted
 * in a task list and nowhere a build could see.
 *
 * ## The reason 3.3 gave has since been falsified, and the requirement has not
 *
 * 3.3 argued the absence from the platform: "Material has no persistent accessory slot above a
 * navigation bar, so an in-app bar would be a control invented to make two screenshots match."
 * That was true when it was written and is not true now. `audiobooks-and-playback` built
 * exactly such a slot — `StoryArcScaffold`'s `aboveNavigation`, holding a `CompactPlayerBar`
 * for a narrated audiobook — because `audio-playback` requires one. So the platform argument
 * is spent: the slot exists, it works, and a voice is kept out of it by one thing only.
 *
 * **That one thing is an accident of the engine split, not a decision.** The bar reads
 * `PlaybackHost.nowPlaying`, and `PlaybackHost` drives media3; a voice lives in
 * `ReadAloudHost` behind Readium and a service of its own. `audiobooks-and-playback` task 6.1
 * is to collapse the two engines. **On the day it does, a read-aloud session starts appearing
 * in this bar and the requirement above is reversed by a merge nobody read as a product
 * change** — every unit suite, `lint` and both compile gates staying green throughout. That is
 * precisely the failure 3.3 named, arriving from the direction 3.3 did not expect.
 *
 * So this asserts the outcome rather than the reason: no read-aloud transport is composed in
 * `:app`. A change that wants one has to delete a test whose message says what it is deleting,
 * which is the whole ask.
 *
 * ## What this is not
 *
 * It reads Kotlin source, for the reason [WhatsNewWiringTest] sets out at length: `AppShell` is
 * `@Composable`, `:app` declares no Robolectric or Compose rule, and the instrumented tests
 * that could compose it are compiled by `pnpm build:android:tests` and run by nothing. It
 * asserts an absence in a file; it never asserts a screen. The evidence that a listener with
 * the reader closed sees a notification and no bar is `read-aloud-beyond-the-reader` task 3.1's
 * emulator capture, and this does not stand in for it.
 *
 * **Proved able to fail**, per AGENTS.md §5, one mutation per test and each one compiling —
 * a mutation the compiler rejects proves the compiler, not the test:
 *
 * - a `private const val` in `AppShell.kt` whose value is the string `"ReadAloudBar"` failed
 *   *the shell docks no transport for a voice*;
 * - replacing the whole `aboveNavigation` argument with `{}` — it defaults to `{}`, so this
 *   compiles — failed *the compact bar above the navigation is fed by the audiobook host
 *   alone*;
 * - *the in-reader bar stays in the reader* failed on its own first run, before the filter
 *   below excluded declarations: `ReadAloudBar.kt` names `ReadAloudBar(` to declare it, and
 *   the test reported that file as a composer.
 *
 * Worth stating about the first: all four symbols are `internal` to `:feature:epubreader`
 * today, so the module system already stops `:app` naming them. That assertion is for the day
 * one of them is made `public` — which is step one of adding the bar, and the step a reviewer
 * reads as harmless.
 */
class ReadAloudAddsNoBarTest {

    @Test
    fun `the shell docks no transport for a voice`() {
        val shell = codeOnly(read(APP_SHELL))

        for (symbol in READ_ALOUD_SYMBOLS) {
            assertTrue(
                "$APP_SHELL names $symbol in code. `ebook-reader`'s *The transport on" +
                    " Android* says \"no docked bar is added inside the app\" while a voice" +
                    " speaks — the transport there is the media notification and the lock" +
                    " screen, which survive the app being backgrounded as a bar cannot." +
                    " If a voice is meant to take the compact bar now, that is a product" +
                    " change to `ebook-reader`, not a wiring change: propose it, then delete" +
                    " this test in the same pass.",
                !shell.contains(symbol),
            )
        }
    }

    @Test
    fun `the compact bar above the navigation is fed by the audiobook host alone`() {
        val shell = codeOnly(read(APP_SHELL))

        // The positive half of the same claim. Without it, deleting `CompactPlayerBar`
        // outright would satisfy the negative assertion above — the mutation that makes a
        // negative test worthless on its own. `audio-playback` requires the bar for a
        // narrated book; this change requires it to carry nothing else.
        assertTrue(
            "$APP_SHELL no longer composes CompactPlayerBar. `audio-playback` requires a" +
                " compact bar above the navigation while a narrated book plays.",
            shell.contains("CompactPlayerBar("),
        )
        assertTrue(
            "$APP_SHELL no longer reads PlaybackHost.nowPlaying for the bar above the" +
                " navigation. That reader is what keeps a voice out of the slot: a voice" +
                " runs on ReadAloudHost and a narrated file on PlaybackHost, and the day" +
                " those engines merge (audiobooks-and-playback 6.1) this line is where" +
                " read-aloud starts appearing in a bar that ebook-reader forbids it.",
            shell.contains("PlaybackHost.nowPlaying"),
        )
    }

    @Test
    fun `the in-reader bar stays in the reader`() {
        // `ReadAloudBar` is in-reader chrome and is meant to stay there: on screen only while
        // the book is open, beside the return control. `ReaderChromeTest` keeps it off the
        // page's own two-control overlay; this keeps it from being promoted out of the module
        // altogether, which is the shape "adding a docked bar" would actually take.
        // The declaration is not a call site, and `ReadAloudBar.kt` necessarily holds one.
        val composers = epubReaderSources()
            .filter { file ->
                codeOnly(file.readText())
                    .lineSequence()
                    .any { it.contains("ReadAloudBar(") && !it.contains("fun ReadAloudBar(") }
            }
            .map { it.name }
            .sorted()

        assertTrue(
            "ReadAloudBar is composed by $composers. It is in-reader chrome and only" +
                " EpubReaderOverlays.kt may compose it — a call site anywhere else is the" +
                " first step of promoting it into a persistent transport, which" +
                " ebook-reader's *The transport on Android* forbids.",
            composers == listOf("EpubReaderOverlays.kt"),
        )
    }

    // Reading the tree

    private fun read(path: String): String {
        val file = File(androidRoot, path)
        if (!file.isFile) {
            error("$path is not under ${androidRoot.absolutePath} — has it moved?")
        }
        return file.readText()
    }

    /** Every Kotlin source in `:feature:epubreader`, so a new file is covered unnamed. */
    private fun epubReaderSources(): List<File> {
        val directory = File(androidRoot, EPUB_READER)
        val sources = directory.listFiles { file: File -> file.name.endsWith(".kt") }?.toList()
            ?: error("${directory.absolutePath} could not be listed — has :feature:epubreader moved?")
        assertTrue("Only ${sources.size} sources found in :feature:epubreader. Suspicious.", sources.size > 5)
        return sources
    }

    /**
     * A source's text with every comment line removed.
     *
     * The precision that makes these assertions mean anything: this file's own subjects are
     * discussed at length in the prose of the files it reads — `AppShell.kt`'s slot comment
     * and `EpubReaderOverlays.kt`'s — and a naive search would fail on the paragraph
     * explaining the rule while a real call site went unnoticed. Same helper, same crudeness
     * and same direction of crudeness as [WhatsNewWiringTest]: a trailing comment on a line of
     * code survives, so keeping too much fails loudly rather than passing quietly.
     */
    private fun codeOnly(text: String): String {
        var inBlock = false
        val kept = mutableListOf<String>()
        for (raw in text.lineSequence()) {
            val line = raw.trim()
            if (inBlock) {
                if (line.contains("*/")) inBlock = false
                continue
            }
            if (line.startsWith("/*")) {
                if (!line.contains("*/")) inBlock = true
                continue
            }
            if (line.startsWith("//") || line.startsWith("*")) continue
            kept += line
        }
        return kept.joinToString("\n")
    }

    private companion object {
        const val APP_SHELL = "app/src/main/kotlin/app/storyarc/AppShell.kt"
        const val EPUB_READER = "feature/epubreader/src/main/kotlin/app/storyarc/feature/epubreader"

        /**
         * Every way `:app` could reach the voice.
         *
         * The host is the session, the bar is the in-reader chrome, and the controller is the
         * engine. Any of the three appearing in the shell is the shell taking an interest in
         * read-aloud, which is the thing being forbidden.
         */
        val READ_ALOUD_SYMBOLS = listOf(
            "ReadAloudHost",
            "ReadAloudBar",
            "ReadAloudController",
            "ReadAloudService",
        )

        /**
         * The Gradle root, found by walking up from the working directory, per
         * `ShelvesAskOneRuleTest`: the walk starts inside `:app` and stops at the first
         * ancestor holding the settings script, so it cannot climb out of an agent worktree
         * into the parent checkout.
         */
        val androidRoot: File = generateSequence(File("").absoluteFile) { it.parentFile }
            .firstOrNull { File(it, "settings.gradle.kts").isFile }
            ?: error("no settings.gradle.kts above ${File("").absolutePath}")
    }
}
