package app.storyarc.feature.epubreader

import java.util.Locale
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.services.content.Content
import org.readium.r2.shared.publication.services.content.TextContentTokenizer
import org.readium.r2.shared.publication.services.content.content
import org.readium.r2.shared.util.tokenizer.TextUnit

/**
 * One sentence of a publication, with the place it came from.
 *
 * [locator] is what the highlight is drawn at and what the page is moved to, so it is the
 * segment's own locator rather than the element's: an element is a paragraph, and a
 * paragraph-wide highlight would not say which sentence the voice is on.
 */
internal data class Sentence(
    val locator: Locator,
    val text: String,
    /** The language this sentence declares, or null to use the publication's. */
    val language: Locale?,
)

/**
 * The publication, walked one sentence at a time, in either direction.
 *
 * This is the part the repository believed Android had no answer for. It does, and it has
 * had one since before this app existed: `readium-shared` — already a dependency, because
 * the navigator needs it — carries a content service, an HTML content iterator and a
 * sentence tokenizer, and `EpubParser` installs the first of those on every EPUB it
 * parses. Nothing here needed a new artifact. See ADR-0017.
 *
 * The engine that says the words is the platform's `TextToSpeech`; what this type does is
 * decide *what* it says and *where that is in the book*, which is the half a speech engine
 * cannot do.
 *
 * iOS gets the same two answers from Readium's own `PublicationSpeechSynthesizer`, which
 * is the iOS-only half of the same toolkit.
 */
@OptIn(ExperimentalReadiumApi::class)
internal class SpokenSentences(private val publication: Publication) {

    /**
     * Whether this publication has any extractable text at all.
     *
     * Null means no content service, which is what a publication with nothing to say looks
     * like from here. The control is absent in that case rather than present and refusing.
     */
    val isSpeakable: Boolean = isSpeakable(publication)

    internal companion object {
        /**
         * The same answer, without a walk to ask it of.
         *
         * The reader has to know whether the control appears the moment the book opens, and
         * the walk is not built until somebody presses play — the session it belongs to
         * outlives the screen asking this question, so building one here to ask it would be
         * building the thing whose lifetime is the whole point.
         */
        fun isSpeakable(publication: Publication): Boolean = publication.content() != null
    }

    private val tokenizer = TextContentTokenizer(
        language = publication.metadata.language,
        unit = TextUnit.Sentence,
    )

    private var iterator: Content.Iterator? = null

    /** The sentences of the element the cursor is inside, and where in them it is. */
    private var sentences: List<Sentence> = emptyList()
    private var cursor = -1

    /**
     * Points the walk at a position and forgets everything before it.
     *
     * `ebook-reader`: speech "begins at the current position". A null start is the
     * beginning of the publication, which is what a book nobody has opened yet means.
     */
    fun restart(from: Locator?) {
        iterator = publication.content(from)?.iterator()
        sentences = emptyList()
        cursor = -1
    }

    /**
     * The next sentence, or null at the end of the publication.
     *
     * The iterator spans the whole reading order, so the end of a resource is not the end
     * of anything: the walk crosses into the next one without being asked to, which is
     * what "the page follows" has to mean when a chapter runs out mid-listen.
     */
    suspend fun next(): Sentence? = advance(forward = true)

    /** The sentence before, or null at the beginning of the publication. */
    suspend fun previous(): Sentence? = advance(forward = false)

    private suspend fun advance(forward: Boolean): Sentence? {
        val step = if (forward) 1 else -1
        if (cursor + step in sentences.indices) {
            cursor += step
            return sentences[cursor]
        }
        val walk = iterator ?: return null
        // A loop, not a single step: an element can be an image, a horizontal rule, or a
        // paragraph of nothing but whitespace, and none of those has a sentence in it.
        // Returning null there would end the reading at the first illustration.
        while (true) {
            val element =
                if (forward) walk.nextOrNull() else walk.previousOrNull()
            if (element == null) {
                // Left where it was, so pressing the other way still works: a reader who
                // skipped back to the first sentence of the book has not lost the rest.
                return null
            }
            val found = element.sentences()
            if (found.isEmpty()) continue
            sentences = found
            cursor = if (forward) 0 else found.lastIndex
            return found[cursor]
        }
    }

    /**
     * One content element, split into the sentences a voice can say.
     *
     * Whitespace-only segments are dropped rather than spoken: a tokenizer splitting a
     * paragraph that ends with a line break yields one, and an engine handed it either
     * says nothing for a beat or refuses, and either way the highlight lands on a blank.
     */
    private fun Content.Element.sentences(): List<Sentence> =
        tokenizer.tokenize(this)
            .filterIsInstance<Content.TextElement>()
            .flatMap { it.segments }
            .mapNotNull { segment ->
                val text = segment.text.trim()
                if (text.isEmpty()) {
                    null
                } else {
                    // The publication's own language where the markup declares none:
                    // an engine given no language reads French with an English voice,
                    // which is worse than not reading it at all.
                    val language = segment.language ?: publication.metadata.language
                    Sentence(segment.locator, text, language?.locale)
                }
            }
}
