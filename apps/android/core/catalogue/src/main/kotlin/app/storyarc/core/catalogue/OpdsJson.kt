package app.storyarc.core.catalogue

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull

/**
 * OPDS 2.0, which is a Readium Web Publication Manifest with catalogue groups.
 *
 * Read from the JSON tree rather than through generated serializers. Half the fields the
 * standard defines are "a string, an object, or an array of either" -- `rel`, `author`,
 * `belongsTo.series` -- and a data class per shape costs more than reading the tree does.
 * iOS pays the same price in hand-written `init(from:)`.
 */
internal object OpdsJson {

    private val json = Json { ignoreUnknownKeys = true }

    fun parse(body: ByteArray, baseUrl: String): OpdsFeed {
        val root = runCatching { json.parseToJsonElement(String(body)).jsonObject }
            .getOrElse { throw OpdsError.Malformed(it.message ?: "invalid JSON") }

        // A JSON document with no metadata is some other API's response, not a catalogue.
        val metadata = root["metadata"]?.asObject()
            ?: throw OpdsError.NotAFeed(OpdsError.Received.Unrecognised("application/json"))
        val title = metadata["title"].asString().orEmpty()

        fun resolve(href: String) = OpdsDocument.resolve(href, baseUrl)

        // Groups hold the same things a feed does. A named one becomes a section of its own;
        // an unnamed one is poured into the feed, because a section with no title is a
        // heading nobody can read. OPDS 2.0 uses groups where OPDS 1.2 used separate feeds.
        val wireGroups = root["groups"]?.asArray().orEmpty().mapNotNull { it.asObject() }
        val unnamed = wireGroups.filter { it.groupTitle() == null }

        val navigation = (root["navigation"]?.asArray().orEmpty() +
            unnamed.flatMap { it["navigation"]?.asArray().orEmpty() })
            .mapNotNull { section(it.asObject(), ::resolve) }

        val publications = (root["publications"]?.asArray().orEmpty() +
            unnamed.flatMap { it["publications"]?.asArray().orEmpty() })
            .mapNotNull { entry(it.asObject(), ::resolve) }

        val groups = wireGroups.mapNotNull { group(it, ::resolve) }

        val facets = root["facets"]?.asArray().orEmpty().flatMap { facet ->
            val object_ = facet.asObject() ?: return@flatMap emptyList()
            val group = object_["metadata"].asObject()?.get("title").asString()
            object_["links"]?.asArray().orEmpty().mapNotNull { link ->
                val each = link.asObject() ?: return@mapNotNull null
                val href = each["href"].asString()?.let(::resolve) ?: return@mapNotNull null
                val name = each["title"].asString() ?: return@mapNotNull null
                OpdsFacet(group ?: name, name, href, each.numberOfItems())
            }
        }

        val links = root["links"]?.asArray().orEmpty().mapNotNull { it.asObject() }
        val search = links.firstOrNull { "search" in it.relations() }
        val isTemplated = search?.get("templated")?.asBoolean() == true

        return OpdsFeed(
            title = title,
            navigation = navigation,
            publications = publications,
            groups = groups,
            facets = facets,
            next = links.firstOrNull { "next" in it.relations() }
                ?.get("href").asString()?.let(::resolve),
            // A templated link says so, and its href holds the braces. One that does not is
            // a description document, the same as in OPDS 1.2.
            // Smart-cast: `isTemplated` is only true when `search` is not null.
            searchTemplate = if (isTemplated) search.get("href").asString()?.let(::resolve) else null,
            searchDescription = if (isTemplated) null else search?.get("href").asString()?.let(::resolve),
        )
    }

    /**
     * A named group, which the browser shows as a section of its own.
     *
     * Null for a group with no title: there is nothing to head it with, and its contents have
     * already been poured into the feed by the caller.
     */
    private fun group(wire: JsonObject, resolve: (String) -> String?): OpdsGroup? {
        val title = wire.groupTitle() ?: return null
        return OpdsGroup(
            title = title,
            navigation = wire["navigation"]?.asArray().orEmpty()
                .mapNotNull { section(it.asObject(), resolve) },
            publications = wire["publications"]?.asArray().orEmpty()
                .mapNotNull { entry(it.asObject(), resolve) },
            // `self` is where the standard puts "the rest of this group", and a group that
            // points at itself is the one case where following a self link is not a loop: the
            // group is an excerpt of the page it names.
            more = wire["links"]?.asArray().orEmpty()
                .mapNotNull { it.asObject() }
                .firstOrNull { "self" in it.relations() }
                ?.get("href").asString()?.let(resolve),
        )
    }

    /** What a group calls itself, when it calls itself anything. */
    private fun JsonObject.groupTitle(): String? =
        this["metadata"]?.asObject()?.get("title").asString()

