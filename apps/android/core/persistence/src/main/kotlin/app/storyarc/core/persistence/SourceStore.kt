package app.storyarc.core.persistence

import android.content.Context
import android.content.SharedPreferences
import app.storyarc.core.model.Source
import app.storyarc.core.model.SourceKind
import app.storyarc.core.model.SourceRegistry
import app.storyarc.core.model.SourceTombstone
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.util.UUID

/**
 * The source registry, on disk.
 *
 * `sources` requires the registry to be "ordered, persistent", and the order to survive a
 * launch. One JSON blob for the same reason [SettingsStore] is one: the whole registry is
 * read together to draw one list, and a store that read it key by key would let two halves
 * of it disagree.
 *
 * **Connection state is not stored.** It describes a network right now, so a state read
 * back from disk would be a claim about the past. Every source loads as `Connecting` and
 * whatever probes it says otherwise, which is also the honest thing to show a reader on a
 * cold launch. iOS's `SourceStore` makes the same choice.
 */
class SourceStore(private val preferences: SharedPreferences) {

    companion object {
        fun open(context: Context): SourceStore =
            SourceStore(context.getSharedPreferences("app.storyarc.sources", Context.MODE_PRIVATE))

        private const val REGISTRY = "registry"

        private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    }

    fun registry(): SourceRegistry =
        preferences.getString(REGISTRY, null)
            ?.let { runCatching { json.decodeFromString<StoredRegistry>(it).toDomain() }.getOrNull() }
            ?: SourceRegistry()

    fun save(registry: SourceRegistry) {
        preferences.edit()
            .putString(REGISTRY, json.encodeToString(StoredRegistry.of(registry)))
            .apply()
    }

    /** Forgets every source. Used by a reset, and by the tests. */
    fun reset() {
        preferences.edit().remove(REGISTRY).apply()
    }
}

/**
 * What is actually written.
 *
 * A separate shape rather than making [Source] serializable, because the durable fields and
 * the runtime ones are different sets and one annotation would quietly carry a stale
 * connection state to disk.
 */
@Serializable
internal data class StoredRegistry(
    val sources: List<StoredSource> = emptyList(),
    val tombstones: List<StoredTombstone> = emptyList(),
) {
    fun toDomain(): SourceRegistry = SourceRegistry(
        // A kind this build does not know is dropped rather than guessed at. A source
        // written by a newer version has a type this one cannot fetch from, and showing it
        // as a folder would be worse than not showing it.
        sources = sources.mapNotNull { entry ->
            val kind = runCatching { SourceKind.valueOf(entry.kind) }.getOrNull() ?: return@mapNotNull null
            Source(
                id = UUID.fromString(entry.id),
                displayName = entry.displayName,
                kind = kind,
                lastSuccessfulSyncEpochMillis = entry.lastSuccessfulSyncEpochMillis,
                credentialReference = entry.credentialReference,
                locator = entry.locator,
            )
        },
        tombstones = tombstones.map {
            SourceTombstone(UUID.fromString(it.sourceId), it.removedAtEpochMillis)
        },
    )

    companion object {
        fun of(registry: SourceRegistry) = StoredRegistry(
            sources = registry.sources.map {
                StoredSource(
                    id = it.id.toString(),
                    displayName = it.displayName,
                    kind = it.kind.name,
                    lastSuccessfulSyncEpochMillis = it.lastSuccessfulSyncEpochMillis,
                    credentialReference = it.credentialReference,
                    locator = it.locator,
                )
            },
            tombstones = registry.tombstones.map {
                StoredTombstone(it.sourceId.toString(), it.removedAtEpochMillis)
            },
        )
    }
}

@Serializable
internal data class StoredSource(
    val id: String,
    val displayName: String,
    val kind: String,
    val lastSuccessfulSyncEpochMillis: Long? = null,
    val credentialReference: String? = null,
    val locator: String? = null,
)

@Serializable
internal data class StoredTombstone(val sourceId: String, val removedAtEpochMillis: Long)
