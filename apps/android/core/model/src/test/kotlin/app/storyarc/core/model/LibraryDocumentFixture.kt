package app.storyarc.core.model

import java.io.File
import java.util.UUID

/**
 * One library, described once, so both platforms assert the same document.
 *
 * `packages/test-fixtures/library/` holds what each platform's encoder writes from this
 * snapshot. Each suite pins its own file and reads the other's, which is what makes task
 * 1.2's claim — "a test writes on one platform's encoder and reads on the other's decoder" —
 * something a gate can fail on rather than something a handoff asserts.
 *
 * iOS's `LibraryDocumentFixture` builds the identical library.
 */
object LibraryDocumentFixture {

    const val APP_VERSION = "10.14.0"
    const val WRITTEN_AT = 1_767_225_845_000L

    val networkShareId: UUID = UUID.fromString("11111111-1111-1111-1111-111111111111")
    val folderId: UUID = UUID.fromString("22222222-2222-2222-2222-222222222222")
    val collectionId: UUID = UUID.fromString("33333333-3333-3333-3333-333333333333")
    val listId: UUID = UUID.fromString("44444444-4444-4444-4444-444444444444")
    val kavitaId: UUID = UUID.fromString("55555555-5555-5555-5555-555555555555")

    /** The secrets the export must never carry. See `LibraryExportSecrecyTest`. */
    const val PASSWORD = "hunter2correcthorse"
    const val TOKEN = "eyJhbGciOiJIUzI1NiJ9.aGVsbG8.sig"
    const val API_KEY = "ak-9f3c2b1a7e5d4c6b8a0f2e1d3c4b5a69"

    /**
     * Where the committed documents live. `storyarc.repoRootDir` is handed to the test JVM by
     * this module's build file, because a walk up from the working directory escapes a
     * worktree.
     */
    fun document(name: String): String =
        File(System.getProperty("storyarc.repoRootDir"), "packages/test-fixtures/library/$name")
            .readText()

    /** The library both platforms export. */
    val snapshot: LibrarySnapshot
        get() = LibrarySnapshot(
            sources = SourceRegistry(
                sources = listOf(
                    Source(
                        id = networkShareId,
                        displayName = "Comics NAS",
                        kind = SourceKind.NETWORK_SHARE,
                        lastSuccessfulSyncEpochMillis = 1_767_139_445_000L,
                        credentialReference = "keystore:$networkShareId",
                        // The password is in the address, which is where an SMB mount puts
                        // one.
                        locator = "smb://reader:$PASSWORD@nas.local/comics",
                    ),
                    Source(
                        id = folderId,
                        displayName = "Shelf",
                        kind = SourceKind.LOCAL_FOLDER,
                        locator = "/Books/Shelf",
                    ),
                    Source(
                        id = kavitaId,
                        displayName = "Kavita",
                        kind = SourceKind.KAVITA_SERVER,
                        credentialReference = "keystore:$kavitaId",
                        locator = "https://kavita.example/api?apikey=$API_KEY&library=3",
                    ),
                ),
            ),
            certificatePins = mapOf("nas.local" to setOf("AB:CD:EF:01")),
            shelves = Shelves(
                collections = listOf(
                    PublicationCollection(
                        id = collectionId,
                        name = "Image Comics",
                        members = setOf("path:/a.cbz", "path:/b.cbz"),
                        coverMemberId = "path:/b.cbz",
                    ),
                ),
                lists = listOf(
                    ReadingList(
                        id = listId,
                        name = "Crossover",
                        entries = listOf("path:/b.cbz", "path:/a.cbz"),
                    ),
                ),
            ),
            pinnedShelves = PinnedShelves(
                setOf(ShelfPin.Collection(collectionId), ShelfPin.ReadingListPin(listId)),
            ),
            settings = AppSettings(
                appearance = AppearanceMode.OLED_DARK,
                language = "fr",
                turnPagesByTappingTheEdges = false,
                linkReadingThemeToAppearance = true,
                lightReadingTheme = ThemePreset.CALM,
                darkReadingTheme = ThemePreset.FOCUS,
                downloadOverWifiOnly = true,
                maximumDownloadBytes = 4_294_967_296L,
                removeDownloadsAfterFinishing = true,
            ),
            themes = themes,
            progress = listOf(
                ReadingProgress(
                    identity = PublicationIdentity(
                        contentDigest = "d1",
                        normalizedPath = "/a.cbz",
                    ),
                    position = ReadingPosition.Page(12, 40),
                    updatedAtEpochMillis = 1_767_100_000_000L,
                ),
                ReadingProgress(
                    identity = PublicationIdentity(contentDigest = "d2"),
                    position = ReadingPosition.Reflowable(0.375, """{"href":"ch3"}"""),
                    isFinished = true,
                    finishedAtEpochMillis = 1_767_110_000_000L,
                    updatedAtEpochMillis = 1_767_110_000_000L,
                    // Present on this device, and deliberately absent from the document.
                    syncedPosition = ReadingPosition.Reflowable(0.1, "{}"),
                ),
                ReadingProgress(
                    identity = PublicationIdentity(
                        serverIdentifier = PublicationIdentity.ServerIdentifier(kavitaId, "901"),
                    ),
                    position = ReadingPosition.Listening(2, 9, 61_500L, 600_000L),
                    updatedAtEpochMillis = 1_767_120_000_000L,
                ),
            ),
        )

    private val themes: ShelfMemory
        get() {
            val reflowableDefault = ShelfSettings(
                theme = ReadingTheme(
                    preset = ThemePreset.QUIET,
                    deviations = setOf(ThemeAxis.FONT_SIZE, ThemeAxis.LINE_SPACING),
                ),
                values = ThemeValues(
                    typeface = ReaderTypeface.LITERATA,
                    fontSize = FontSizeStep.LARGE,
                    lineHeight = 1.8,
                ),
                transition = PageTransition.FAST_FADE,
            )
            val bone = ShelfSettings(
                transition = PageTransition.VERTICAL_SCROLL,
                adjustments = ImageAdjustments(brightness = 0.2f, isGreyscale = true),
                offsetsSpreads = true,
                fit = PageFit.WIDTH,
            )
            return ShelfMemory()
                .settingDefault(reflowableDefault, ThemeScope.REFLOWABLE)
                .remembering(bone, ThemeScope.FIXED_LAYOUT, "Bone")
                .copy(
                    customPalette = ReaderPalette(
                        name = "Midnight",
                        background = "#101014",
                        foreground = "#E8E8F0",
                    ),
                )
        }
}
