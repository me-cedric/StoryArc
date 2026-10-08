package app.storyarc.feature.settings

import android.content.Context
import app.storyarc.core.model.LibraryDocumentCoder
import app.storyarc.core.model.LibraryExport
import app.storyarc.core.model.LibrarySecrets
import app.storyarc.core.model.LibrarySnapshot
import app.storyarc.core.model.PublicationCollection
import app.storyarc.core.model.SealedSecret
import app.storyarc.core.model.Shelves
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import app.storyarc.core.persistence.LibraryArchive
import app.storyarc.core.persistence.LibraryTransfer
import app.storyarc.core.persistence.SourceSecretStore
import java.io.File
import java.io.InputStream
import java.util.UUID
import org.json.JSONObject

/** A secure store in memory. */
internal class HeldSecrets : SourceSecretStore {
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

/** One device for the transfer screens' tests: real stores, and a secure store in memory. */
internal class TransferDevice(context: Context) {
    val secrets = HeldSecrets()
    val archive: LibraryArchive = LibraryArchive.open(context)
    val transfer = LibraryTransfer(archive, secrets)

    /** This device holding [library], with its two secrets in the secure store. */
    suspend fun holding(library: LibrarySnapshot = TransferLibrary.library): TransferDevice {
        secrets.save("nas-password", "share-handle")
        secrets.save("kavita-key", "kavita-handle")
        archive.apply(library)
        return this
    }
}

/** The libraries the tests move between devices. */
internal object TransferLibrary {
    val shareId: UUID = UUID.fromString("11111111-1111-1111-1111-111111111111")
    val kavitaId: UUID = UUID.fromString("55555555-5555-5555-5555-555555555555")

    /** A share and a server, each with a secret, a pinned certificate, and a collection. */
    val library = LibrarySnapshot(
        sources = SourceRegistry(
            sources = listOf(
                Source(
                    id = shareId,
                    displayName = "Comics NAS",
                    kind = SourceKind.NETWORK_SHARE,
                    credentialReference = "share-handle",
                    locator = "smb://reader@nas.local/comics",
                ),
                Source(
                    id = kavitaId,
                    displayName = "Kavita",
                    kind = SourceKind.KAVITA_SERVER,
                    credentialReference = "kavita-handle",
                    locator = "https://kavita.example/api?library=3",
                ),
            ),
        ),
        certificatePins = mapOf("nas.local" to setOf("AB:CD")),
        shelves = Shelves(
            collections = listOf(PublicationCollection(name = "Image Comics", members = setOf("path:/a.cbz", "path:/b.cbz"))),
        ),
    )

    /** The vector the two platforms and a third implementation all open. */
    class Vector(val passphrase: String, val secrets: LibrarySecrets)

    val vector: Vector by lazy {
        val repo = requireNotNull(File(requireNotNull(System.getProperty("storyarc.android.rootDir"))).parentFile?.parentFile)
        val root = JSONObject(File(repo, "packages/test-fixtures/library/sealed-secrets.json").readText())
        val block = root.getJSONObject("secrets")
        val sealed = block.getJSONObject("sealed")
        Vector(
            passphrase = root.getString("passphrase"),
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

    /** The text of a document a picker would hand over: the library, sealed by the vector or not. */
    fun documentText(
        library: LibrarySnapshot = this.library,
        sealed: Boolean = false,
        version: Int = 1,
    ): String = LibraryDocumentCoder.encode(
        LibraryExport.document(
            library,
            "10.14.0",
            1_767_225_845_000L,
            secrets = if (sealed) vector.secrets else null,
        ),
    ).replace("\"formatVersion\": 1", "\"formatVersion\": $version")
}

/** A picked file held in memory. [opened] counts how often anything tried to read it. */
internal class MemoryFile(
    private val text: String,
    private val reportedSize: Long? = text.toByteArray().size.toLong(),
    private val unopenable: Boolean = false,
) : PickedFile {
    var opened = 0
        private set

    override fun size(): Long? = reportedSize

    override fun open(): InputStream? {
        opened += 1
        return if (unopenable) null else text.byteInputStream()
    }
}
