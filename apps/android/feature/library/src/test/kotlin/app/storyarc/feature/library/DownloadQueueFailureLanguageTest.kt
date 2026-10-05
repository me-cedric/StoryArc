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
import app.storyarc.core.model.DownloadFailure
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
 *
 * Task 15.9 went further: the record keeps no sentence at all now, so the claim is that it
 * keeps the reason and that the reason reads in the reader's language when it is drawn.
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

        // The record keeps the reason and the screen says it -- `localization` 15.9. Storing
        // the sentence was the defect: it kept whichever language the app spoke that day, so a
        // reader who switched afterwards read the old one for ever.
        assertEquals(DownloadFailure.RefusedAddress.stored, reason)
        val french = DownloadFailureWords.sentence(context.speakingReaderLanguage(), reason!!)
        val english = DownloadFailureWords.sentence(context, reason)
        assertEquals(CatalogueMessages.describe(context.speakingReaderLanguage(), OpdsError.RefusedAddress), french)
        assertNotEquals(english, french)
    }
}