    /**
     * A navigation link, which is a section when it has somewhere to go and a name to show.
     * Shared by the feed's own navigation and by every group's.
     */
    private fun section(wire: JsonObject?, resolve: (String) -> String?): OpdsSection? {
        if (wire == null) return null
        val href = wire["href"].asString()?.let(resolve) ?: return null
        val name = wire["title"].asString() ?: return null
        return OpdsSection(name, href, wire.numberOfItems())
    }

    private fun entry(wire: JsonObject?, resolve: (String) -> String?): OpdsEntry? {
        val metadata = wire?.get("metadata")?.asObject() ?: return null
        val title = metadata["title"].asString() ?: return null

        // The largest declared image is the cover and the smallest is the thumbnail. Where
        // only one is offered it serves as both, which is better than showing nothing in a
        // grid while a detail screen has art.
        val images = wire["images"]?.asArray().orEmpty()
            .mapNotNull { it.asObject() }
            .sortedByDescending { it["width"]?.asInt() ?: 0 }

        val series = metadata["belongsTo"]?.asObject()?.get("series")

        return OpdsEntry(
            id = metadata["identifier"].asString() ?: title,
            title = title,
            authors = names(metadata["author"]),
            summary = metadata["description"].asString(),
            series = names(series).firstOrNull(),
            seriesIndex = series?.asObject()?.get("position")?.asDouble(),
            updated = metadata["modified"].asString()?.let(OpdsDates::parse),
            cover = images.firstOrNull()?.get("href").asString()?.let(resolve),
            thumbnail = images.lastOrNull()?.get("href").asString()?.let(resolve),
            acquisitions = wire["links"]?.asArray().orEmpty().mapNotNull { link ->
                val each = link.asObject() ?: return@mapNotNull null
                val href = each["href"].asString()?.let(resolve) ?: return@mapNotNull null
                val relations = each.relations()
                // OPDS 2.0 lets an acquisition link carry no relation at all, in which case
                // being in `links` with a readable type is the whole signal.
                val kind = relations.firstNotNullOfOrNull(OpdsAcquisition.Kind::named)
                    ?: OpdsAcquisition.Kind.DIRECT.takeIf { relations.isEmpty() }
                    ?: return@mapNotNull null
                // The Readium Link Object's own field: the resource's size in bytes, before
                // any encryption or compression in an archive. `asLong` yields null for a
                // server that sends it as a string, which is a feed with no size stated
                // rather than a feed to refuse.
                OpdsAcquisition.of(
                    href,
                    each["type"].asString().orEmpty(),
                    kind,
                    each["size"].asLong(),
                )
            },
        )
    }

    /** A name, a `{ "name": ... }`, or an array of either. */
    private fun names(element: JsonElement?): List<String> = when (element) {
        null -> emptyList()
        is JsonPrimitive -> listOfNotNull(element.contentOrNull)
        is JsonObject -> listOfNotNull(element["name"].asString())
        is JsonArray -> element.flatMap { names(it) }
    }

    /** `rel` is a string or an array of them, and the standard permits both. */
    private fun JsonObject.relations(): List<String> = when (val rel = this["rel"]) {
        is JsonPrimitive -> listOfNotNull(rel.contentOrNull)
        is JsonArray -> rel.mapNotNull { it.asString() }
        else -> emptyList()
    }

    private fun JsonObject.numberOfItems(): Int? =
        this["properties"]?.asObject()?.get("numberOfItems")?.asInt()

    private fun JsonElement?.asObject(): JsonObject? = runCatching { this?.jsonObject }.getOrNull()
    private fun JsonElement?.asArray(): List<JsonElement>? =
        runCatching { this?.jsonArray }.getOrNull()
    private fun JsonElement?.asString(): String? =
        runCatching { this?.jsonPrimitive?.contentOrNull }.getOrNull()
    /**
     * A number, and only a number.
     *
     * `intOrNull` and `longOrNull` parse the *content* of a primitive, so `"4096"` — a
     * quoted string, which the standard's schema does not allow where an integer is
     * required — reads back as 4096. iOS's `Decodable` refuses it, and a mirrored test
     * caught the two platforms disagreeing about the same feed. `isString` is the check
     * that makes them agree: a quoted number is a server sending the wrong type, which is a
     * field with nothing in it rather than a catalogue to refuse.
     */
    private fun JsonElement?.asNumber(): JsonPrimitive? =
        runCatching { this?.jsonPrimitive?.takeIf { !it.isString } }.getOrNull()

    private fun JsonElement?.asInt(): Int? = asNumber()?.intOrNull
    private fun JsonElement?.asLong(): Long? = asNumber()?.longOrNull
    private fun JsonElement?.asDouble(): Double? = asNumber()?.doubleOrNull
    private fun JsonElement?.asBoolean(): Boolean? =
        runCatching { this?.jsonPrimitive?.contentOrNull?.toBooleanStrictOrNull() }.getOrNull()
}
