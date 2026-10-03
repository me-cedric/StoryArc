package app.storyarc.feature.library

import app.storyarc.core.model.PublicationFormat
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Task 16.7 / D38: a publication page names the device's own read-aloud voice, or says that
 * none reads the book's language. Pure, exactly because [ReadAloudVoiceLookup] — the one call
 * to `TextToSpeech` this feature makes — is not: what voices and engines a test runner
 * happens to have installed is not this suite's to depend on, so every fact arrives already
 * resolved. A fixed `languageName` lambda stands in for [languageName] itself, so this suite
 * is not also a test of `Locale`.
 */
class ReadAloudVoiceLineTest {

    private val name: (String) -> String = { "<$it>" }

    @Test
    fun `a narrated or image format names no voice, whatever the language`() {
        for (format in PublicationFormat.entries) {
            if (format == PublicationFormat.EPUB) continue
            assertNull(
                "$format should name no voice",
                ReadAloudVoiceLine.fact(format, "en", ReadAloudEngine("Google", true), name),
            )
        }
    }

    @Test
    fun `an EPUB with no stated language names no voice either`() {
        assertNull(ReadAloudVoiceLine.fact(PublicationFormat.EPUB, null, null, name))
        assertNull(ReadAloudVoiceLine.fact(PublicationFormat.EPUB, "", null, name))
    }

    @Test
    fun `an EPUB the device can speak names the engine and the language`() {
        val fact = ReadAloudVoiceLine.fact(
            PublicationFormat.EPUB,
            "fr",
            ReadAloudEngine(label = "Google", speaksTheLanguage = true),
            name,
        )
        assertEquals(ReadAloudVoiceFact.Named(engineLabel = "Google", languageName = "<fr>"), fact)
    }

    @Test
    fun `an EPUB with no installed voice names the language instead`() {
        val fact = ReadAloudVoiceLine.fact(
            PublicationFormat.EPUB,
            "de",
            ReadAloudEngine(label = "Google", speaksTheLanguage = false),
            name,
        )
        assertEquals(ReadAloudVoiceFact.Missing(languageName = "<de>"), fact)
    }

    @Test
    fun `no engine at all is the same as no voice for the language`() {
        val fact = ReadAloudVoiceLine.fact(PublicationFormat.EPUB, "es", null, name)
        assertEquals(ReadAloudVoiceFact.Missing(languageName = "<es>"), fact)
    }
}
