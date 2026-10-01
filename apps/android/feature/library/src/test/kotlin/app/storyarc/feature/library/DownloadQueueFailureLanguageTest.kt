package app.storyarc.feature.library

import android.content.Context
import android.os.Looper.getMainLooper
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.catalogue.OpdsAcquisition
import app.storyarc.core.catalogue.OpdsEntry
import app.storyarc.core.catalogue.OpdsError
import app.storyarc.core.catalogue.OpdsOrigin
import app.storyarc.core.model.AppSettings
import app.storyarc.core.model.Download
import app.storyarc.core.persistence.DownloadStore
import app.storyarc.core.persistence.SettingsStore
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Task 15.5: a download's own failure reason read `context.getString(...)` on the bare
 * application context, which stays in the system's language outside any activity --
 * `DownloadQueueScreenWritesTest`'s "stepped down from https" case is the one place this
 * suite can trigger a real failure with no network fake, so it is the one reused here.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class DownloadQueueFailureLanguageTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun store(): DownloadStore = DownloadStore.open(context).apply { reset() }

    @Test
    fun `a refused-address failure is written in the reader's chosen language`() {
        val settingsStore = SettingsStore.open(context)
        settingsStore.save(settingsStore.settings().copy(language = "fr"))

        val source = UUID.randomUUID()
        val queue = DownloadQueue(
            context,
            CertificatePins(),
            store(),
            sourceOrigin = { id -> OpdsOrigin.of("https://library.invalid").takeIf { id == source } },
            settings = { AppSettings() },
            onWifi = MutableStateFlow(true),
        )
        val entry = OpdsEntry(id = "entry-1", title = "Cleartext")
        val cleartext = OpdsAcquisition(
            href = "http://library.invalid/entry-1.epub",
            mediaType = "application/epub+zip",
            kind = OpdsAcquisition.Kind.OPEN,
        )

        queue.enqueue(entry, cleartext, sourceId = source)
        shadowOf(getMainLooper()).idle()

        val reason = (queue.library.value[queue.downloadId(entry.id, source)]?.state as? Download.State.Failed)?.reason
        val french = CatalogueMessages.describe(context.speakingReaderLanguage(), OpdsError.RefusedAddress)
        val english = CatalogueMessages.describe(context, OpdsError.RefusedAddress)

        assertEquals(french, reason)
        assertNotEquals(english, reason)
    }
}
