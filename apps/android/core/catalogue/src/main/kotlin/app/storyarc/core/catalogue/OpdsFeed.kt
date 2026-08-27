package app.storyarc.core.catalogue

import java.util.Date

/**
 * One page of an OPDS catalogue, in the shape the app browses.
 *
 * `opds-catalog` requires the app to "support OPDS 1.2 (Atom) and OPDS 2.0 (JSON),
 * detecting the version from the response". Two wire formats, one model: the browsing code
 * should not know which one it came from, or a facet would have to be implemented twice
 * and would drift.
 *
 * iOS's `OpdsFeed` is the same five fields.
 */
data class OpdsFeed(
    /** Shown as confirmation when a catalogue is added, per the spec's first scenario. */
    val title: String,
    /** Sections a reader can enter. Empty for a pure acquisition feed. */
    val navigation: List<OpdsSection> = emptyList(),
    /** Publications on this page. Empty for a pure navigation feed. */
    val publications: List<OpdsEntry> = emptyList(),
    /** Filters the server offers, surfaced through `library-browsing`'s controls. */
    val facets: List<OpdsFacet> = emptyList(),
    /**
     * The next page, followed as the reader scrolls. `opds-catalog` forbids a visible
     * "load more", so this is read by the scroll rather than by a button.
     */
    val next: String? = null,
    /**
     * Where a search goes when the catalogue advertises one.
     *
     * A template, not a URL: OpenSearch gives `...?q={searchTerms}` and OPDS 2.0 gives an
     * href with the same braces. Substitution happens at the moment of searching, so the
     * unresolved form is what is stored.
     */
    val searchTemplate: String? = null,
    /**
     * Where a template lives, when the feed pointed at an OpenSearch description document
     * instead of carrying the template itself. One more request, and only when a reader
     * actually searches.
     */
    val searchDescription: String? = null,
) {
    /**
     * Whether this page holds publications rather than sections.
     *
     * A feed can hold both, and several real servers do -- Calibre-Web puts "Recently
     * added" beside its sections. So this asks what to *show first*, not what the feed is.
     */
    val isAcquisition: Boolean get() = publications.isNotEmpty()
}

/** A section of a catalogue, which is a link to another feed. */
data class OpdsSection(
    val title: String,
    val href: String,
    /**
     * How many publications the section holds, when the feed says.
     *
     * `opds-catalog`: each section is shown "with its title and, where the feed provides
     * one, its item count". Null because most servers do not provide one, and a fabricated
     * zero would read as an empty section.
     */
    val count: Int? = null,
)

/** A filter the server offers. */
data class OpdsFacet(
    /**
     * The group this facet belongs to -- "Language", "Sort by". Facets in one group are
     * alternatives to each other, which is what makes them a filter rather than a list.
     */
    val group: String,
    val title: String,
    val href: String,
    val count: Int? = null,
    /** Whether the server says this facet is the one currently applied. */
    val isActive: Boolean = false,
)

/**
 * One publication in a catalogue, before it is downloaded.
 *
 * Deliberately not a `Publication`: that type describes a file this device can open, and
 * this describes something on a server that may not be readable at all. Conflating them is
 * how a library ends up listing a title it cannot open.
 */
data class OpdsEntry(
    val id: String,
    val title: String,
    val authors: List<String> = emptyList(),
    val summary: String? = null,
    val series: String? = null,
    val seriesIndex: Double? = null,
    val updated: Date? = null,
    val cover: String? = null,
    val thumbnail: String? = null,
    /** Every way this entry can be obtained, in the order the feed listed them. */
    val acquisitions: List<OpdsAcquisition> = emptyList(),
)

/** One way to obtain a publication. */
data class OpdsAcquisition(
    val href: String,
    /**
     * The media type the feed declared, verbatim. Kept as written rather than mapped to a
     * `PublicationFormat` here: the spec requires an unreadable entry to name "the formats
     * offered", and a type that mapped to nothing would have no name to give.
     */
    val mediaType: String,
    val kind: Kind,
) {
    /**
     * What obtaining it involves.
     *
     * `opds-catalog` requires an unsupported acquisition to be *stated* rather than to fail
     * silently, so every relation the standard defines is named here -- including the ones
     * the app will refuse.
     */
    enum class Kind {
        /** A direct download, free to take. */
        OPEN,

        /** A direct download the reader has already paid for or is entitled to. */
        DIRECT,

        /** A loan. Requires a flow StoryArc does not implement. */
        BORROW,

        /** A purchase. Requires a payment flow StoryArc does not implement. */
        BUY,

        /** A subscription. */
        SUBSCRIBE,

        /** An excerpt. */
        SAMPLE,

        /** Something reached through another acquisition step, such as OPDS-LCP. */
        INDIRECT,
        ;

        /** Whether the app can act on it. Only a direct link is something to fetch. */
        val isFetchable: Boolean get() = this == OPEN || this == DIRECT || this == SAMPLE

        companion object {
            /** The Atom relation this corresponds to, for parsing and for tests. */
            fun named(relation: String): Kind? = when (relation) {
                "http://opds-spec.org/acquisition" -> DIRECT
                "http://opds-spec.org/acquisition/open-access" -> OPEN
                "http://opds-spec.org/acquisition/borrow" -> BORROW
                "http://opds-spec.org/acquisition/buy" -> BUY
                "http://opds-spec.org/acquisition/subscribe" -> SUBSCRIBE
                "http://opds-spec.org/acquisition/sample" -> SAMPLE
                else -> null
            }
        }
    }
}

/**
 * Why a URL did not yield a catalogue.
 *
 * `opds-catalog`: when a URL "returns something that is not an OPDS feed", the app "says
 * what it received -- an HTML page, a redirect, a 404 -- instead of reporting a generic
 * failure". Each of those is a case here so the message can be written once and be true.
 */
sealed class OpdsError(message: String) : Exception(message) {
    /** The response had no body. */
    data object Empty : OpdsError("empty response")

    /** The body parsed, but is not a catalogue. */
    data class NotAFeed(val received: Received) : OpdsError("not a feed: $received")

    /** The body is the right dialect and is malformed. */
    data class Malformed(val reason: String) : OpdsError("malformed: $reason")

    /** The server answered, unhappily. */
    data class Http(val status: Int) : OpdsError("http $status")

    /** The server asked who is calling. */
    data class Unauthorized(val scheme: AuthenticationScheme?) : OpdsError("unauthorized")

    /** What arrived instead of a feed. */
    sealed class Received {
        data object Html : Received()
        data class Unrecognised(val contentType: String?) : Received()
    }

    /**
     * How a 401 asked to be answered.
     *
     * `opds-catalog` requires support for "HTTP Basic and Bearer tokens", and the challenge
     * is the only thing that says which one this server wants.
     */
    enum class AuthenticationScheme {
        BASIC,
        BEARER,
        ;

        companion object {
            /** Reads the scheme out of a `WWW-Authenticate` header. */
            fun of(challenge: String): AuthenticationScheme? =
                when (challenge.trim().substringBefore(' ').lowercase()) {
                    "basic" -> BASIC
                    "bearer" -> BEARER
                    else -> null
                }
        }
    }
}
