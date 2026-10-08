package app.storyarc.core.smb

import app.storyarc.core.model.SyncFile
import app.storyarc.core.model.SyncPlace

/**
 * The sync document's place on a share the reader already added.
 *
 * `library-sync` task 2.2. The files live in the folder the source opens at
 * ([SmbAddress.path]), with the source's own credential. One connection serves the whole sync,
 * and [close] ends it. Each call throws [SmbError] as the share's other calls do, so an
 * unreachable share is grey, not red. iOS's `SmbSyncPlace` is the same place.
 */
class SmbSyncPlace(private val address: SmbAddress) : SyncPlace, AutoCloseable {

    private val client = SmbClient(address)

    override suspend fun names(): List<String> =
        client.list(address.path).filterNot { it.isDirectory }.map { it.name }

    override suspend fun read(name: String): SyncFile? =
        client.readFile(pathOf(name))?.let { SyncFile(it.bytes.decodeToString(), it.version) }

    override suspend fun write(name: String, text: String, replacing: String?): Boolean =
        client.writeFile(pathOf(name), text.encodeToByteArray(), replacing)

    override suspend fun delete(name: String): Boolean = client.deleteFile(pathOf(name))

    override fun close() = client.close()

    private fun pathOf(name: String): String =
        listOf(address.path.trim('/'), name).filter { it.isNotEmpty() }.joinToString("/")
}
