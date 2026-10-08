package app.storyarc.feature.library

import android.app.Application
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.test.core.app.ApplicationProvider
import app.storyarc.core.catalogue.CertificatePins
import app.storyarc.core.designsystem.theme.StoryArcTheme
import app.storyarc.core.model.LibraryExport
import app.storyarc.core.model.LibraryImport
import app.storyarc.core.model.LibrarySnapshot
import app.storyarc.core.model.MetadataOrigin
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceAction
import app.storyarc.core.model.SourceConnectionState
import app.storyarc.core.model.SourceDiagnosis
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import app.storyarc.core.persistence.SourceStore
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * `library-portability` task 3.4: an imported source asks for its secret when it is reached.
 *
 * The import half is asserted in `LibraryImportTest`: the source arrives with no secret and is
 * named in `sourcesNeedingSignIn`. This is the other half. A source that came through an import
 * is asked by the same probe as any other, lands in the unauthorised state with no request made
 * (it holds nothing to send), offers the one action that asks for the secret, and shows the
 * explanation instead of a browser that would fail. Everything else in the library stays where it
 * was. iOS's `ImportedSourceSignInTests` asserts the same rows.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [34], qualifiers = "w360dp-h800dp")
class ImportedSourceSignInTest {

    @get:Rule
    val compose = createComposeRule()

    private val application: Application get() = ApplicationProvider.getApplicationContext()

    private val kavitaId: UUID = UUID.fromString("55555555-5555-5555-5555-555555555555")

    /** A document that carries one Kavita server the writing device was signed in to. */
    private val document = LibraryExport.document(
        LibrarySnapshot(
            sources = SourceRegistry(
                sources = listOf(
                    Source(
                        id = kavitaId,
                        displayName = "Kavita",
                        kind = SourceKind.KAVITA_SERVER,
                        credentialReference = "elsewhere",
                        locator = "https://kavita.invalid/api?library=3",
                    ),
                ),
            ),
        ),
        "10.14.0",
        1_767_225_845_000L,
    )

    private val publication = Publication(
        identity = PublicationIdentity(normalizedPath = "/Books/Shelf/a.cbz"),
        format = PublicationFormat.CBZ,
        displayTitle = "Already here",
        origin = MetadataOrigin.INFERRED,
    )

    /** A device holding a folder with one publication, and then the import of the document. */
    private fun importedLibrary(): LibraryViewModel {
        val folder = Source(
            displayName = "Shelf",
            kind = SourceKind.LOCAL_FOLDER,
            state = SourceConnectionState.Connected,
            locator = "/Books/Shelf",
        )
        val device = LibrarySnapshot(sources = SourceRegistry(sources = listOf(folder)))
        val store = SourceStore.open(application)
        store.save(LibraryImport.merging(document, device).snapshot.sources)
        return LibraryViewModel(application, sourceStore = store).also {
            it._publications.value = listOf(publication)
        }
    }

    private fun LibraryViewModel.imported(): Source = registry.value.sources.first { it.id == kavitaId }

    @Test
    fun `the imported source holds no secret so the probe lands it in the unauthorised state`() = runBlocking {
        val library = importedLibrary()
        assertNull(library.imported().credentialReference)

        library.probeAndWait(credentials = null, pins = CertificatePins())

        assertTrue(library.imported().state is SourceConnectionState.Unauthorized)
    }

    @Test
    fun `it offers the action that asks for the secret, first`() = runBlocking {
        val library = importedLibrary()
        library.probeAndWait(credentials = null, pins = CertificatePins())

        val diagnosis = SourceDiagnosis.of(library.imported(), itemCount = 0, downloads = emptyList())

        assertEquals(SourceAction.RECONNECT, diagnosis.actions.first())
    }

    @Test
    fun `the library it joined stays browsable`() = runBlocking {
        val library = importedLibrary()

        library.probeAndWait(credentials = null, pins = CertificatePins())

        assertEquals(listOf(publication), library.publications.value)
    }

    @Test
    fun `opening it says nobody stored a sign-in, and a refused secret says it was refused`() = runBlocking {
        val library = importedLibrary()
        library.probeAndWait(credentials = null, pins = CertificatePins())
        val arrived = library.imported()
        val held = arrived.copy(credentialReference = "held")

        assertFalse(arrived.signInWasRefused())
        assertTrue(held.signInWasRefused())

        compose.setContent {
            StoryArcTheme {
                UnauthorizedSourceScreen(name = "Kavita", isRefused = arrived.signInWasRefused(), onBack = {})
            }
        }
        compose.waitForIdle()
        val body = application.getString(R.string.source_unauthorized_body, "Kavita")
        assertTrue(compose.onAllNodesWithText(body).fetchSemanticsNodes().isNotEmpty())
        val refusedBody = application.getString(R.string.source_unauthorized_refused_body, "Kavita")
        assertTrue(compose.onAllNodesWithText(refusedBody).fetchSemanticsNodes().isEmpty())
    }
}
