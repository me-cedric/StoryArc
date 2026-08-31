package app.storyarc

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A locked audiobook is refused by name, and nothing is asked of the reader.
 *
 * `publication-formats`:
 *
 * > **THEN** the app states that the file is protected by its store's content protection
 * > and that StoryArc cannot open it, naming that as the reason
 * > **AND** it does not prompt for a key, an account or an activation code, and does not
 * > suggest a way around the protection
 * > **AND** the refusal is distinct from an unsupported container
 *
 * **The last clause is a behaviour and is asserted as one** — `AudiobookIndexingTest` drives
 * the corpus's own `protected.aax` through the indexer and fails if it comes back as an
 * unsupported container. The first two clauses are about *words on a screen*, and this file
 * is the guard over them.
 *
 * A guard against something arriving, rather than a proof that nothing is there today. The
 * dialog that says this has one dismiss button and no field, so there is no prompt to
 * suppress and nothing here can measure a suppression. What was missing is anything that
 * fails on the day somebody adds a "enter your activation code" affordance in the belief
 * that it is helpful — and a requirement nothing can fail is a requirement nothing protects.
 *
 * iOS keeps the same guard in `ProtectedAudiobookPromptsForNothingTests.swift`.
 */
class ProtectedAudiobookPromptsForNothingTest {

    /** The two files that decide what a reader sees when a locked audiobook is opened. */
    private val refusalSources = listOf(
        "app/src/main/kotlin/app/storyarc/RefusedFileDialog.kt",
        "app/src/main/kotlin/app/storyarc/OpenedFile.kt",
    )

    @Test
    fun `the refusal is its own outcome, not an unsupported container with new words`() {
        // The structural half. A `ContentProtected` outcome cannot be confused with an
        // `Unsupported` one at a call site, which is what makes "distinct" hold no matter
        // what string anybody writes later.
        assertTrue(
            "OpenedFile has no ContentProtected outcome, so a locked file is indistinguishable" +
                " from a format StoryArc does not read",
            read(refusalSources[1]).contains("data class ContentProtected("),
        )
        // And the branch says its **own** words. Merely having a branch is not enough — a
        // `ContentProtected` case that reaches for `open_in_unsupported` is the defect the
        // requirement names, wearing a different type.
        val branch = withoutComments(read(refusalSources[0]))
            .substringAfter("OpenedFile.Outcome.ContentProtected", missingDelimiterValue = "")
            .substringBefore("is OpenedFile.Outcome.Opened")
        assertTrue(
            "RefusedFileDialog does not answer ContentProtected, so a locked file falls" +
                " through to another message",
            branch.isNotBlank(),
        )
        assertTrue(
            "the ContentProtected branch does not use open_in_protected, so a locked file" +
                " is described in some other refusal's words",
            branch.contains("R.string.open_in_protected"),
        )
    }

    @Test
    fun `nothing in the refusal path collects a key, an account or a code`() {
        // **Code, not prose.** The first version of this searched for the word
        // "activation" and failed on `OpenedFile`'s own doc comment explaining that it
        // never asks for one — a guard that forbids describing the rule it enforces is a
        // guard that gets the comment deleted rather than the defect fixed. So the
        // comments come off first, and what is left is searched for the things a prompt is
        // actually *built* out of. A field is an API call; a paragraph is not.
        val prompts = listOf(
            "TextField(",
            "BasicTextField",
            "PasswordVisualTransformation",
            "KeyboardType.Password",
            "rememberTextFieldState",
        )
        for (source in refusalSources) {
            val code = withoutComments(read(source))
            for (prompt in prompts) {
                assertTrue(
                    "$source constructs a $prompt. A protected audiobook is refused and" +
                        " nothing is asked of the reader — see publication-formats.",
                    !code.contains(prompt),
                )
            }
        }
    }

    @Test
    fun `the refused-file dialog offers one action and it dismisses`() {
        // A dialog with a second button is a dialog that offers a way forward, and there is
        // none to offer. `confirmButton` dismisses; a `dismissButton` slot would be the
        // second one.
        val dialog = withoutComments(read(refusalSources[0]))
        assertTrue("the dialog lost its dismiss action", dialog.contains("confirmButton"))
        assertTrue(
            "the dialog grew a second action, which for a locked file could only be a way" +
                " around the protection",
            !dialog.contains("dismissButton"),
        )
    }

    @Test
    fun `the message states the protection as the reason`() {
        // The default locale's copy, read from the resource rather than from a constant, so
        // rewording it in the file the reader actually sees is what this checks.
        val strings = read("app/src/main/res/values/strings.xml")
        val message = Regex("""<string name="open_in_protected">(.*?)</string>""", RegexOption.DOT_MATCHES_ALL)
            .find(strings)
            ?.groupValues
            ?.get(1)
            ?: error("open_in_protected is gone; the refusal has no words")

        assertTrue("the message does not name the protection", message.contains("content protection"))
        assertTrue("the message does not say StoryArc cannot open it", message.contains("cannot open"))
        // And it forecloses the expectation rather than leaving the reader waiting for a
        // field that is never coming.
        assertTrue(
            "the message does not say there is nothing to enter",
            message.contains("nothing to enter"),
        )
    }

    @Test
    fun `every language has the message`() {
        // A missing translation falls back to English, which is survivable — a *wrong* one
        // is not, and the way that happens is a locale being forgotten when a string lands.
        val locales = listOf("values", "values-de", "values-es", "values-fr")
        val present = locales.filter { locale ->
            read("app/src/main/res/$locale/strings.xml").contains("name=\"open_in_protected\"")
        }
        assertEquals(locales, present)
    }

    /**
     * A Kotlin source with its comments taken out.
     *
     * Crude on purpose — it does not know a `//` inside a string literal from a real
     * comment — and that is the right trade for a guard: a false *match* would be a
     * comment kept and a defect missed, and this errs the other way. Neither file here
     * holds a string literal at all.
     */
    private fun withoutComments(source: String): String = source
        .replace(Regex("""/\*.*?\*/""", RegexOption.DOT_MATCHES_ALL), "")
        .lines()
        .joinToString("\n") { it.substringBefore("//") }

    private fun read(path: String): String {
        val file = File(androidRoot, path)
        assertTrue("$path has moved; this test names it by path", file.isFile)
        return file.readText()
    }

    private companion object {
        /** `apps/android`, found rather than hardcoded. See `ShelvesAskOneRuleTest`. */
        val androidRoot: File = generateSequence(File("").absoluteFile) { it.parentFile }
            .firstOrNull { File(it, "settings.gradle.kts").isFile }
            ?: error("no settings.gradle.kts above ${File("").absolutePath}")
    }
}
