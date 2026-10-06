package app.storyarc.feature.settings

import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.CoverLookupProvider
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Task 3.1: the setting is off until a reader turns it on, and it names its providers.
 *
 * iOS's `CoverLookupSettingsTests` makes the same four claims.
 */
class CoverLookupRowTest {

    private companion object {
        /** Lenient about fields it does not know, the way `SettingsStore` reads one. */
        val json = Json { ignoreUnknownKeys = true }
    }

    @Test
    fun `a reader who has never opened the setting has the lookup off`() {
        // `cover-art`: "a reader has never opened the cover-lookup setting ... no cover
        // request is made to any third party". The default is the requirement.
        assertFalse(AppSettings.Defaults.lookUpMissingCovers)
    }

    @Test
    fun `an older stored file reads as off rather than as consent`() {
        // A build that adds a setting must read what an earlier build wrote, and the field
        // is absent from every file written before this change. Absent must never mean yes.
        val older = """{"appearance":"SYSTEM","downloadOverWifiOnly":true}"""
        val settings = json.decodeFromString<AppSettings>(older)

        assertFalse(settings.lookUpMissingCovers)
    }

    @Test
    fun `the row names every provider the lookup can reach`() {
        // A fourth provider added without a word on this screen would be a request the
        // reader never agreed to, so the row is built from the enum rather than from a list
        // beside it.
        val shown = coverLookupProviderNames()
        for (provider in CoverLookupProvider.entries) {
            assertTrue(shown.contains(provider.displayName))
        }
    }

    @Test
    fun `the setting lives on the Privacy screen, because it decides what leaves`() {
        assertEquals(SettingsGroup.PRIVACY, SettingsAnchor.COVER_LOOKUP.group)
    }
}
