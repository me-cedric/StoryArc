package app.storyarc.core.persistence

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.driver.AndroidSQLiteDriver
import androidx.sqlite.execSQL
import app.storyarc.core.model.ElementLocator
import app.storyarc.core.model.PublicationIdentity
import app.storyarc.core.model.ReadingPosition
import app.storyarc.core.model.ReadingProgress
import java.io.File
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

/**
 * The migrations of the progress table, run under a real SQLite on the host.
 *
 * `audiobooks-and-playback` task 17.3: `MIGRATION_3_4` had never run under SQLite, because
 * `ProgressMigrationTest` is an instrumented test and nothing had run it. Robolectric's native
 * SQLite is the same engine, so the statements are proved here and the instrumented test stays
 * the device's own check. The version 2 table is written out for the reason that test gives: the
 * point is to upgrade a table shaped the way a shipped one is.
 */
@RunWith(RobolectricTestRunner::class)
// Robolectric ships no image for API 37, and nothing here has an API level in it.
@Config(sdk = [34])
class ProgressMigrationHostTest {

    @get:Rule
    val folder = TemporaryFolder()

    private val v2 = """
        CREATE TABLE IF NOT EXISTS progress (
            id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
            server_key TEXT,
            content_digest TEXT,
            normalized_path TEXT,
            page_index INTEGER NOT NULL,
            page_count INTEGER NOT NULL,
            progression REAL NOT NULL,
            locator TEXT,
            is_finished INTEGER NOT NULL,
            finished_at INTEGER,
            updated_at INTEGER NOT NULL,
            synced_progression REAL
        )
    """.trimIndent()

    private fun upgraded(through: List<androidx.room.migration.Migration>, body: SQLiteConnection.() -> Unit) {
        val connection = AndroidSQLiteDriver().open(File(folder.root, "migration.db").path)
        try {
            connection.execSQL(v2)
            through.forEach { it.migrate(connection) }
            connection.body()
        } finally {
            connection.close()
        }
    }

    private fun SQLiteConnection.readInt(sql: String): Int =
        prepare(sql).use { statement ->
            assertTrue("the row is there", statement.step())
            statement.getInt(0)
        }

    private fun SQLiteConnection.readString(sql: String): String? =
        prepare(sql).use { statement ->
            assertTrue("the row is there", statement.step())
            if (statement.isNull(0)) null else statement.getText(0)
        }

    @Test
    fun `a page position written before audiobooks existed is still not a listening one`() {
        upgraded(emptyList()) {
            execSQL(
                "INSERT INTO progress (page_index, page_count, progression, is_finished, updated_at) " +
                    "VALUES (4, 20, 0.2, 0, 1000)",
            )
            MIGRATION_2_3.migrate(this)

            assertEquals(-1, readInt("SELECT part_index FROM progress"))
            assertEquals(4, readInt("SELECT page_index FROM progress"))
        }
    }

    @Test
    fun `an offset that may be a file time is reset to its part's start`() {
        upgraded(listOf(MIGRATION_2_3)) {
            execSQL(
                "INSERT INTO progress (page_index, page_count, progression, is_finished, updated_at, " +
                    "part_index, part_count, offset_millis, part_duration_millis) " +
                    "VALUES (-1, 0, 0.9, 0, 1000, 9, 10, 540000, 60000)",
            )

            MIGRATION_3_4.migrate(this)

            assertEquals(0, readInt("SELECT offset_millis FROM progress"))
            assertEquals(9, readInt("SELECT part_index FROM progress"))
        }
    }

    @Test
    fun `a place in the first part keeps its offset`() {
        upgraded(listOf(MIGRATION_2_3)) {
            execSQL(
                "INSERT INTO progress (page_index, page_count, progression, is_finished, updated_at, " +
                    "part_index, part_count, offset_millis, part_duration_millis) " +
                    "VALUES (-1, 0, 0.1, 0, 1000, 0, 10, 20000, 60000)",
            )

            MIGRATION_3_4.migrate(this)

            assertEquals(20_000, readInt("SELECT offset_millis FROM progress"))
        }
    }

    @Test
    fun `a page position is left alone by the audio repair`() {
        upgraded(listOf(MIGRATION_2_3)) {
            execSQL(
                "INSERT INTO progress (page_index, page_count, progression, is_finished, updated_at) " +
                    "VALUES (4, 20, 0.2, 0, 1000)",
            )

            MIGRATION_3_4.migrate(this)

            assertEquals(4, readInt("SELECT page_index FROM progress"))
            assertEquals(-1, readInt("SELECT part_index FROM progress"))
        }
    }

    @Test
    fun `a bare chapter number is rewritten to the chapter form, and the chapter form is left`() {
        upgraded(emptyList()) {
            execSQL(
                "INSERT INTO progress (server_key, page_index, page_count, progression, is_finished, updated_at) " +
                    "VALUES ('3E7F6C1C-0000-0000-0000-00000000AAAA:42', 4, 20, 0.2, 0, 1000)",
            )
            execSQL(
                "INSERT INTO progress (server_key, page_index, page_count, progression, is_finished, updated_at) " +
                    "VALUES ('3E7F6C1C-0000-0000-0000-00000000AAAA:chapter:7', 4, 20, 0.2, 0, 1000)",
            )

            MIGRATION_4_5.migrate(this)

            assertEquals(
                "3E7F6C1C-0000-0000-0000-00000000AAAA:chapter:42",
                readString("SELECT server_key FROM progress WHERE id = 1"),
            )
            assertEquals(
                "3E7F6C1C-0000-0000-0000-00000000AAAA:chapter:7",
                readString("SELECT server_key FROM progress WHERE id = 2"),
            )
        }
    }

    /**
     * `reading-progress` O27, through Room itself: a version 5 file on disk is opened by the
     * store, so Room runs [MIGRATION_5_6] and checks the table against the entity.
     */
    @Test
    fun `a reflowable position stored before the element existed reads back with none, and a new one keeps it`() =
        runTest {
            val context = RuntimeEnvironment.getApplication()
            val name = "progress-v5.db"
            val file = context.getDatabasePath(name).apply { parentFile?.mkdirs(); delete() }
            val connection = AndroidSQLiteDriver().open(file.path)
            try {
                connection.execSQL(v2)
                listOf("server_key", "content_digest", "normalized_path").forEach {
                    connection.execSQL("CREATE INDEX IF NOT EXISTS index_progress_$it ON progress ($it)")
                }
                listOf(MIGRATION_2_3, MIGRATION_3_4, MIGRATION_4_5).forEach { it.migrate(connection) }
                connection.execSQL(
                    "INSERT INTO progress (content_digest, page_index, page_count, progression, locator, " +
                        "is_finished, updated_at) VALUES ('d2', -1, 0, 0.45, '{}', 0, 1000)",
                )
                connection.execSQL("PRAGMA user_version = 5")
            } finally {
                connection.close()
            }

            val store = ProgressStore.open(context, name)
            val identity = PublicationIdentity(contentDigest = "d2")
            assertEquals(ReadingPosition.Reflowable(0.45, "{}"), store.progress(identity)?.position)

            val element = ElementLocator("OEBPS/ch1.xhtml", "body > p:nth-child(18)", "the end. ", "Paragraph", "d2")
            val position = ReadingPosition.Reflowable(0.5, "{}", element)
            store.save(ReadingProgress(identity, position, updatedAtEpochMillis = 2_000))
            assertEquals(position, store.progress(identity)?.position)
        }
}
