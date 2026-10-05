package app.storyarc.feature.library

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import app.storyarc.core.persistence.ImportedCopies
import app.storyarc.core.persistence.SettingsStore
import app.storyarc.core.persistence.speaking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * That "On this device" is named in the language the reader chose, and stays named in it.
 *
 * `localization` asks a chosen language to reach the whole interface. This is the only name in
 * the source registry StoryArc writes itself — every other one is the reader's or a server's —
 * and it was resolved on the `Application`, whose resources keep the system configuration
 * because the per-app override is applied to an activity's own `attachBaseContext`.
 *
 * It is also written to disk by `SourceStore`, so getting it right once is not enough: a name
 * resolved at the moment the first copy landed would keep that language for ever.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ImportedSourceNameTest {

    private val context: Application get() = ApplicationProvider.getApplicationContext()

    private fun chooseFrench() {
        val store = SettingsStore.open(context)
        store.save(store.settings().copy(language = "fr"))
    }

    /** What the row should read, taken from the French catalogue rather than retyped. */
    private val inFrench: String
        get() = context.speaking("fr").getString(R.string.source_on_this_device)

    @After
    fun forgetTheChoice() {
        val store = SettingsStore.open(context)
        store.save(store.settings().copy(language = null))
    }

    @Test
    fun theRowIsNamedInTheReadersLanguage() {
        chooseFrench()

        assertEquals(inFrench, LibraryViewModel(context).importedSourceName())
    }

    @Test
    fun withNoChoiceMadeItReadsTheSystemsLanguage() {
        val named = LibraryViewModel(context).importedSourceName()

        assertEquals(context.getString(R.string.source_on_this_device), named)
        assertNotEquals(inFrench, named)
    }

    @Test
    fun aRowWrittenInTheOldLanguageIsBroughtForward() {
        val model = LibraryViewModel(context)
        model._registry.value = SourceRegistry().adding(
            Source(
                id = ImportedCopies.SOURCE_ID,
                displayName = context.getString(R.string.source_on_this_device),
                kind = SourceKind.LOCAL_FOLDER,
            ),
        )
        chooseFrench()

        assertTrue(
            "The row is already in the registry, so nothing should add a second one.",
            model.keptImportedSourceNamed(model.importedSourceName()),
        )
        assertEquals(inFrench, model._registry.value[ImportedCopies.SOURCE_ID]?.displayName)
    }

    @Test
    fun withNoRowThereIsNothingToKeep() {
        val model = LibraryViewModel(context)

        assertEquals(false, model.keptImportedSourceNamed(inFrench))
    }
}
