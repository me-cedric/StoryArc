package app.storyarc.core.model

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.nullable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder

/**
 * Where a reflowable page starts, as text rather than as a fraction.
 *
 * `reading-progress`, *Resume at the first visible element*, decision O27. A fraction names a
 * page only through the typography of the device that wrote it, so the same fraction opens
 * pages up to one page apart on iOS and Android. This names the first visible element (its CSS
 * selector) and the text just before and just after the first visible character in it. A
 * resume anchors on that text, so two devices open the same paragraph.
 *
 * iOS's `ElementLocator` holds the same five fields with the same names.
 *
 * @param href the resource the element is in, as the reading order names it.
 * @param textBefore the text before the first visible character, at most [TEXT_LIMIT] chars.
 * @param textAfter the text from the first visible character on, at most [TEXT_LIMIT] chars.
 * @param publicationDigest the content digest of the file the element was taken from.
 */
@Serializable
data class ElementLocator(
    val href: String,
    val cssSelector: String,
    val textBefore: String? = null,
    val textAfter: String,
    val publicationDigest: String,
) {
    /**
     * Whether a resume in this publication, in this resource, goes to the element.
     *
     * Only the same file and the same resource. Any other case uses the fraction, because a
     * selector in another file names another element.
     */
    fun resumes(publicationDigest: String?, resource: String): Boolean =
        publicationDigest == this.publicationDigest && bare(href) == bare(resource)

    companion object {
        /**
         * How much text each side keeps. Enough to find one place in a chapter, small enough
         * for a sync document.
         */
        const val TEXT_LIMIT = 60

        /**
         * The element a reader can store, or null when there is nothing to anchor on.
         *
         * Null without a digest, because a resume must prove the file is the same one. Null
         * without a selector or without visible text after the point, because the navigator
         * can find neither.
         */
        fun captured(
            href: String,
            cssSelector: String?,
            textBefore: String?,
            textAfter: String?,
            publicationDigest: String?,
        ): ElementLocator? {
            if (cssSelector.isNullOrEmpty() || textAfter.isNullOrBlank() || publicationDigest.isNullOrEmpty()) {
                return null
            }
            return ElementLocator(
                href = href,
                cssSelector = cssSelector,
                textBefore = textBefore?.takeLast(TEXT_LIMIT),
                textAfter = textAfter.take(TEXT_LIMIT),
                publicationDigest = publicationDigest,
            )
        }

        private fun bare(href: String): String = href.substringBefore('#')
    }
}

/**
 * Reads an element, or null when this build cannot read it.
 *
 * A document position keeps its fraction when its element is unreadable, as iOS's
 * `DocumentPosition` does. The default serializer would fail the whole document instead.
 */
internal object ElementOrNull : KSerializer<ElementLocator?> {
    private val plain = ElementLocator.serializer().nullable

    override val descriptor: SerialDescriptor = plain.descriptor

    override fun serialize(encoder: Encoder, value: ElementLocator?) = plain.serialize(encoder, value)

    override fun deserialize(decoder: Decoder): ElementLocator? {
        val json = decoder as? JsonDecoder ?: return plain.deserialize(decoder)
        val value = json.decodeJsonElement()
        return runCatching { json.json.decodeFromJsonElement(ElementLocator.serializer(), value) }.getOrNull()
    }
}
