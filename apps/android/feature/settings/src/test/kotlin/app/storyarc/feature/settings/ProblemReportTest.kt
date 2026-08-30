package app.storyarc.feature.settings

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * What a problem report arrives pre-filled with.
 *
 * `settings-and-about`: the issue tracker opens "with the app version, platform version,
 * and device class pre-filled, and no personal data". Three facts, and Android carried two
 * of them -- the device class was settled in a comment here and stated only in the
 * diagnostic export, so a reader who tapped Report a problem sent a report that did not
 * say what they were holding.
 *
 * Mirrored case for case by `ProblemReportTests.swift`.
 */
class ProblemReportTest {

    @Test
    fun `a report carries the version, the platform and the device class, in that order`() {
        val body = BuildInfo.issueBody(platform = "Android 16 (API 36)", deviceClass = "tablet")
        val lines = body.trimEnd('\n').split("\n")
        assertEquals(3, lines.size)
        assertTrue("expected the app first, got ${lines[0]}", lines[0].startsWith("StoryArc "))
        assertEquals("Android 16 (API 36)", lines[1])
        assertEquals("tablet", lines[2])
    }

    @Test
    fun `a report carries nothing else`() {
        // No reader-typed text, no source name, no file path, no account. Everything in
        // the body arrives from the two arguments and the build's own version.
        val body = BuildInfo.issueBody(platform = "Android 16 (API 36)", deviceClass = "phone")
        assertTrue(body.endsWith("\n\n"))
        assertEquals(3, body.trimEnd('\n').split("\n").size)
    }
}
