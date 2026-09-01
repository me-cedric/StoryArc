package app.storyarc.core.persistence

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.driver.AndroidSQLiteDriver
import androidx.sqlite.execSQL
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * What happens to the positions already on somebody's phone.
 *
 * The store's tests build a database from the current entity, so they exercise the schema
 * Room *creates* and never the one it *upgrades*. Those are different code paths and only
 * one of them runs on a device that has been in use — which is every device that matters.
 *
 * **The default on `part_index` is the whole of this.** It is the discriminator that tells
 * a listening position from a page one, so a column added with a default of 0 would read
 * every comic and every book already in the library back as an audiobook at chapter zero.
 * A migration cannot be un-run, and nothing in a build would have said a word.
 *
 * The schema below is version 2's, written out rather than generated: the point is to
 * upgrade a table shaped the way a shipped one is, and asking Room for it would ask the
 * version under test to describe the version it is replacing.
 */
@RunWith(AndroidJUnit4::class)
class ProgressMigrationTest {

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

    private fun openV2(): Pair<SQLiteConnection, File> {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val file = File(context.cacheDir, "migration-${System.nanoTime()}.db")
        file.delete()
        val connection = AndroidSQLiteDriver().open(file.path)
        connection.execSQL(v2)
        return connection to file
    }

    private fun SQLiteConnection.readInt(sql: String): Int =
        prepare(sql).use { statement ->
            assertTrue("the row is there", statement.step())
            statement.getInt(0)
        }

    @Test
    fun aPagePositionWrittenBeforeAudiobooksExistedIsStillNotOne() {
        val (connection, file) = openV2()
        try {
            connection.execSQL(
                "INSERT INTO progress " +
                    "(server_key, content_digest, normalized_path, page_index, page_count, " +
                    "progression, locator, is_finished, finished_at, updated_at, " +
                    "synced_progression) " +
                    "VALUES (NULL, NULL, '/books/one.cbz', 4, 20, 0.2, NULL, 0, NULL, 1000, NULL)",
            )

            MIGRATION_2_3.migrate(connection)

            assertEquals(
                "a row that predates the case must not read back as a listening one",
                -1,
                connection.readInt("SELECT part_index FROM progress"),
            )
            assertEquals(4, connection.readInt("SELECT page_index FROM progress"))
        } finally {
            connection.close()
            file.delete()
        }
    }

    @Test
    fun theUpgradedTableTakesAListeningPosition() {
        val (connection, file) = openV2()
        try {
            MIGRATION_2_3.migrate(connection)

            connection.execSQL(
                "INSERT INTO progress " +
                    "(server_key, content_digest, normalized_path, page_index, page_count, " +
                    "progression, locator, is_finished, finished_at, updated_at, " +
                    "synced_progression, part_index, part_count, offset_millis, " +
                    "part_duration_millis) " +
                    "VALUES (NULL, NULL, '/books/sea-room.m4b', -1, 0, 0.5, NULL, 0, NULL, " +
                    "1000, NULL, 2, 5, 42000, 300000)",
            )

            assertEquals(2, connection.readInt("SELECT part_index FROM progress"))
            assertEquals(42_000, connection.readInt("SELECT offset_millis FROM progress"))
        } finally {
            connection.close()
            file.delete()
        }
    }

    /**
     * The nullable one stays nullable.
     *
     * A read-aloud position has no duration, and a `NOT NULL DEFAULT 0` here would turn
     * "nobody knows" into a number the moment it was stored.
     */
    @Test
    fun aPartWithNoKnownLengthCanBeStoredWithNone() {
        val (connection, file) = openV2()
        try {
            MIGRATION_2_3.migrate(connection)

            connection.execSQL(
                "INSERT INTO progress " +
                    "(page_index, page_count, progression, is_finished, updated_at, " +
                    "part_index, part_count, offset_millis, part_duration_millis) " +
                    "VALUES (-1, 0, 0.1, 0, 1000, 1, 9, 8000, NULL)",
            )

            connection.prepare("SELECT part_duration_millis FROM progress").use { statement ->
                assertTrue(statement.step())
                assertTrue("no duration stays no duration", statement.isNull(0))
            }
        } finally {
            connection.close()
            file.delete()
        }
    }
}
