package app.storyarc.core.catalogue

import org.xmlpull.v1.XmlPullParser
import org.xmlpull.v1.XmlPullParserException
import org.xmlpull.v1.XmlPullParserFactory

/**
 * An OpenSearch description document, reduced to the one thing a catalogue search needs.
 *
 * `opds-catalog`: "when a catalogue advertises an OpenSearch description, searching within
 * that source queries the server rather than filtering locally". Most OPDS 1.2 servers
 * advertise it this way — a `rel="search"` link pointing at a small XML document — rather
 * than putting the template inline in the href, which is what OPDS 2.0 does. The feed parser
 * records where the document is; this reads it.
 *
 * iOS's `OpenSearchDescription` is the same reader, asserted against the same cases.
 */
object OpenSearchDescription {

    /**
     * The query template this document offers, resolved against where the document lives.
     *
     * Null when the body is not a description document, offers no `Url` with a template, or
     * offers only templates for formats a reader cannot browse here. A caller that gets null
     * has a catalogue with no usable search, which is the fallback the spec names.
     */
    fun template(body: ByteArray, baseUrl: String): String? {
        val chosen = choose(offers(body)) ?: return null
        return OpdsDocument.resolve(chosen.template, baseUrl)
    }

    /** One `<Url>` of a description document. */
    data class Offer(val type: String, val template: String)

    /**
     * Which of the offered templates a catalogue browser should use.
     *
     * A description document commonly offers several: one that answers with a feed, one that
     * answers with a web page, sometimes one that answers with suggestions. Only the first is
     * any use here, and a browser that took the HTML one would put the reader's query to a
     * page it cannot render.
     *
     * Internal rather than private so the choice can be asserted on its own, the way iOS
     * asserts it.
     */
    internal fun choose(offers: List<Offer>): Offer? {
        val usable = offers.filter { it.template.isNotEmpty() }
        return usable.firstOrNull { it.type.lowercase().contains("opds") }
            ?: usable.firstOrNull { it.type.lowercase().contains("atom") }
            // A document that declares no type at all is still a document. Preferred over a
            // type that names something this app cannot read.
            ?: usable.firstOrNull { it.type.isEmpty() }
            ?: usable.firstOrNull { !it.type.lowercase().contains("html") }
    }

    /** Collects every `<Url>` the document declares. */
    private fun offers(body: ByteArray): List<Offer> {
        // `XmlPullParserFactory` rather than `android.util.Xml`, so the same parser runs in
        // a JVM unit test — the reason `OpdsAtom` gives for the same choice.
        val factory = XmlPullParserFactory.newInstance()
        factory.isNamespaceAware = true
        val parser = factory.newPullParser()
        parser.setInput(body.inputStream(), null)

        val urls = mutableListOf<Offer>()
        try {
            var event = parser.eventType
            while (event != XmlPullParser.END_DOCUMENT) {
                if (event == XmlPullParser.START_TAG && parser.name == "Url") {
                    urls.add(
                        Offer(
                            type = parser.getAttributeValue(null, "type").orEmpty(),
                            template = parser.getAttributeValue(null, "template").orEmpty(),
                        ),
                    )
                }
                event = parser.next()
            }
        } catch (error: XmlPullParserException) {
            // A body that is not a description document offers nothing, which is the same
            // answer as a document that offers nothing. Both fall back to local filtering.
            return urls
        }
        return urls
    }
}
