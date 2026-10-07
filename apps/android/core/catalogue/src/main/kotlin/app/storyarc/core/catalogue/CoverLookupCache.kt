package app.storyarc.core.catalogue

import app.storyarc.core.model.CoverLookupProvider
import java.io.File
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * What a provider answered about one publication.
 *
 * A refusal is recorded as well as a hit, and that is the point of the type. `cover-art`
 * asks that "the same publication is never looked up twice, because a provider that asks not
 * to be crawled is entitled to that" -- and a cache that remembered only the hits would
 * re-ask every publication a provider has no cover for, which is most of them.
 */
@Serializable
data class CoverLookupAnswer(
    val provider: CoverLookupProvider,
    /** Where the picture is, or null when the provider had none. */
    val imageUrl: String? = null,
)

/**
 * Every answer a provider has given, on disk, keyed by publication.
 *
 * **In the app's data directory rather than its cache directory.** `StorageUsage.clearCache`
 * empties the cache directory, and a reader clearing decoded pages has not asked for
 * permission to crawl three catalogues again. The file is small -- one entry per publication
 * -- so it costs a reader nothing to keep.
 *
 * iOS's `CoverLookupCache` keeps the same file for the same reason.
 */
class CoverLookupCache(private val file: File) {

    companion object {
        /**
         * Lenient about fields it does not know, the way every store here is: a build that
         * adds a field must still read what an earlier build wrote.
         */
        private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

        private const val FNV_BASIS = -0x340d631b7bdddcdbL
        private const val FNV_PRIME = 0x100000001b3L

        /** The cache every lookup shares, in the app's data directory. */
        fun inDataDirectory(filesDir: File): CoverLookupCache =
            CoverLookupCache(File(filesDir, "cover-lookup/answers.json"))
    }

    private val answers: MutableMap<String, CoverLookupAnswer> =
        runCatching { json.decodeFromString<Map<String, CoverLookupAnswer>>(file.readText()) }
            .getOrElse { emptyMap() }
            .toMutableMap()

    /** What this publication has already been told, or null when it has never been asked. */
    fun answer(key: String): CoverLookupAnswer? = answers[key]

    /** Records an answer, including a refusal, and writes the file. */
    fun record(answer: CoverLookupAnswer, key: String) {
        answers[key] = answer
        write()
    }

    /**
     * Forgets one publication's answer, so it may be asked once more.
     *
     * The escape hatch a cached refusal needs. A provider that answered 429 was asking for
     * later rather than never, and a reader who asks for this publication again by hand is
     * the "later" -- but nothing else re-asks, which is what keeps the app polite.
     */
    /**
     * Title-search answers, beside the identifier answers in a file of their own, so a cache
     * written before this existed reads exactly as it did.
     */
    private val titleFile = File(file.parentFile, "${file.nameWithoutExtension}-titles.json")

    private val titles: MutableMap<String, List<CoverCandidate>> =
        runCatching {
            json.decodeFromString<Map<String, List<CoverCandidate>>>(titleFile.readText())
        }.getOrElse { emptyMap() }.toMutableMap()

    fun candidates(key: String): List<CoverCandidate>? = titles[key]

    fun recordCandidates(key: String, found: List<CoverCandidate>) {
        titles[key] = found
        runCatching {
            titleFile.parentFile?.mkdirs()
            titleFile.writeText(json.encodeToString(titles.toMap()))
        }
    }

    fun forget(key: String) {
        answers.remove(key)
        pictureFile(key).delete()
        write()
    }

    /**
     * The picture a lookup found, kept beside the answers.
     *
     * An answer names where a picture is, and a publication asked for again at another size
     * would fetch it a second time without this: "the same publication is never looked up
     * twice" covers the picture as well as the address.
     */
    private val pictures = File(file.parentFile, "${file.nameWithoutExtension}-pictures")

    fun picture(key: String): ByteArray? = runCatching { pictureFile(key).readBytes() }.getOrNull()

    fun recordPicture(key: String, data: ByteArray) {
        runCatching {
            pictures.mkdirs()
            pictureFile(key).writeBytes(data)
        }
    }

    private fun pictureFile(key: String): File =
        File(pictures, key.toByteArray().fold(FNV_BASIS) { hash, byte ->
            (hash xor byte.toLong()) * FNV_PRIME
        }.toString(36))

    private fun write() {
        runCatching {
            file.parentFile?.mkdirs()
            file.writeText(json.encodeToString(answers.toMap()))
        }
    }
}
