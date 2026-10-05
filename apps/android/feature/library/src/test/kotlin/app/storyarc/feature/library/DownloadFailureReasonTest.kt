package app.storyarc.feature.library

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.Download
import app.storyarc.core.model.DownloadFailure
import app.storyarc.core.model.DownloadLibrary
import app.storyarc.core.persistence.DownloadStore
import app.storyarc.core.persistence.speaking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A stored failure reason keeps no language -- `localization` 15.9.
 *
 * The queue used to compose `offline-downloads`' "plain-language reason" at the moment of
 * failure and write that sentence into the record. The record outlives the moment: a reader who
 * switched the app to French afterwards kept reading an English refusal on every failed row,
 * for ever. iOS asserts the same in `DownloadFailureReasonTests.swift`.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class DownloadFailureReasonTest {

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun download(reason: String) = Download(
        id = "hl09",
        title = "Harbour Lights 09",
        remote = "https://example.invalid/hl09.epub",
        mediaType = "application/epub+zip",
        state = Download.State.Failed(reason, 3),
    )

    @Test
    fun `a reason with an argument comes back exactly as it went in`() {
        val reasons = listOf(
            DownloadFailure.UnsupportedFormat("7-Zip"),
            DownloadFailure.NotAFeed("text/plain"),
            DownloadFailure.NotAFeed(null),
            DownloadFailure.Http(503),
            DownloadFailure.Unreadable,
            DownloadFailure.Unknown,
        )

        reasons.forEach { assertEquals(it, DownloadFailure.of(it.stored)) }
    }

    @Test
    fun `a sentence an older build stored is read as the generic reason`() {
        val store = DownloadStore.open(context).apply { reset() }
        // Exactly what a build before this change wrote: the English sentence of the day.
        store.save(DownloadLibrary(listOf(download("The server did not answer in time."))))

        val state = store.library()["hl09"]?.state as? Download.State.Failed

        assertEquals(DownloadFailure.Unknown.stored, state?.reason)
        // The count is the record's and is not what the migration is about.
        assertEquals(3, state?.attempts)
        val drawn = DownloadFailureWords.sentence(context, state!!.reason)
        assertEquals(DownloadFailureWords.sentence(context, DownloadFailure.Unknown), drawn)
        // And not the sentence that was stored, which is the whole defect: it is in the
        // language the app spoke that day and nothing could translate it.
        assertNotEquals("The server did not answer in time.", drawn)
        assertTrue(drawn.isNotEmpty())
    }

    @Test
    fun `a stored reason reads in the language the reader has chosen`() {
        val stored = DownloadFailure.RefusedAddress.stored

        assertNotEquals(
            DownloadFailureWords.sentence(context, stored),
            DownloadFailureWords.sentence(context.speaking("fr"), stored),
        )
    }
}
