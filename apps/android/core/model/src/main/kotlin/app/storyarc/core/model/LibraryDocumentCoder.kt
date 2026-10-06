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

    /** The document as bytes a reader can open. */
    fun encode(document: LibraryDocument): String = json.encodeToString(document)

    /**
     * A document read back, migrated forward if it is older.
     *
     * @param transforms the chain, injectable so a test can prove it runs. Production passes
     *   [LibraryDocumentCoder.transforms].
     */
    fun decode(
        text: String,
        transforms: List<LibraryDocumentTransform> = LibraryDocumentCoder.transforms,
    ): Result<LibraryDocument> {
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
    fun declaredVersion(text: String): Int? =
        runCatching { (json.parseToJsonElement(text) as JsonObject)["formatVersion"] }
            .getOrNull()
            ?.let { (it as? JsonPrimitive)?.intOrNull }

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
