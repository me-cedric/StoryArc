package app.storyarc.core.model

import java.time.Instant
import java.time.temporal.ChronoUnit
import java.util.UUID
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * An enum case as the document spells it: lower camel, which is what Swift's raw values
 * already are.
 *
 * This platform names its cases in SCREAMING_SNAKE, so one of the two had to convert and it
 * is this one. The conversion is a bijection over the names both platforms use — every case
 * in this codebase is `WORDS_LIKE_THIS`, and the inverse splits on the capitals it put in —
 * so a value written here and read back here is the value that went in.
 *
 * `SourceKind` is design.md's second row and the reason this exists; it then turned out that
 * every other enum crossing the boundary has the identical problem, so they all come through
 * here rather than each inventing its own spelling.
 */
internal fun String.toWireCase(): String {
    val words = split('_')
    return words.first().lowercase() + words.drop(1).joinToString("") { word ->
        word.lowercase().replaceFirstChar { it.uppercase() }
    }
}

/** The inverse of [toWireCase]: `localFolder` becomes `LOCAL_FOLDER`. */
internal fun String.fromWireCase(): String = buildString {
    this@fromWireCase.forEach { character ->
        if (character.isUpperCase() && isNotEmpty()) append('_')
        append(character.uppercaseChar())
    }
}

/** The enum a wire case names, or [fallback] when this build does not know it. */
internal inline fun <reified T : Enum<T>> wireEnum(wire: String?, fallback: T): T =
    wireEnumOrNull<T>(wire) ?: fallback

/** The enum a wire case names, or null — for a field that is itself optional. */
internal inline fun <reified T : Enum<T>> wireEnumOrNull(wire: String?): T? =
    wire?.let { runCatching { enumValueOf<T>(it.fromWireCase()) }.getOrNull() }

/**
 * A moment as the document spells it: ISO 8601, to whole seconds.
 *
 * design.md's first row. This platform keeps epoch millis and iOS keeps a `Date`; neither is
 * readable in a file, and one of them is not even a date.
 *
 * **Truncated to the second on purpose.** `ISO8601DateFormatter` refuses a fractional second
 * unless it is told to expect one, so a millisecond written here would be a document iOS
 * declines over a field no reader ever looks at.
 */
internal fun wireMoment(epochMillis: Long): String =
    Instant.ofEpochMilli(epochMillis).truncatedTo(ChronoUnit.SECONDS).toString()

/** The moment a wire string names, or null when it names nothing this build can read. */
internal fun epochMillis(wire: String?): Long? =
    wire?.let { runCatching { Instant.parse(it).toEpochMilli() }.getOrNull() }

/**
 * A publication identity as the document spells it.
 *
 * A shape of its own rather than [PublicationIdentity] itself, because the two platforms
 * spell its server half differently — iOS writes `sourceID` and `remoteID`, this platform
 * writes `sourceId` and `remoteId`. The document takes the lower-camel `Id`, which is what
 * every other key in it uses, and flattens the pair so the whole identity is four scalars.
 */
@Serializable
data class DocumentIdentity(
    val serverSourceId: String? = null,
    val serverRemoteId: String? = null,
    val contentDigest: String? = null,
    val normalizedPath: String? = null,
) {
    constructor(identity: PublicationIdentity) : this(
        serverSourceId = identity.serverIdentifier?.sourceId?.toString(),
        serverRemoteId = identity.serverIdentifier?.remoteId,
        contentDigest = identity.contentDigest,
        normalizedPath = identity.normalizedPath,
    )

    /**
     * The identity this one names.
     *
     * A server half needs both of its components, so a document carrying only one of them is
     * read as having no server half at all. A guessed server identity would file two
     * different publications as one, which is the loss [PublicationIdentity] exists to
     * prevent.
     */
    fun identity(): PublicationIdentity {
        val sourceId = serverSourceId?.let { runCatching { UUID.fromString(it) }.getOrNull() }
        val server = if (sourceId != null && serverRemoteId != null) {
            PublicationIdentity.ServerIdentifier(sourceId, serverRemoteId)
        } else {
            null
        }
        return PublicationIdentity(server, contentDigest, normalizedPath)
    }
}

/**
 * A reading position as the document spells it: a named kind and named fields.
 *
 * design.md's table, fourth row. iOS stores a position as one JSON blob and this platform as
 * nine flat columns in a Room table, and neither shape is a thing a reader can read or a
 * later version can diff. The named fields are the agreed shape, and each platform converts.
 *
 * **Times are whole milliseconds.** iOS keeps a listening offset as seconds in a `Double` and
 * this platform as millis in a `Long`. Millis is the one of the two that is exact, and a
 * listening position has no use for a finer unit than a millisecond.
 */
@Serializable
data class DocumentPosition(
    val kind: String,
    val index: Int? = null,
    @SerialName("of") val pageCount: Int? = null,
    val progression: Double? = null,
    val locator: String? = null,
    val part: Int? = null,
    val partCount: Int? = null,
    val offsetMillis: Long? = null,
    val ofMillis: Long? = null,
) {
    constructor(position: ReadingPosition) : this(
        kind = when (position) {
            is ReadingPosition.Page -> PAGE
            is ReadingPosition.Reflowable -> REFLOWABLE
            is ReadingPosition.Listening -> LISTENING
        },
        index = (position as? ReadingPosition.Page)?.index,
        pageCount = (position as? ReadingPosition.Page)?.total,
        progression = (position as? ReadingPosition.Reflowable)?.progression,
        locator = (position as? ReadingPosition.Reflowable)?.locator,
        part = (position as? ReadingPosition.Listening)?.part,
        partCount = (position as? ReadingPosition.Listening)?.partCount,
        offsetMillis = (position as? ReadingPosition.Listening)?.offsetMillis,
        ofMillis = (position as? ReadingPosition.Listening)?.ofMillis,
    )

    /**
     * The position this one names, or null when it names a kind this build does not know.
     *
     * Null rather than a guess: a record filed at the wrong place in a book is worse than a
     * record that did not arrive, because the reader cannot see that it is wrong.
     */
    fun position(): ReadingPosition? = when (kind) {
        PAGE -> ReadingPosition.Page(index ?: return null, pageCount ?: return null)
        REFLOWABLE -> ReadingPosition.Reflowable(progression ?: return null, locator.orEmpty())
        LISTENING -> ReadingPosition.Listening(
            part = part ?: return null,
            partCount = partCount ?: return null,
            offsetMillis = offsetMillis ?: return null,
            ofMillis = ofMillis,
        )
        else -> null
    }

    private companion object {
        const val PAGE = "page"
        const val REFLOWABLE = "reflowable"
        const val LISTENING = "listening"
    }
}
