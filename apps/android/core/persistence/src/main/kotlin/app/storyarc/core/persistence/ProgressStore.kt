package app.storyarc.core.persistence

import android.content.Context
import androidx.room.ColumnInfo
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.Update
import androidx.room.migration.Migration
import androidx.sqlite.SQLiteConnection
import androidx.sqlite.execSQL
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.UUID

/**
 * One reading position, as Room stores it.
 *
 * The identity fields are flattened into their own columns rather than stored as
 * one blob, because ADR-0006 requires looking a record up by *any* of them: a file
 * read from a folder and the same file served by Kavita have to resolve to one
 * record, and that only works if each component is queryable on its own. iOS's
 * SwiftData model has the same three columns for the same reason.
 */
@Entity(tableName = "progress")
internal data class ProgressRow(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    /** The server's identifier, when the publication came from a source with one. */
    @ColumnInfo(name = "server_key", index = true) val serverKey: String?,
    /** A digest of the file's size plus its first and last bytes. */
    @ColumnInfo(name = "content_digest", index = true) val contentDigest: String?,
    /** Last resort, when neither of the above is obtainable. */
    @ColumnInfo(name = "normalized_path", index = true) val normalizedPath: String?,
    /**
     * A page index, or -1 for a reflowable position.
     *
     * Stored as columns rather than as an encoded blob so a future query can order
     * or filter by how far in someone is without decoding every row.
     */
    @ColumnInfo(name = "page_index") val pageIndex: Int,
    @ColumnInfo(name = "page_count") val pageCount: Int,
    @ColumnInfo(name = "progression") val progression: Double,
    @ColumnInfo(name = "locator") val locator: String?,
    @ColumnInfo(name = "is_finished") val isFinished: Boolean,
    /** When the finished flag was set. Null for a publication nobody has finished. */
    @ColumnInfo(name = "finished_at") val finishedAt: Long? = null,
    @ColumnInfo(name = "updated_at") val updatedAt: Long,
    @ColumnInfo(name = "synced_progression") val syncedProgression: Double?,
)

@Dao
internal interface ProgressDao {
    @Query("SELECT * FROM progress WHERE server_key = :key LIMIT 1")
    suspend fun byServerKey(key: String): ProgressRow?

    @Query("SELECT * FROM progress WHERE content_digest = :digest LIMIT 1")
    suspend fun byDigest(digest: String): ProgressRow?

    @Query("SELECT * FROM progress WHERE normalized_path = :path LIMIT 1")
    suspend fun byPath(path: String): ProgressRow?

    @Query("SELECT * FROM progress ORDER BY updated_at DESC LIMIT :limit")
    suspend fun recent(limit: Int): List<ProgressRow>

    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(row: ProgressRow)

    @Update
    suspend fun update(row: ProgressRow)

    @Query("DELETE FROM progress WHERE id = :id")
    suspend fun delete(id: Long)

    /**
     * Forgets every recorded position.
     *
     * `settings-and-about` requires reading history to be individually clearable, and this
     * is the whole of "clear". Deliberately not a file deletion: dropping the database from
     * under an open connection is how a later read finds a corrupt file instead of an empty
     * one.
     */
    @Query("DELETE FROM progress")
    suspend fun clear()
}

@Database(entities = [ProgressRow::class], version = 2, exportSchema = false)
internal abstract class ProgressDatabase : RoomDatabase() {
    abstract fun progress(): ProgressDao
}

/**
 * Adds the completion timestamp `reading-progress` asks for.
 *
 * A written migration rather than `fallbackToDestructiveMigration`, because the fallback
 * drops the table — and ADR-0006 puts losing a reading position at the top of the list of
 * things this app must never do. A nullable column needs no default: every row that
 * predates this reads back `null`, which is the truthful answer for a publication whose
 * completion was never recorded, including one already marked finished before the column
 * existed.
 */
internal val MIGRATION_1_2 = object : Migration(1, 2) {
    override fun migrate(connection: SQLiteConnection) {
        connection.execSQL("ALTER TABLE progress ADD COLUMN finished_at INTEGER")
    }
}

/**
 * Reading positions, stored locally and authoritative.
 *
 * ADR-0006: "Progress is written locally first, always, for every publication —
 * including ones from sources that cannot store progress. Remote sync is a
 * projection of that store outward, never a prerequisite for it." So this has no
 * idea a server exists, and the app works fully with none configured.
 *
 * iOS's `ProgressStore` is the same store on SwiftData. The schema semantics are
 * shared and specified in the ADR; the implementations are not.
 */
class ProgressStore internal constructor(private val database: ProgressDatabase) {

    companion object {
        /** Opens the store on disk. */
        fun open(context: Context, name: String = "progress.db"): ProgressStore =
            ProgressStore(
                Room.databaseBuilder(
                    context.applicationContext,
                    ProgressDatabase::class.java,
                    name,
                ).addMigrations(MIGRATION_1_2).build(),
            )

        /** An in-memory store, for tests. */
        fun inMemory(context: Context): ProgressStore =
            ProgressStore(
                Room.inMemoryDatabaseBuilder(context, ProgressDatabase::class.java)
                    .addMigrations(MIGRATION_1_2).build(),
            )
    }

    /**
     * The progress recorded for a publication, if any.
     *
     * Matches on *any* identity component, in ADR-0006's order of preference. A
     * file that gains a server id later still finds the record written against its
     * digest.
     */
    suspend fun progress(identity: PublicationIdentity): ReadingProgress? =
        withContext(Dispatchers.IO) { existing(identity)?.let(::toDomain) }

