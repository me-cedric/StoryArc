package app.storyarc.core.model

import kotlinx.serialization.Serializable

/**
 * A cover the reader chose, with the key the store files it under.
 *
 * The key is [PublicationIdentity.coverOverrideKey]: `sha:<digest>` where the publication has a
 * content digest, its stable identifier where it has none. Both platforms spell it the same,
 * which is what lets a cover chosen on one be found on the other.
 */
class ChosenCover(val key: String, val image: ByteArray) {
    override fun equals(other: Any?): Boolean =
        other is ChosenCover && key == other.key && image.contentEquals(other.image)

    override fun hashCode(): Int = 31 * key.hashCode() + image.contentHashCode()

    override fun toString(): String = "ChosenCover($key, ${image.size} bytes)"
}

/**
 * Where chosen covers are kept, as far as an export and an import need to see.
 *
 * An interface in the model because the store itself lives in `:core:format`, and
 * `:core:persistence`, where the archive reads and writes every other part of the library,
 * cannot see `:core:format`.
 */
interface ChosenCoverStore {
    /**
     * Every chosen cover this store can name.
     *
     * The store names the ones it has filed with their key. [candidates] lets it find the ones
     * chosen before it filed keys, by trying each key it is handed.
     */
    fun chosen(candidates: Collection<String>): List<ChosenCover>

    fun image(key: String): ByteArray?

    /** Whether the image was written. */
    fun store(key: String, image: ByteArray): Boolean

    fun remove(key: String)
}

/**
 * The key a chosen cover for this publication is filed under.
 *
 * The content digest where there is one, because it survives a rename and a move; the stable
 * identifier where there is none. `cover-for-every-publication` task 2.1.
 */
val PublicationIdentity.coverOverrideKey: String
    get() = contentDigest?.let { "sha:$it" } ?: stableId

/**
 * One chosen cover as the document spells it: the store's own key and the image in base64.
 *
 * design.md: "Only the covers a reader *chose* are images with no other source, and those are
 * few and base64 in the body is enough."
 */
@Serializable
data class DocumentCover(val key: String, val image: String)
