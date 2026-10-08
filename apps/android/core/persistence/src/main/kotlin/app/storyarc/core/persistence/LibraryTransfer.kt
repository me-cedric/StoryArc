package app.storyarc.core.persistence

import app.storyarc.core.model.LibraryDocument
import app.storyarc.core.model.LibraryDocumentCoder
import app.storyarc.core.model.LibraryExport
import app.storyarc.core.model.LibraryImport
import app.storyarc.core.model.LibraryImportPlan
import app.storyarc.core.model.LibrarySecretSealer
import app.storyarc.core.model.LibrarySecretsException
import app.storyarc.core.model.LibrarySnapshot
import app.storyarc.core.model.ProgressPull
import app.storyarc.core.model.fillableSources
import app.storyarc.core.model.merging
import app.storyarc.core.model.needsPassphrase
import app.storyarc.core.model.sealedSecrets
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Where a source's secret is kept: the Keystore-backed store in the app, a map in a test. */
interface SourceSecretStore {
    fun save(secret: String, reference: String): Boolean

    fun secret(reference: String): String?

    fun remove(reference: String): Boolean
}

/** A document read and planned, with nothing changed yet. */
data class LibraryImportPreview(
    val document: LibraryDocument,
    val plan: LibraryImportPlan,
    /**
     * Whether the document carries secrets this device would use, so the reader is asked for
     * the passphrase before they confirm.
     */
    val needsPassphrase: Boolean,
)

/** What an import did, for the screen that tells the reader and the app that reloads. */
data class LibraryImportOutcome(
    /** Positions where both sides had moved. The further one was kept. */
    val conflicts: List<ProgressPull.Conflict>,
    /** Sources, by name, that still ask for a sign-in. */
    val sourcesNeedingSignIn: List<String>,
    /** How many secrets went to the secure store. */
    val secretsWritten: Int,
    /** The library as the import left it. The app reloads its in-memory copies from this. */
    val snapshot: LibrarySnapshot,
)

/** Why an import stopped before it changed anything. */
class LibraryImportException(val failure: Failure) : Exception(failure.name) {
    enum class Failure {
        /** The passphrase did not open the secrets. The reader may try again, or skip them. */
        PASSPHRASE_REFUSED,
    }
}

/**
 * Export and import of the library, from the text to the stores.
 *
 * `library-portability`. The pure rules are in `:core:model`; this reads the stores through
 * [LibraryArchive], reads and writes secrets through a [SourceSecretStore], and keeps the one
 * promise neither of them can: a failed import leaves the device as it was, secrets included.
 * iOS's `LibraryTransfer` is the same three operations.
 *
 * @param secrets null where the platform keystore refused to open: nothing is sealed, and an
 *   import writes no secret, so each source asks for a sign-in.
 */
class LibraryTransfer(
    private val archive: LibraryArchive,
    private val secrets: SourceSecretStore?,
) {

    /**
     * The document, as the text a reader will put wherever they choose.
     *
     * @param passphrase null writes no secret. A value seals every stored secret under it; the
     *   caller has already checked the pair with `ExportPassphrase.problem`. The passphrase is
     *   used for the one derivation and kept nowhere.
     */
    suspend fun exportText(
        appVersion: String,
        passphrase: String? = null,
        atEpochMillis: Long = System.currentTimeMillis(),
    ): String {
        val snapshot = archive.snapshot()
        return withContext(Dispatchers.Default) {
            val sealed = passphrase?.let {
                LibraryExport.sealedSecrets(snapshot, it) { source ->
                    source.credentialReference?.let { handle -> secrets?.secret(handle) }
                }
            }
            LibraryDocumentCoder.encode(
                LibraryExport.document(snapshot, appVersion, atEpochMillis, sealed),
            )
        }
    }

    /**
     * Reads a document and states what importing it would do. Changes nothing.
     *
     * @throws app.storyarc.core.model.LibraryDocumentRefusal when the document is refused, by
     *   name.
     */
    suspend fun preview(text: String): LibraryImportPreview {
        val document = LibraryDocumentCoder.decode(text).getOrThrow()
        val device = archive.snapshot()
        return LibraryImportPreview(
            document = document,
            plan = LibraryImport.plan(document, device),
            needsPassphrase = LibraryImport.needsPassphrase(document, device),
        )
    }

    /**
     * Merges the document into the library.
     *
     * Opens the secrets first, so a wrong passphrase stops here with nothing written. Then the
     * secrets go to the secure store, then the merged library to its stores. A failure in the
     * second undoes the first: the device is as it was, and the failure is thrown again.
     *
     * @param passphrase null, or empty, imports everything but the secrets; those sources are
     *   listed as needing a sign-in.
     * @throws LibraryImportException when the passphrase is refused.
     */
    suspend fun performImport(preview: LibraryImportPreview, passphrase: String?): LibraryImportOutcome {
        val document = preview.document
        val opened = openedSecrets(document, passphrase)
        val device = archive.snapshot()

        val usable = LibraryImport.fillableSources(document, device)
        val stored = mutableMapOf<UUID, String>()
        for ((id, secret) in opened) {
            if (id in usable && secrets?.save(secret, CredentialStore.reference(id)) == true) {
                stored[id] = secret
            }
        }

        val result = LibraryImport.merging(document, device, stored) { CredentialStore.reference(it) }
        // A secret the merge found no source for is not left behind in the secure store.
        for (id in stored.keys - result.credentialed) secrets?.remove(CredentialStore.reference(id))
        try {
            archive.apply(result.snapshot)
        } catch (failure: Exception) {
            for (id in stored.keys) secrets?.remove(CredentialStore.reference(id))
            throw failure
        }
        return LibraryImportOutcome(
            conflicts = result.conflicts,
            sourcesNeedingSignIn = result.sourcesNeedingSignIn,
            secretsWritten = result.credentialed.size,
            snapshot = result.snapshot,
        )
    }

    private suspend fun openedSecrets(document: LibraryDocument, passphrase: String?): Map<UUID, String> {
        val sealed = document.secrets
        if (sealed == null || passphrase.isNullOrEmpty()) return emptyMap()
        return withContext(Dispatchers.Default) {
            try {
                LibrarySecretSealer.open(sealed, passphrase)
            } catch (_: LibrarySecretsException) {
                throw LibraryImportException(LibraryImportException.Failure.PASSPHRASE_REFUSED)
            }
        }
    }
}
