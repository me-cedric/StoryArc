package app.storyarc

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That the shell docks **one** compact bar, and that a voice is never given a second one.
 *
 * ## What this file used to be, and why it is not that any more
 *
 * It was `ReadAloudAddsNoBarTest`, and it guarded the opposite rule. `ebook-reader`'s *The
 * transport on Android* ended "no docked bar is added inside the app" while a voice speaks,
 * and `read-aloud-beyond-the-reader` task 3.3 asked for that absence to be *explicitly
 * asserted*, "so the divergence is not read as an omission and 'fixed' later". Three claims
 * enforced it: that `:app` named no read-aloud symbol at all, that the slot above the
 * navigation still read `PlaybackHost.nowPlaying`, and that `ReadAloudBar` stayed inside the
 * reader.
 *
 * **The owner reversed the requirement on 2026-09-05, and the amended delta carries the
 * reasoning in full.** In short: the forbidding clause was written when the voice had no bar
 * to appear in — Material had no persistent slot above a navigation bar, so an in-app bar
 * would have been a control invented to make two screenshots match. `audiobooks-and-playback`
 * then built the slot, because `audio-playback` requires a compact bar above the navigation
 * whenever something plays. So the clause encoded an implementation accident rather than an
 * intent about readers, and a listener who has left the reader wants the same transport
 * whichever of the two is speaking. *The transport on Android* now asks for the bar **and**
 * the media notification, and the requirement's prose forbids only a *second* bar.
 *
 * ### The one assertion that was deleted rather than rewritten
 *
 * The old second test asserted that the slot still reads `PlaybackHost.nowPlaying` — a
 * single-engine feed — and its failure message said that line "is where read-aloud starts
 * appearing in a bar that ebook-reader forbids it". Under the amended requirement that line
 * is where read-aloud must *start* appearing, so the assertion now guards the defect. It is
 * gone, and nothing replaces it here: **what it was watching for is now work rather than a
 * violation**, and work belongs in a task list. `audiobooks-and-playback` task 6.1 owns it,
 * and `read-aloud-beyond-the-reader` task 3.3 records that Android does not yet meet the
 * amended requirement.
 *
 * The old first test also forbade `:app` naming `ReadAloudHost`, `ReadAloudController` and
 * `ReadAloudService`. That went with it, and deliberately: under the amended rule the shell
 * taking an interest in the voice is no longer forbidden — feeding one bar from a surface
 * that spans both engines may well require it — and a test that blocked the compliant
 * implementation would be the old rule wearing a new name. Only [ReadAloudBar] is still
 * refused in the shell, because composing the *reader's own* bar outside the reader is the
 * second transport, which is the thing the amended requirement forbids by name.
 *
 * ## What is asserted now
 *
 * One bar exists and exactly one is composed; no second one is grown for the voice; and the
 * in-reader chrome stays in the reader.
 *
 * ## What this is not
 *
 * It reads Kotlin source, for the reason [WhatsNewWiringTest] sets out at length: `AppShell`
 * is `@Composable`, `:app` declares no Robolectric or Compose rule, and the instrumented
 * tests that could compose it are compiled by `pnpm build:android:tests` and run by nothing.
 * It asserts an absence in a file; it never asserts a screen. The evidence that a listener
 * with the reader closed sees one bar and a notification is
 * `read-aloud-beyond-the-reader` task 3.1's emulator capture, and this does not stand in for
 * it.
 *
 * **Proved able to fail**, per AGENTS.md §5, one mutation per assertion and each one
 * compiling — a mutation the compiler rejects proves the compiler, not the test:
 *
 * - replacing the whole `aboveNavigation` argument with `{}` — it defaults to `{}`, so this
 *   compiles — failed *the shell docks exactly one compact bar* with a count of 0;
 * - a second `CompactPlayerBar(` call inside the same slot failed it with a count of 2;
 * - a `private const val` in `AppShell.kt` whose value is the string `"ReadAloudBar"` failed
 *   *the shell grows no second bar for the voice*;
 * - a `ReadAloudBar(` call added to `EpubChrome.kt` failed *the in-reader bar stays in the
 *   reader*. That test also failed on its own first run under the old file name, before the
 *   filter below excluded declarations: `ReadAloudBar.kt` names `ReadAloudBar(` to declare
 *   it, and the test reported that file as a composer.
 */
class OneCompactBarTest {

    @Test
    fun `the shell docks exactly one compact bar`() {
        val shell = codeOnly(read(APP_SHELL))

        // `audio-playback` requires a compact bar above the navigation whenever something is
        // playing, and `ebook-reader`'s *The transport outside the reader* now requires the
        // voice to take that same one. Exactly one composition is the whole of "the same
        // one": zero is the bar removed, and two is the second transport a listener would
        // have to learn.
        val composed = shell.split("CompactPlayerBar(").size - 1
        assertEquals(
            "$APP_SHELL composes CompactPlayerBar $composed time(s), not once." +
                " `audio-playback` requires a compact bar above the navigation while" +
                " something plays, and `ebook-reader`'s *The transport outside the reader*" +
                " requires a read-aloud session to take that same bar — \"the app SHALL NOT" +
                " draw a second bar for the voice, nor withhold the one it has from it\"." +
                " Zero means the bar is gone; two means the app grew a second transport.",
            1,
            composed,
        )
    }

    @Test
    fun `the shell grows no second bar for the voice`() {
        val shell = codeOnly(read(APP_SHELL))

        // Narrowed from four symbols to one when the requirement was reversed — see the
        // header. `ReadAloudBar` is the reader's own in-reader chrome; composing it in the
        // shell is not "the shell knowing about read-aloud", which is now allowed, it is a
        // second persistent transport, which is not.
        assertTrue(
            "$APP_SHELL names ReadAloudBar in code. That is the reader's own in-reader" +
                " chrome, and composing it in the shell is a second persistent transport." +
                " `ebook-reader`'s *The transport on Android* asks for the compact bar the" +
                " app already draws \"rather than a second one grown for the voice, because" +
                " a listener has one transport to learn and not two\". Feed the existing" +
                " bar from a surface that spans both engines instead" +
                " (audiobooks-and-playback 6.1).",
            !shell.contains("ReadAloudBar"),
        )
    }

    @Test
    fun `the in-reader bar stays in the reader`() {
        // `ReadAloudBar` is in-reader chrome and is meant to stay there: on screen only while
        // the book is open, beside the return control. `ReaderChromeTest` keeps it off the
        // page's own two-control overlay; this keeps it from being promoted out of the module
        // altogether, which is the shape "adding a second bar" would actually take.
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
                " first step of promoting it into a second persistent transport, which" +
                " ebook-reader's *The transport outside the reader* forbids while requiring" +
                " the voice to take the app's existing compact bar.",
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
