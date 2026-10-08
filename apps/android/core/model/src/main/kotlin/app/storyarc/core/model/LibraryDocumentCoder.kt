package app.storyarc.core.model

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.intOrNull

/**
 * Why a document could not be read.
 *
 * `library-portability` / *A newer document is refused, by name*: the app "names the version
 * it found and the newest it understands, and changes nothing". A type carrying both numbers
 * rather than a formatted string, so the four languages each phrase it themselves.
 */
sealed interface LibraryDocumentFailure {
    /** The bytes are not a JSON object with a `formatVersion` in them. */
    data object NotALibraryDocument : LibraryDocumentFailure

    /**
     * The document declares a version this build does not know.
     *
     * Refused rather than partly read. An older app meeting a newer export can only guess at
     * what it does not understand, and guessing changes data silently; refusing names the
     * problem and leaves the device as it was.
     */
    data class NewerThanThisApp(val found: Int, val understood: Int) : LibraryDocumentFailure

    /** A version this build should know, with no transform that reaches the current one. */
    data class NoMigrationPath(val from: Int) : LibraryDocumentFailure

    /** The document declared a known version and then did not match it. */
    data class Malformed(val reason: String) : LibraryDocumentFailure

    /**
     * The document holds more bytes than this build reads.
     *
     * Refused by name, before any parse, the way a newer version is. A file a reader was handed
     * can be any size, and parsing is where the memory goes.
     */
    data class TooLarge(val found: Long, val limit: Long) : LibraryDocumentFailure
}

/**
 * One step up the version ladder.
 *
 * A transform over the parsed JSON rather than over a typed value, because the type it would
 * decode into is the one this build has and an older document is by definition not that
 * shape. [from] is the version it reads; it writes `from + 1`.
 */
class LibraryDocumentTransform(
    val from: Int,
    private val apply: (JsonObject) -> JsonObject,
) {
    operator fun invoke(document: JsonObject): JsonObject =
        JsonObject(apply(document) + ("formatVersion" to JsonPrimitive(from + 1)))
}

/**
 * Reads and writes [LibraryDocument].
 *
 * The version is checked before anything is decoded, because the whole point of refusing a
 * newer document is that nothing happens to the device — a decoder that got partway and then
 * threw would have already told its caller about half a library.
 *
 * iOS's `LibraryDocumentCoder` is the same three operations and the same refusals.
 */
object LibraryDocumentCoder {

    /**
     * The most bytes this build reads: 64 MiB.
     *
     * The text of a very large library is a few megabytes. The rest of the room is for the
     * covers a reader chose, which travel as base64 (task 6.7): a few hundred of them fit.
     * iOS's `LibraryDocumentCoder.maximumBytes` holds the same number.
     */
    const val MAXIMUM_BYTES = 64L * 1024 * 1024

    /**
     * The transforms this build ships. Empty: version 1 is the first, and the chain exists
     * from the start so the second version has somewhere to go.
     */
    val transforms: List<LibraryDocumentTransform> = emptyList()

    /**
     * Indented and with every field written, because `library-portability` asks for a body a
     * reader can open and a later version can diff. `encodeDefaults` is on for the same
     * reason: a field missing because it happened to hold its default is a field the reader
     * cannot find, and a diff that gains and loses keys is not a diff anybody reads.
     */
    private val json = Json {
        prettyPrint = true
        encodeDefaults = true
        ignoreUnknownKeys = true
        explicitNulls = true
    }

    /**
     * Refuses a file by its size alone, before a byte of it is read.
     *
     * `library-portability` / *A document that is too large*: the import screen asks this with
     * the size the provider reports, so a file a reader was handed never reaches memory.
     * [decode] refuses the same way for text already in hand.
     *
     * @return the refusal, or null when the file is small enough to read.
     */
    fun admits(byteCount: Long, limit: Long = MAXIMUM_BYTES): LibraryDocumentFailure? =
        if (byteCount > limit) LibraryDocumentFailure.TooLarge(byteCount, limit) else null

    /** The document as bytes a reader can open. */
    fun encode(document: LibraryDocument): String = json.encodeToString(document)

    /**
     * A document read back, migrated forward if it is older.
     *
     * The size is checked first, in bytes as UTF-8 would hold the text, before anything is
     * parsed.
     *
     * @param limit the size ceiling, injectable so a test need not allocate 64 MiB.
     * @param transforms the chain, injectable so a test can prove it runs. Production passes
     *   [LibraryDocumentCoder.transforms].
     */
    fun decode(
        text: String,
        limit: Long = MAXIMUM_BYTES,
        transforms: List<LibraryDocumentTransform> = LibraryDocumentCoder.transforms,
    ): Result<LibraryDocument> {
        val size = utf8Size(text)
        if (size > limit) return failure(LibraryDocumentFailure.TooLarge(size, limit))
        val parsed = runCatching { json.parseToJsonElement(text) as JsonObject }.getOrNull()
            ?: return failure(LibraryDocumentFailure.NotALibraryDocument)
        val declared = (parsed["formatVersion"] as? JsonPrimitive)?.intOrNull
            ?: return failure(LibraryDocumentFailure.NotALibraryDocument)

        val current = LibraryDocument.CURRENT_FORMAT_VERSION
        if (declared > current) {
            return failure(LibraryDocumentFailure.NewerThanThisApp(declared, current))
        }

        var migrated = parsed
        var version = declared
        while (version < current) {
            val step = transforms.firstOrNull { it.from == version }
                ?: return failure(LibraryDocumentFailure.NoMigrationPath(version))
            migrated = step(migrated)
            version += 1
        }

        return runCatching { json.decodeFromJsonElement(LibraryDocument.serializer(), migrated) }
            .recoverCatching { throw LibraryDocumentRefusal(LibraryDocumentFailure.Malformed(it.message.orEmpty())) }
    }

    /**
     * The version a document declares, without decoding it.
     *
     * What an import preview asks first: a document it is going to refuse should be refused
     * before the reader is shown a list of what it would have done.
     */
    fun declaredVersion(text: String, limit: Long = MAXIMUM_BYTES): Int? {
        if (utf8Size(text) > limit) return null
        return runCatching { (json.parseToJsonElement(text) as JsonObject)["formatVersion"] }
            .getOrNull()
            ?.let { (it as? JsonPrimitive)?.intOrNull }
    }

    /** The bytes UTF-8 gives [text], counted without making them. */
    private fun utf8Size(text: String): Long {
        var size = 0L
        var index = 0
        while (index < text.length) {
            val unit = text[index].code
            size += when {
                unit < 0x80 -> 1
                unit < 0x800 -> 2
                // A surrogate pair is four bytes together, so the low half adds none.
                unit in 0xD800..0xDBFF -> 4
                unit in 0xDC00..0xDFFF -> 0
                else -> 3
            }
            index++
        }
        return size
    }

    private fun failure(reason: LibraryDocumentFailure): Result<LibraryDocument> =
        Result.failure(LibraryDocumentRefusal(reason))
}

/**
 * The exception a refused document arrives as.
 *
 * `Result` carries a `Throwable` and nothing else, so the refusal has to be one. The reason
 * is the part callers read; the stack trace is of no interest to anybody, which is why this
 * carries no message of its own — the four languages phrase [reason] themselves.
 */
class LibraryDocumentRefusal(val reason: LibraryDocumentFailure) : Exception()
