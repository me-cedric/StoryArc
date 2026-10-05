package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.persistence.SettingsStore
import app.storyarc.core.persistence.speaking
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * That the four source sheets refuse in the language the reader chose.
 *
 * `localization` asks a chosen language to reach the whole interface. All four of these are
 * built with `host.activity.applicationContext` — `AppSheets` and `AppScreens` hand them the
 * application — and the per-app override is applied to an activity's own `attachBaseContext`,
 * so the `Application`'s resources keep the system configuration. A reader who set StoryArc to
 * French on a German device was told in German that an address could not be read.
 *
 * `lint` cannot see this. Every key below exists in `values`, `values-de`, `values-es` and
 * `values-fr`, so `MissingTranslation` is satisfied and the wrong catalogue is read anyway.
 *
 * Each case drives the sheet to the one refusal it can reach with no server: an address that
 * is not an address. [theBareApplicationStillReadsEnglish] is the control — without it these
 * assertions would also pass on a device whose own language is French.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SourceSheetsSpeakTheReadersLanguageTest {

    private val context: Application get() = ApplicationProvider.getApplicationContext()

    /** The reader's choice, which is what every case here is about. */
    private fun chooseFrench() {
        val store = SettingsStore.open(context)
        store.save(store.settings().copy(language = "fr"))
    }

    /** What the sentence should read, taken from the French catalogue rather than retyped. */
    private fun french(id: Int): String = context.speaking("fr").getString(id)

    @After
    fun forgetTheChoice() {
        val store = SettingsStore.open(context)
        store.save(store.settings().copy(language = null))
    }

    @Test
    fun theKavitaSheetRefusesAnAddressInTheReadersLanguage() {
        chooseFrench()
        val connection = KavitaConnection(context, credentials = null)

        connection.connect()

        assertEquals(
            french(R.string.kavita_error_not_an_address),
            (connection.step.value as KavitaConnection.Step.Failed).message,
        )
    }

    @Test
    fun theSharedFolderSheetRefusesAnAddressInTheReadersLanguage() {
        chooseFrench()
        val connection = SmbConnection(context, credentials = null)

        connection.connect()

        assertEquals(
            french(R.string.smb_error_not_an_address),
            (connection.step.value as SmbConnection.Step.Failed).message,
        )
    }

    @Test
    fun theCatalogueSheetRefusesAnAddressInTheReadersLanguage() {
        chooseFrench()
        val connection = CatalogueConnection(context, CertificatePins(), null, null)

        connection.connect()

        assertEquals(
            french(R.string.catalogue_error_not_a_url),
            (connection.step.value as CatalogueConnection.Step.Failed).message,
        )
    }

    /**
     * The browser's own refusal, which is the one that leaves the main thread.
     *
     * `ftp://` is a scheme `OpdsOrigin.isFetchable` refuses, so the page fails before a socket
     * is opened and this case needs no server. The main dispatcher is [Dispatchers.Unconfined]
     * so the fetch resumes on the thread that finished it instead of waiting for a looper.
     */
    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun theCataloguePageRefusesAnAddressInTheReadersLanguage() {
        chooseFrench()
        Dispatchers.setMain(Dispatchers.Unconfined)
        try {
            val browser = CatalogueBrowser(
                context,
                title = "Livres",
                root = "ftp://books.invalid/feed",
                credential = null,
                pins = CertificatePins(),
            )

            browser.load()

            val failed = runBlocking {
                withTimeout(FETCH_TIMEOUT_MILLIS) {
                    browser.state.first { it is CatalogueBrowser.State.Failed }
                }
            }
            assertEquals(
                french(R.string.catalogue_error_refused_address),
                (failed as CatalogueBrowser.State.Failed).message,
            )
        } finally {
            Dispatchers.resetMain()
        }
    }

    @Test
    fun theBareApplicationStillReadsEnglish() {
        val connection = KavitaConnection(context, credentials = null)

        connection.connect()

        val refusal = (connection.step.value as KavitaConnection.Step.Failed).message
        assertEquals(context.getString(R.string.kavita_error_not_an_address), refusal)
        assertNotEquals(french(R.string.kavita_error_not_an_address), refusal)
    }

    private companion object {
        /** Generous: the fetch is refused before any network, so this is only a deadlock guard. */
        const val FETCH_TIMEOUT_MILLIS = 10_000L
    }
}
