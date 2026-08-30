package app.storyarc.feature.library

import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.persistence.CredentialStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * What removing a source takes with it.
 *
 * Rank 8 of the 30 August security review: "Remove source" was a no-op for every source that
 * was not a folder -- the folder lookup gated the whole method -- and no production code path
 * had ever called `CredentialStore.remove`. A reader who disconnected a Kavita server or an
 * SMB share kept a working credential on the device for a server they believed was gone.
 *
 * The decision rather than the view model, because [LibraryViewModel] is an
 * `AndroidViewModel` and a JVM unit test cannot build an `Application`. iOS's
 * `SourceRemovalDecisionTests` asserts these four cases in the same order, and its
 * `SourceRemovalTests` then asserts the same promise through the model itself.
 */
class SourceRemovalTest {

    private val folders = listOf("content://tree/Comics", "content://tree/Manga")

    @Test
    fun aServerSourceGivesUpItsSecretAndNamesNoFolder() {
        val source = Source(
            displayName = "Kavita",
            kind = SourceKind.KAVITA_SERVER,
            credentialReference = "3F2504E0",
            locator = "https://kavita.example",
        )

        val removal = SourceRemoval.of(source, folders)

        assertEquals("3F2504E0", removal.credentialReference)
        assertNull(removal.folder)
    }

    @Test
    fun aFolderSourceNamesItsFolder() {
        val source = Source(
            displayName = "Comics",
            kind = SourceKind.LOCAL_FOLDER,
            locator = "content://tree/Comics",
        )

        val removal = SourceRemoval.of(source, folders)

        assertEquals("content://tree/Comics", removal.folder)
        assertNull(removal.credentialReference)
    }

    @Test
    fun aSourceWithNoSecretStillRemovesCleanly() {
        // A folder never has one, and a removal that only worked for sources with a
        // credential would be the same bug with the guard moved.
        val source = Source(
            displayName = "Comics",
            kind = SourceKind.LOCAL_FOLDER,
            locator = "content://tree/Comics",
        )

        assertNull(SourceRemoval.of(source, folders).credentialReference)
    }

    @Test
    fun theSecretIsTheOneTheRegistryStoredNotOneDerivedFromTheId() {
        val source = Source(
            displayName = "NAS",
            kind = SourceKind.NETWORK_SHARE,
            credentialReference = "a-reference-nothing-else-would-guess",
            locator = "smb://nas.example/comics",
        )

        val removal = SourceRemoval.of(source, folders)

        assertEquals("a-reference-nothing-else-would-guess", removal.credentialReference)
        assertNotEquals(CredentialStore.reference(source.id), removal.credentialReference)
    }
}