    /**
     * Records a position, replacing whatever was there.
     *
     * Last write wins *locally* — this is one device, and the interesting conflict
     * rules apply between devices, not within one.
     */
    suspend fun save(progress: ReadingProgress): Unit = withContext(Dispatchers.IO) {
        val dao = database.progress()
        val existing = existing(progress.identity)
        val position = progress.position

        val row = ProgressRow(
            id = existing?.id ?: 0,
            // Identity components fill in as they become known, so a record written
            // against a path can later be found by its digest.
            serverKey = existing?.serverKey ?: serverKey(progress.identity),
            contentDigest = existing?.contentDigest ?: progress.identity.contentDigest,
            normalizedPath = existing?.normalizedPath ?: progress.identity.normalizedPath,
            pageIndex = (position as? ReadingPosition.Page)?.index ?: -1,
            pageCount = (position as? ReadingPosition.Page)?.total ?: 0,
            progression = position.fraction,
            locator = (position as? ReadingPosition.Reflowable)?.locator,
            // Finished is sticky. ADR-0006: unmarking a finished publication is a
            // deliberate act, and losing it to a routine save is not something a
            // user would ever want.
            isFinished = (existing?.isFinished ?: false) || progress.isFinished,
            // Stamped the moment the flag first turns on, and never restamped: reading a
            // finished publication again writes a new position, not a new completion.
            finishedAt = existing?.finishedAt
                ?: progress.finishedAtEpochMillis.takeIf { progress.isFinished }
                ?: progress.updatedAtEpochMillis.takeIf { progress.isFinished },
            updatedAt = progress.updatedAtEpochMillis,
            syncedProgression = progress.syncedPosition?.fraction,
        )
        if (existing == null) dao.insert(row) else dao.update(row)
    }

    /**
     * Everything recorded, most recently read first.
     *
     * What `library-browsing`'s "Continue reading" row is built from.
     */
    suspend fun recent(limit: Int = 50): List<ReadingProgress> =
        withContext(Dispatchers.IO) { database.progress().recent(limit).map(::toDomain) }

    /**
     * Sets the finished flag, in either direction.
     *
     * Separate from [save] because finished is sticky there: a routine save must never
     * unmark a publication. `reading-progress` calls unmarking "a deliberate act", and this
     * is the deliberate act -- a reader choosing the state, not a page turn implying it.
     */
    suspend fun mark(
        identity: PublicationIdentity,
        isFinished: Boolean,
        at: Long = System.currentTimeMillis(),
    ): Unit = withContext(Dispatchers.IO) {
        val dao = database.progress()
        val row = existing(identity)
        if (row == null) {
            // Nothing recorded yet, and marking read is still a position: the whole of it.
            dao.insert(
                ProgressRow(
                    serverKey = serverKey(identity),
                    contentDigest = identity.contentDigest,
                    normalizedPath = identity.normalizedPath,
                    pageIndex = -1,
                    pageCount = 0,
                    progression = if (isFinished) 1.0 else 0.0,
                    locator = null,
                    isFinished = isFinished,
                    finishedAt = at.takeIf { isFinished },
                    updatedAt = at,
                    syncedProgression = null,
                ),
            )
        } else {
            dao.update(
                row.copy(
                    isFinished = isFinished,
                    // Kept while it stays on, dropped when it goes off: an unfinished
                    // publication has no completion to date.
                    finishedAt = if (isFinished) row.finishedAt ?: at else null,
                    progression = if (isFinished) 1.0 else row.progression,
                    updatedAt = at,
                ),
            )
        }
    }

    /** Forgets one publication's position. A deliberate act, per ADR-0006. */
    suspend fun forget(identity: PublicationIdentity): Unit = withContext(Dispatchers.IO) {
        existing(identity)?.let { database.progress().delete(it.id) }
    }

    /**
     * Forgets every recorded position.
     *
     * `settings-and-about` requires reading history to be individually clearable. A reader
     * who clears this is choosing to lose their places, which is why the confirmation names
     * it rather than calling it "data".
     */
    suspend fun clear(): Unit = withContext(Dispatchers.IO) {
        database.progress().clear()
    }

    private suspend fun existing(identity: PublicationIdentity): ProgressRow? {
        val dao = database.progress()
        serverKey(identity)?.let { key -> dao.byServerKey(key)?.let { return it } }
        identity.contentDigest?.let { digest -> dao.byDigest(digest)?.let { return it } }
        identity.normalizedPath?.let { path -> dao.byPath(path)?.let { return it } }
        return null
    }

    /** A server identifier flattened to one string, so it can be one column. */
    private fun serverKey(identity: PublicationIdentity): String? =
        identity.serverIdentifier?.let { "${it.sourceId}:${it.remoteId}" }

    private fun toDomain(row: ProgressRow): ReadingProgress = ReadingProgress(
        identity = PublicationIdentity(
            serverIdentifier = row.serverKey?.let { key ->
                val separator = key.indexOf(':')
                if (separator <= 0) {
                    null
                } else {
                    runCatching {
                        PublicationIdentity.ServerIdentifier(
                            UUID.fromString(key.take(separator)),
                            key.substring(separator + 1),
                        )
                    }.getOrNull()
                }
            },
            contentDigest = row.contentDigest,
            normalizedPath = row.normalizedPath,
        ),
        position = if (row.pageIndex >= 0) {
            ReadingPosition.Page(row.pageIndex, row.pageCount)
        } else {
            ReadingPosition.Reflowable(row.progression, row.locator.orEmpty())
        },
        isFinished = row.isFinished,
        finishedAtEpochMillis = row.finishedAt,
        updatedAtEpochMillis = row.updatedAt,
        syncedPosition = row.syncedProgression?.let { ReadingPosition.Reflowable(it, "") },
    )
}
