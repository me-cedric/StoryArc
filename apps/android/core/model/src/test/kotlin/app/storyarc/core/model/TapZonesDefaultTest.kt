package app.storyarc.core.model

import kotlinx.serialization.json.Json
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * That a reader who has never opened Settings has the tap zones.
 *
 * `page-transitions`: turning the page by tapping the edges is "on by default", and it can
 * be turned off. A default nobody asserts is a default one refactor away from being the
 * other one, and this particular default has two ways of being lost — the field's own
 * initialiser, and the decoder that reads a settings file written before the field
 * existed. `SettingsStore` decodes JSON and falls back to [AppSettings.Defaults], so both
 * paths end here.
 *
 * iOS's `SettingsStoreTests` asserts the same two facts against `UserDefaults`.
 */
class TapZonesDefaultTest {

    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `never touched means the zones are on`() {
        assertTrue(AppSettings.Defaults.turnPagesByTappingTheEdges)
    }

    @Test
    fun `settings written before the field existed keep the zones on`() {
        val before = """{"appearance":"DARK","turnPagesWithVolumeButtons":true}"""

        val settings = json.decodeFromString<AppSettings>(before)

        assertTrue(
            "A settings file from a build without this field turned the zones off.",
            settings.turnPagesByTappingTheEdges,
        )
    }

    @Test
    fun `off stays off, so the default is a default and not a floor`() {
        val stored = json.encodeToString(AppSettings(turnPagesByTappingTheEdges = false))

        assertTrue(
            "The setting was not written, so nothing could have read it back.",
            stored.contains("turnPagesByTappingTheEdges"),
        )
        assertTrue(
            "A reader who turned the zones off got them back on.",
            !json.decodeFromString<AppSettings>(stored).turnPagesByTappingTheEdges,
        )
    }
}
