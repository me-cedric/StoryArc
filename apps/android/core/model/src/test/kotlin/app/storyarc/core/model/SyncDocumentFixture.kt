package app.storyarc.core.model

import java.io.File
import java.util.UUID

/**
 * One library as a sync writes it, described once, so both platforms assert the same document.
 *
 * `library-sync` task 5.2. Beside this file is `sync-written-by-android.json`, the document the
 * Android sync path writes from [snapshot]; beside iOS's `SyncDocumentFixture` is
 * `sync-written-by-ios.json`. Each suite pins its own file and merges the other's. iOS's
 * `SyncDocumentFixture` builds the identical library.
 */
object SyncDocumentFixture {

    const val ANDROID_DEVICE = "android-device"
    const val IOS_DEVICE = "ios-device"
    const val APP_VERSION = "10.14.0"

    /** 2026-01-01T00:00:00Z, and the moments after it in seconds. */
    fun at(second: Long): Long = 1_767_225_600_000L + second * 1_000L

    val written: Long = at(1_000)

    val collectionId: UUID = UUID.fromString("33333333-3333-3333-3333-333333333333")
    val listId: UUID = UUID.fromString("44444444-4444-4444-4444-444444444444")
    val kavitaId: UUID = UUID.fromString("55555555-5555-5555-5555-555555555555")
    val removedId: UUID = UUID.fromString("66666666-6666-6666-6666-666666666666")

    val book = PublicationIdentity(contentDigest = "d1")
    val fontSizeField = "reflowable/|values.fontSizePercent"

    /** The library each platform's sync writes. */
    val snapshot: LibrarySnapshot
        get() = LibrarySnapshot(
            sources = SourceRegistry(
                listOf(Source(id = kavitaId, displayName = "Kavita", kind = SourceKind.KAVITA_SERVER)),
            ),
            shelves = Shelves(
                collections = listOf(
                    PublicationCollection(
                        id = collectionId, name = "Image Comics", members = setOf("path:/a.cbz"),
                        changedAtEpochMillis = at(100),
                    ),
                ),
                lists = listOf(
                    ReadingList(
                        id = listId, name = "Crossover", entries = listOf("path:/b.cbz", "path:/a.cbz"),
                        changedAtEpochMillis = at(200),
                    ),
                ),
            ),
            removedShelves = listOf(ShelfTombstone(removedId, at(300))),
            settings = AppSettings(appearance = AppearanceMode.DARK),
            settingsChangedAt = mapOf("appearance" to at(400)),
            themes = ShelfMemory().settingDefault(
                ShelfSettings().let { it.copy(values = it.values.copy(fontSize = FontSizeStep.LARGE)) },
                ThemeScope.REFLOWABLE,
            ),
            themesChangedAt = mapOf(fontSizeField to at(500)),
            progress = listOf(
                ReadingProgress(book, ReadingPosition.Page(12, 40), updatedAtEpochMillis = at(600)),
                ReadingProgress(
                    PublicationIdentity(serverIdentifier = PublicationIdentity.ServerIdentifier(kavitaId, "chapter:9")),
                    ReadingPosition.Page(3, 20),
                    updatedAtEpochMillis = at(600),
                ),
            ),
        )

    /**
     * The device that reads the other platform's document: it holds the same shelves from
     * before, an older setting and an earlier position.
     */
    val receiver: LibrarySnapshot
        get() = LibrarySnapshot(
            shelves = Shelves(
                collections = listOf(
                    PublicationCollection(id = collectionId, name = "Comics", members = setOf("path:/c.cbz"), changedAtEpochMillis = at(50)),
                    PublicationCollection(id = removedId, name = "Gone", changedAtEpochMillis = at(50)),
                ),
            ),
            settings = AppSettings(appearance = AppearanceMode.LIGHT),
            settingsChangedAt = mapOf("appearance" to at(10)),
            progress = listOf(ReadingProgress(book, ReadingPosition.Page(5, 40), updatedAtEpochMillis = at(20))),
        )

    private fun file(path: String) = File(System.getProperty("storyarc.repoRootDir"), path)

    const val ANDROID_PATH = "apps/android/core/model/src/test/kotlin/app/storyarc/core/model/sync-written-by-android.json"
    const val IOS_PATH = "apps/ios/Packages/StoryArcKit/Tests/StoryArcCoreTests/sync-written-by-ios.json"

    fun writtenByAndroid(): String = file(ANDROID_PATH).readText()

    fun writtenByIos(): String = file(IOS_PATH).readText()
}
