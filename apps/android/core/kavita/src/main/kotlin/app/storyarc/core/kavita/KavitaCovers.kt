package app.storyarc.core.kavita

import java.util.Base64
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * What Kavita's cover-upload route is sent.
 *
 * `url` is Kavita's own field name for a picture that may arrive either as an address or as
 * base64, and this client always sends base64: an address would ask the server to fetch a
 * file from this device, which it cannot reach.
 */
@Serializable
internal data class KavitaCoverUpload(val id: Int, val url: String)

/**
 * Writes a cover to a reading list the signed-in reader owns.
 *
 * **The one Kavita cover route a normal reader may use.** The other five -- series, volume,
 * chapter, collection and library -- require the administrator role, so `cover-art` forbids
 * offering them at all. `CoverWriteBack.offer` is what decides that, and this function is
 * what it decides to call.
 *
 * **Not verified against a live server.** Task 5.3 of `cover-for-every-publication` is the
 * owner step that does it, and the mock in `scripts/kavita-server.mjs` is where a correction
 * gets recorded. The shape below is Kavita's documented `UploadFileDto`.
 *
 * In a file of its own rather than inside `KavitaClient.kt`, which is already 650 lines.
 * iOS's `KavitaCovers.swift` sits beside its client for the same reason.
 */
suspend fun KavitaClient.uploadReadingListCover(listId: Int, image: ByteArray) {
    if (image.isEmpty()) throw KavitaError.ImageRejected
    if (image.size > KavitaClient.COVER_UPLOAD_CEILING) throw KavitaError.ImageTooLarge

    // `java.util.Base64`, not `android.util.Base64`: the same output, and it runs in a JVM
    // unit test. minSdk is 31, so it is available everywhere this ships.
    val encoded = Base64.getEncoder().encodeToString(image)
    // Versioned, so an older Kavita without the route says so once and is not asked again
    // for the rest of the session.
    listing(
        "Upload/reading-list",
        Json.encodeToString(KavitaCoverUpload.serializer(), KavitaCoverUpload(listId, encoded)),
    )
}
