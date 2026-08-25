package app.storyarc.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The redaction rules, one test per thing that must not survive.
 *
 * `settings-and-about` asks for the redaction to be "a tested function, not a regex
 * written at the call site". A regex nobody tests is a regex that silently stops
 * matching, and the failure mode here is a reader publishing their own password. iOS's
 * `DiagnosticRedactionTests` asserts the same table.
 */
class DiagnosticRedactionTest {

    @Test
    fun `a password in a share URL does not survive and neither does the host`() {
        val redacted = DiagnosticRedaction.redact("smb://reader:hunter2@nas.local:445/comics")

        assertEquals("smb://[host]/comics", redacted)
        assertFalse(redacted.contains("hunter2"))
        assertFalse(redacted.contains("nas.local"))
    }

    @Test
    fun `the path survives because a path is what the diagnostic is for`() {
        assertEquals(
            "https://[host]/api/series/12",
            DiagnosticRedaction.redact("https://kavita.example.com/api/series/12"),
        )
    }

    @Test
    fun `a port is part of the authority and goes with it`() {
        assertEquals("http://[host]/opds", DiagnosticRedaction.redact("http://192.168.1.4:8080/opds"))
    }

    @Test
    fun `a bare address needs no scheme to identify a server`() {
        assertEquals("could not reach [host]", DiagnosticRedaction.redact("could not reach 192.168.1.40"))
    }

    @Test
    fun `a file URL has no host to remove and keeps its path`() {
        // The empty authority is the point: a greedy authority rule would eat the
        // path, and the path is the whole content of a file URL.
        assertEquals(
            "file://[host]/storage/emulated/0/Comics",
            DiagnosticRedaction.redact("file:///storage/emulated/0/Comics"),
        )
    }

    @Test
    fun `a value introduced by a word meaning secret is removed`() {
        val keyed = listOf(
            "token=abc123",
            "password: hunter2",
            "apiKey=xyz",
            "Authorization: Basic dXNlcg",
            "secret = s3cr3t",
            "bearer eyJhbGci",
        )
        for (line in keyed) {
            assertTrue(line, DiagnosticRedaction.redact(line).contains(DiagnosticRedaction.CREDENTIAL))
        }
    }

    @Test
    fun `knowing a token was present is useful so the key survives the value`() {
        assertEquals("token=[redacted]", DiagnosticRedaction.redact("token=abc123"))
    }

    @Test
    fun `a word that merely contains a secret word is not a secret`() {
        // "keyboard" contains "key". Redacting the sentence after it would remove the
        // diagnostic while claiming to protect it.
        assertEquals(
            "keyboard shortcuts enabled",
            DiagnosticRedaction.redact("keyboard shortcuts enabled"),
        )
    }

    @Test
    fun `a long opaque run is treated as a token even with nothing naming it`() {
        val key = "a1B2".repeat(10)
        assertEquals("stored [token]", DiagnosticRedaction.redact("stored $key"))
    }

    @Test
    fun `a version string is not long enough to look like a token`() {
        // The whole point of the 32-character floor: above every word and version
        // number, below every key format.
        assertEquals(
            "StoryArc 1.4.2 (build 318)",
            DiagnosticRedaction.redact("StoryArc 1.4.2 (build 318)"),
        )
    }

    @Test
    fun `the home directory carries the reader's name and is replaced by a tilde`() {
        val redacted = DiagnosticRedaction.redact("/home/someone/Comics/Nausicaa.cbz")

        assertEquals("~/Comics/Nausicaa.cbz", redacted)
        assertFalse(redacted.contains("someone"))
    }

    @Test
    fun `a macOS home is the same rule`() {
        assertEquals("~/books", DiagnosticRedaction.redact("/Users/someone/books"))
    }

    @Test
    fun `rules compose rather than undoing each other`() {
        val report = """
            source: smb://reader:hunter2@nas.local/comics
            folder: /home/someone/Comics
            token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
        """.trimIndent()
        val redacted = DiagnosticRedaction.redact(report)

        for (leaked in listOf("hunter2", "nas.local", "someone", "aaaaaaaaaaaa")) {
            assertFalse("leaked $leaked", redacted.contains(leaked))
        }
        assertTrue(redacted.contains("smb://[host]/comics"))
        assertTrue(redacted.contains("~/Comics"))
    }

    @Test
    fun `redaction is idempotent so a marker is never redacted again`() {
        // The export can be regenerated, and a marker that itself matched a rule would
        // degrade into nested markers on each pass.
        val once = DiagnosticRedaction.redact("smb://reader:hunter2@nas.local/x /Users/a/b token=abc")

        assertEquals(once, DiagnosticRedaction.redact(once))
    }

    @Test
    fun `text with nothing to hide is returned unchanged`() {
        val plain = "Android 16, Pixel 9, 42 publications, 3.2 MB cache"
        assertEquals(plain, DiagnosticRedaction.redact(plain))
    }
}
