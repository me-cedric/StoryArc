package app.storyarc.core.persistence

import app.storyarc.core.model.LibraryDocumentCoder
import app.storyarc.core.model.LibraryDocumentFailure
import app.storyarc.core.model.LibraryDocumentRefusal
import app.storyarc.core.model.LibraryExport
import app.storyarc.core.model.LibrarySecretSealer
import app.storyarc.core.model.LibrarySecrets
import app.storyarc.core.model.LibrarySnapshot
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import app.storyarc.core.model.SealedSecret
import app.storyarc.core.model.Shelves
import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import java.io.File
import java.util.UUID
import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/** A secure store in memory. */
internal class MemorySecrets : SourceSecretStore {
    val held = mutableMapOf<String, String>()

    override fun save(secret: String, reference: String): Boolean {
        held[reference] = secret
        return true
    }

    override fun secret(reference: String): String? = held[reference]

    override fun remove(reference: String): Boolean {
        held.remove(reference)
        return true
    }
}

/**
 * `library-portability` tasks 2.5, 3.1, 5.3 and 5.4 against real stores: the document leaves as
 * text, and comes back as a plan, and only a confirmed import changes the device. iOS's
 * `LibraryTransferTests` asserts the same rows.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class LibraryTransferTest {

    private val share = UUID.fromString("11111111-1111-1111-1111-111111111111")
    private val kavita = UUID.fromString("55555555-5555-5555-5555-555555555555")
    private val appVersion = "10.14.0"

    /** A progress store that refuses every save. */
    private class RefusingLedger(private val inner: ProgressStore) : ProgressLedger {
        class Refused : Exception()

        override suspend fun recent(limit: Int) = inner.recent(limit)

        override suspend fun save(progress: ReadingProgress) {
            throw Refused()
        }

        override suspend fun mark(identity: PublicationIdentity, isFinished: Boolean, at: Long) =
            inner.mark(identity, isFinished, at)

        override suspend fun forget(identity: PublicationIdentity) = inner.forget(identity)
    }

    /** One device: real stores in memory, and a secure store in a map. */
    private class Rig(ledger: (ProgressStore) -> ProgressLedger = { it }) {
        val secrets = MemorySecrets()
        val archive: LibraryArchive
        val transfer: LibraryTransfer

        init {
            val preferences = listOf("sources", "pins", "shelves", "library", "settings", "reader")
                .associateWith { FakePreferences() }
            archive = LibraryArchive(
                sources = SourceStore(preferences.getValue("sources")),
                certificatePins = CertificatePinStore(preferences.getValue("pins")),
                shelves = ShelvesStore(preferences.getValue("shelves")),
                library = LibraryPreferences(preferences.getValue("library")),
                settings = SettingsStore(preferences.getValue("settings")),
                reader = ReaderPreferences(preferences.getValue("reader")),
                progress = ledger(ProgressStore.inMemory(RuntimeEnvironment.getApplication())),
            )
            transfer = LibraryTransfer(archive, secrets)
        }
    }

    private class Vector(val passphrase: String, val plaintexts: Map<UUID, String>, val secrets: LibrarySecrets)

    /** The vector the two platforms and a third implementation all open. */
    private val vector: Vector by lazy {
        val root = JSONObject(
            File(
                System.getProperty("storyarc.repoRootDir"),
                "packages/test-fixtures/library/sealed-secrets.json",
            ).readText(),
        )
        val block = root.getJSONObject("secrets")
        val sealed = block.getJSONObject("sealed")
        val plain = root.getJSONObject("plaintexts")
        Vector(
            passphrase = root.getString("passphrase"),
            plaintexts = plain.keys().asSequence().associate { UUID.fromString(it) to plain.getString(it) },
            secrets = LibrarySecrets(
                kdf = block.getString("kdf"),
                iterations = block.getInt("iterations"),
                salt = block.getString("salt"),
                cipher = block.getString("cipher"),
                sealed = sealed.keys().asSequence().associateWith {
                    val entry = sealed.getJSONObject(it)
                    SealedSecret(entry.getString("nonce"), entry.getString("ciphertext"))
                },
            ),
        )
    }

    /** The library an export carries, sources only: a share and a server, each holding a secret. */
    private fun sourceLibrary(handle: (String) -> String) = LibrarySnapshot(
        sources = SourceRegistry(
            sources = listOf(
                Source(
                    id = share,
                    displayName = "Comics NAS",
                    kind = SourceKind.NETWORK_SHARE,
                    credentialReference = handle("share"),
                    locator = "smb://reader@nas.local/comics",
                ),
                Source(
                    id = kavita,
                    displayName = "Kavita",
                    kind = SourceKind.KAVITA_SERVER,
                    credentialReference = handle("kavita"),
                    locator = "https://kavita.example/api?library=3",
                ),
            ),
        ),
        certificatePins = mapOf("nas.local" to setOf("AB:CD")),
    )

    /** This device holding the library, with its two secrets in the secure store. */
    private suspend fun seeded(rig: Rig) {
        rig.secrets.save("nas-password", "share-handle")
        rig.secrets.save("kavita-key", "kavita-handle")
        rig.archive.apply(
            sourceLibrary { "$it-handle" }.copy(
                shelves = Shelves(collections = listOf(PublicationCollection(name = "Image Comics", members = setOf("path:/a.cbz")))),
            ),
        )
    }

    private fun documentText(library: LibrarySnapshot, sealed: Boolean = false): String =
        LibraryDocumentCoder.encode(
            LibraryExport.document(
                library,
                appVersion,
                1_767_225_845_000L,
                secrets = if (sealed) vector.secrets else null,
            ),
        )

    private fun incoming(sealed: Boolean = true) = documentText(sourceLibrary { "elsewhere" }, sealed)

    private fun reference(id: UUID) = CredentialStore.reference(id)

    // Export.

    @Test
    fun `an export with the switch off writes no secrets object though the store holds secrets`() = runTest {
        val rig = Rig()
        seeded(rig)

        val text = rig.transfer.exportText(appVersion)

        assertFalse(text.contains("\"secrets\": {"))
        assertFalse(text.contains("nas-password"))
        assertFalse(text.contains("kavita-key"))
        assertNull(LibraryDocumentCoder.decode(text).getOrThrow().secrets)
    }

    @Test
    fun `an export with the switch on seals each stored secret and writes none in clear`() = runTest {
        val rig = Rig()
        seeded(rig)

        val text = rig.transfer.exportText(appVersion, passphrase = "a long phrase")
        val block = requireNotNull(LibraryDocumentCoder.decode(text).getOrThrow().secrets)

        assertFalse(text.contains("nas-password"))
        assertFalse(text.contains("kavita-key"))
        assertFalse(text.contains("a long phrase"))
        assertEquals(
            mapOf(share to "nas-password", kavita to "kavita-key"),
            LibrarySecretSealer.open(block, "a long phrase"),
        )
    }

    @Test
    fun `the exported text decodes back to the library it was written from`() = runTest {
        val rig = Rig()
        seeded(rig)
        val snapshot = rig.archive.snapshot()

        val document = LibraryDocumentCoder.decode(rig.transfer.exportText(appVersion, atEpochMillis = 5_000L))
            .getOrThrow()

        assertEquals(LibraryExport.document(snapshot, appVersion, 5_000L).library, document.library)
    }

    // Preview.

    @Test
    fun `a preview states what will happen and changes nothing`() = runTest {
        val rig = Rig()
        val before = rig.archive.snapshot()

        val preview = rig.transfer.preview(incoming())

        assertEquals(listOf("Comics NAS", "Kavita"), preview.plan.sourcesToAdd)
        assertEquals(listOf("nas.local"), preview.plan.certificatePinsToAdd.map { it.host })
        assertTrue(preview.needsPassphrase)
        assertEquals(before, rig.archive.snapshot())
        assertTrue(rig.secrets.held.isEmpty())
    }

    @Test
    fun `a newer document is refused by name and the device is unchanged`() = runTest {
        val rig = Rig()
        val before = rig.archive.snapshot()
        val newer = incoming(sealed = false).replace("\"formatVersion\": 1", "\"formatVersion\": 7")

        val refused = runCatching { rig.transfer.preview(newer) }.exceptionOrNull()

        assertEquals(
            LibraryDocumentFailure.NewerThanThisApp(found = 7, understood = 1),
            (refused as? LibraryDocumentRefusal)?.reason,
        )
        assertEquals(before, rig.archive.snapshot())
        assertTrue(rig.secrets.held.isEmpty())
    }

    // Import.

    @Test
    fun `the right passphrase writes each secret to the store and signs the sources in`() = runTest {
        val rig = Rig()
        val preview = rig.transfer.preview(incoming())

        val outcome = rig.transfer.performImport(preview, vector.passphrase)

        assertEquals(2, outcome.secretsWritten)
        assertTrue(outcome.sourcesNeedingSignIn.isEmpty())
        assertEquals(
            mapOf(
                reference(share) to "nas-password-é世",
                reference(kavita) to "kavita-api-key-0123456789abcdef",
            ),
            rig.secrets.held,
        )
        val held = rig.archive.snapshot()
        assertTrue(held.sources.sources.all { it.credentialReference == reference(it.id) })
        assertEquals(mapOf("nas.local" to setOf("AB:CD")), held.certificatePins)
    }

    @Test
    fun `a wrong passphrase is refused before anything is written and may be tried again`() = runTest {
        val rig = Rig()
        val before = rig.archive.snapshot()
        val preview = rig.transfer.preview(incoming())

        val refused = runCatching { rig.transfer.performImport(preview, "not it") }.exceptionOrNull()

        assertEquals(
            LibraryImportException.Failure.PASSPHRASE_REFUSED,
            (refused as? LibraryImportException)?.failure,
        )
        assertEquals(before, rig.archive.snapshot())
        assertTrue(rig.secrets.held.isEmpty())
        assertEquals(2, rig.transfer.performImport(preview, vector.passphrase).secretsWritten)
    }

    @Test
    fun `skipping imports the rest and lists each source as needing a sign-in`() = runTest {
        val rig = Rig()
        val preview = rig.transfer.preview(incoming())

        val outcome = rig.transfer.performImport(preview, passphrase = null)

        assertEquals(0, outcome.secretsWritten)
        assertEquals(listOf("Comics NAS", "Kavita"), outcome.sourcesNeedingSignIn)
        assertTrue(rig.secrets.held.isEmpty())
        val held = rig.archive.snapshot().sources.sources
        assertEquals(listOf("Comics NAS", "Kavita"), held.map { it.displayName })
        assertTrue(held.all { it.credentialReference == null })
    }

    @Test
    fun `a write that fails after the secrets were stored takes the secrets back out`() = runTest {
        val rig = Rig(ledger = { RefusingLedger(it) })
        val before = rig.archive.snapshot()
        val library = sourceLibrary { "elsewhere" }.copy(
            progress = listOf(
                ReadingProgress(
                    identity = PublicationIdentity(contentDigest = "d1"),
                    position = ReadingPosition.Page(3, 20),
                    updatedAtEpochMillis = 1_767_100_000_000L,
                ),
            ),
        )
        val preview = rig.transfer.preview(documentText(library, sealed = true))

        val refused = runCatching { rig.transfer.performImport(preview, vector.passphrase) }.exceptionOrNull()

        assertNotNull(refused as? RefusingLedger.Refused)
        assertEquals(before, rig.archive.snapshot())
        assertTrue(rig.secrets.held.isEmpty())
    }

    @Test
    fun `a document sealed by another implementation opens here, the shared vector`() = runTest {
        val rig = Rig()
        val preview = rig.transfer.preview(incoming())

        rig.transfer.performImport(preview, vector.passphrase)

        assertEquals(vector.plaintexts.mapKeys { reference(it.key) }, rig.secrets.held)
    }

    @Test
    fun `with no secure store the rest is imported and every source asks for a sign-in`() = runTest {
        val rig = Rig()
        val transfer = LibraryTransfer(rig.archive, secrets = null)
        val preview = transfer.preview(incoming())

        val outcome = transfer.performImport(preview, vector.passphrase)

        assertEquals(0, outcome.secretsWritten)
        assertEquals(listOf("Comics NAS", "Kavita"), outcome.sourcesNeedingSignIn)
    }
}
