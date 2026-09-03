package app.storyarc.feature.settings

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * The diagnostic export's source section is a count, and never a list.
 *
 * `sources` forbids a secret reaching "preferences, logs, crash reports, backups, or exported
 * diagnostics", and the export is the one thing here a reader hands to a stranger. Three of a
 * source's fields are exactly what must not travel: the display name, because a reader names a
 * server after the machine and so it *is* the hostname; the locator, because it is a URL and a
 * URL is where an embedded credential survives; and the credential reference, because it is a
 * handle into the platform secure store.
 *
 * The registry below is built to be caught. Every one of its strings is distinctive, so an
 * assertion that the report does not contain them fails the moment anything derived from a
 * source is appended to the section.
 *
 * Robolectric because [Diagnostic.text] reads five stores and the device's own configuration.
 * It is still a host test -- `:feature:settings:testDebugUnitTest`, no device.
 *
 * iOS's `DiagnosticSourcesTests` asserts the same cases, case for case.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class DiagnosticSourcesTest {

    private val hostname = "comics.attic.example.net"
    private val locator = "https://reader:s3cr3t@comics.attic.example.net/opds/v1.2/root.xml"
    private val credentialReference = "app.storyarc.credential.kavita-9f3ab1"

    private val registry = SourceRegistry()
        .adding(
            Source(
                displayName = hostname,
                kind = SourceKind.OPDS_CATALOG,
                credentialReference = credentialReference,
                locator = locator,
            ),
        )
        .adding(Source(displayName = "Attic NAS", kind = SourceKind.NETWORK_SHARE, locator = "smb://10.0.0.4/comics"))
        .adding(Source(displayName = "Downloads", kind = SourceKind.LOCAL_FOLDER, locator = "Downloads"))

    // region The section itself

    @Test
    fun `the source section is a heading and a count, and nothing else`() {
        // Two lines, whatever the registry holds. A list would grow with it, which is the
        // shape this assertion exists to refuse.
        assertEquals(listOf("[Sources]", "configured = 3"), Diagnostic.sourceLines(registry))
    }

    @Test
    fun `the section does not grow when the registry does`() {
        val one = Diagnostic.sourceLines(
            SourceRegistry().adding(
                Source(displayName = hostname, kind = SourceKind.KAVITA_SERVER, locator = locator),
            ),
        )
        val many = Diagnostic.sourceLines(registry)

        assertEquals(one.size, many.size)
        assertEquals(2, one.size)
    }

    @Test
    fun `the count is the real one, not a literal`() {
        // It was `configured = 0` on both platforms, which is a count in shape and a
        // falsehood in fact: a reader with four servers filed a report saying they had none.
        assertEquals(
            listOf("[Sources]", "configured = 0"),
            Diagnostic.sourceLines(SourceRegistry()),
        )
        assertEquals("configured = 3", Diagnostic.sourceLines(registry).last())
    }

    // endregion

    // region What must not travel

    @Test
    fun `no source name reaches the section`() {
        val section = Diagnostic.sourceLines(registry).joinToString("\n")

        assertFalse(section.contains(hostname))
        assertFalse(section.contains("Attic NAS"))
    }

    @Test
    fun `no locator and no credential reference reaches the section`() {
        val section = Diagnostic.sourceLines(registry).joinToString("\n")

        assertFalse(section.contains(locator))
        assertFalse(section.contains(credentialReference))
        assertFalse(section.contains("smb://10.0.0.4/comics"))
    }

    // endregion

    // region The whole report, not just the section

    @Test
    fun `no source value reaches the report at all`() {
        // The section is where a leak would come from, and the report is where it would
        // matter, so the assertion is made against the text the reader actually shares.
        val report = report()

        listOf(hostname, locator, credentialReference, "Attic NAS", "s3cr3t").forEach { secret ->
            assertFalse("$secret reached the report", report.contains(secret))
        }
    }

    @Test
    fun `the report still says how many sources there are`() {
        // The refusals above are worth nothing if the section can satisfy them by being
        // absent: a maintainer reading the report has to be able to tell a reader with no
        // sources from a reader with three.
        val report = report()

        assertTrue(report.contains("[Sources]"))
        assertTrue(report.contains("configured = 3"))
    }

    private fun report(): String =
        Diagnostic.text(ApplicationProvider.getApplicationContext<Context>(), registry)

    // endregion
}
