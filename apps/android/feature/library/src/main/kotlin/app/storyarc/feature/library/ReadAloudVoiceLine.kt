package app.storyarc.feature.library

import android.content.Context
import android.speech.tts.TextToSpeech
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import app.storyarc.core.designsystem.theme.LocalStoryArcPalette
import app.storyarc.core.model.Publication
import app.storyarc.core.model.PublicationFormat
import java.util.Locale
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * What the publication page says about the device's own read-aloud voice, or nothing.
 *
 * Task 16.7 / D38, `audio-playback`: "No publication page names the synthesised voice" — a
 * reader opening a book StoryArc can read aloud had no way to know, before starting, whether
 * the device had a voice for it at all. D38 settles the exact wording: *"Read aloud by %@"*
 * naming the engine and the language, or, with none installed for the language, *"No voice on
 * this device reads %@"* naming the language instead. iOS names the voice; Android names the
 * engine and the language, because `TextToSpeech` states which engine answered and leaves the
 * voice itself to it.
 *
 * EPUB is the one format this decides for: a narrated audiobook already carries a human voice
 * and nothing else in this app has text to speak at all.
 */
sealed class ReadAloudVoiceFact {
    data class Named(val engineLabel: String, val languageName: String) : ReadAloudVoiceFact()
    data class Missing(val languageName: String) : ReadAloudVoiceFact()
}

/** What [ReadAloudVoiceLookup] found for a language — the one thing a view asks a platform. */
data class ReadAloudEngine(val label: String, val speaksTheLanguage: Boolean)

object ReadAloudVoiceLine {
    /**
     * Pure: decided from facts the caller already resolved, so it needs no window and no
     * bound `TextToSpeech` to test against. `engine` is what ``ReadAloudVoiceLookup`` found —
     * the one call in this feature that touches the platform's TTS service, and the only part
     * a test cannot reach without binding to it for real.
     *
     * - Returns: `null` for every format but EPUB, and for an EPUB with no stated language —
     *   there is nothing to look a voice up *for*.
     */
    fun fact(
        format: PublicationFormat,
        languageCode: String?,
        engine: ReadAloudEngine?,
        languageName: (String) -> String = ::languageName,
    ): ReadAloudVoiceFact? {
        if (format != PublicationFormat.EPUB || languageCode.isNullOrEmpty()) return null
        val name = languageName(languageCode)
        return if (engine != null && engine.speaksTheLanguage) {
            ReadAloudVoiceFact.Named(engine.label, name)
        } else {
            ReadAloudVoiceFact.Missing(name)
        }
    }
}

/**
 * The one place this feature asks the platform's `TextToSpeech` anything.
 *
 * A free function rather than inlined into the composable: ``ReadAloudVoiceLine/fact`` is
 * pure exactly because this lookup is not, and keeping the impure half to one function makes
 * the boundary a fact about the file rather than a convention a reviewer has to remember.
 */
object ReadAloudVoiceLookup {
    /**
     * Binds a `TextToSpeech`, asks it about [languageCode], and shuts it down.
     *
     * `TextToSpeech` reports readiness through a callback rather than a constructor, so this
     * wraps that in [suspendCancellableCoroutine] the way [ReadAloudController] already binds
     * one for the reader itself. Cancellation shuts the engine down rather than leaking the
     * binding, which a composable's own `LaunchedEffect` does the moment the page it serves
     * is gone.
     */
    suspend fun resolve(context: Context, languageCode: String): ReadAloudEngine? =
        suspendCancellableCoroutine { continuation ->
            var engine: TextToSpeech? = null
            engine = TextToSpeech(context.applicationContext) { status ->
                val bound = engine
                if (status == TextToSpeech.SUCCESS && bound != null) {
                    val locale = Locale.forLanguageTag(languageCode)
                    val speaksIt = bound.isLanguageAvailable(locale) >= TextToSpeech.LANG_AVAILABLE
                    val label = engineLabel(context, bound.defaultEngine)
                    if (continuation.isActive) {
                        continuation.resume(ReadAloudEngine(label = label, speaksTheLanguage = speaksIt))
                    }
                    bound.shutdown()
                } else {
                    if (continuation.isActive) continuation.resume(null)
                    bound?.shutdown()
                }
            }
            continuation.invokeOnCancellation { engine.shutdown() }
        }

    /** The default engine's own app label, or its package name where that cannot be read. */
    private fun engineLabel(context: Context, packageName: String?): String {
        val name = packageName ?: return context.getString(R.string.detail_readaloud_defaultEngine)
        return runCatching {
            val info = context.packageManager.getApplicationInfo(name, 0)
            context.packageManager.getApplicationLabel(info).toString()
        }.getOrDefault(name)
    }
}

/** The line itself, drawn where [DetailMainPane] puts it. */
@Composable
internal fun ReadAloudVoiceLineText(fact: ReadAloudVoiceFact, modifier: Modifier = Modifier) {
    val palette = LocalStoryArcPalette.current
    val text = when (fact) {
        is ReadAloudVoiceFact.Named ->
            stringResource(R.string.detail_readaloud_voice, fact.engineLabel, fact.languageName)
        is ReadAloudVoiceFact.Missing ->
            stringResource(R.string.detail_readaloud_noVoice, fact.languageName)
    }
    Text(
        text = text,
        style = MaterialTheme.typography.labelMedium,
        color = palette.textSecondary,
        modifier = modifier,
    )
}

/** Whether [publication] is one the device could, in principle, read aloud — EPUB only. */
internal fun canNameAReadAloudVoice(publication: Publication): Boolean =
    publication.format == PublicationFormat.EPUB && !publication.language.isNullOrEmpty()

/**
 * Resolves [publication]'s own ``ReadAloudVoiceFact``, or `null` while that is still in
 * flight or for a publication this can never be true of.
 *
 * Pulled out of `PublicationDetailScreen` itself so that page's own composable states its
 * rules rather than the plumbing underneath one of them — the same reason `rememberDetailAccent`
 * and `rememberPublicationCopy` are already their own functions beside it.
 */
@Composable
internal fun rememberReadAloudVoiceFact(publication: Publication): ReadAloudVoiceFact? {
    var fact by remember(publication.id) { mutableStateOf<ReadAloudVoiceFact?>(null) }
    if (canNameAReadAloudVoice(publication)) {
        val context = LocalContext.current
        LaunchedEffect(publication.id, publication.language) {
            val engine = ReadAloudVoiceLookup.resolve(context, publication.language.orEmpty())
            fact = ReadAloudVoiceLine.fact(publication.format, publication.language, engine)
        }
    }
    return fact
}
