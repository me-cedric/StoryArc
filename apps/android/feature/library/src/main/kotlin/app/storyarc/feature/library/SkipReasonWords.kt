package app.storyarc.feature.library

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import app.storyarc.core.format.SkipReason

/**
 * The words for a refusal, in the reader's language.
 *
 * **The seam this file is.** `core:format` discovers the refusal and names it as a case;
 * `feature:library` says what that case means, because this is the module with the four
 * `strings.xml`. `localization`'s *A refusal speaks the reader's language*: "it is the text
 * most likely to be written far from any screen — in the layer that discovered the problem",
 * and naming it in English only does not satisfy the requirement.
 *
 * **`core:format` gains no resources, deliberately.** It draws nothing, and a `strings.xml`
 * there would be a translation set for a module with no screens, holding the sentences this
 * file holds instead.
 *
 * The `when` is exhaustive, so a case added to the format layer stops this module compiling
 * until somebody words it. That is what makes *Reasons of different kinds in one list*
 * enforceable: a new refusal cannot reach the notice in English while its neighbours are in
 * French.
 *
 * iOS's `SkipReason.sentence` maps the same cases to the same names in its own catalogue.
 */
@Composable
internal fun skipReasonText(reason: SkipReason): String = when (reason) {
    // The format's name is content, not a sentence: `localization`'s *A sentence built around
    // content* shows it as it is and translates the words around it.
    is SkipReason.UnsupportedFormat ->
        stringResource(R.string.library_skipped_reason_unsupported, reason.format)

    SkipReason.NotThere -> stringResource(R.string.library_skipped_reason_not_there)

    SkipReason.FormatNotRecognised ->
        stringResource(R.string.library_skipped_reason_format_not_recognised)

    SkipReason.ArchivePasswordProtected ->
        stringResource(R.string.library_skipped_reason_archive_password_protected)

    SkipReason.ArchiveUnreadable ->
        stringResource(R.string.library_skipped_reason_archive_unreadable)

    // Not "not a format StoryArc reads" — the format *is* read, and this file is locked.
    // `publication-formats` requires the two to be told apart, because a reader shown the
    // first message would go and convert a file that needs no converting. This wording names
    // the kind of thing, and `localization`'s *One sentence, assembled differently* makes the
    // more informative one the agreed wording for both platforms.
    SkipReason.ContentProtected ->
        stringResource(R.string.library_skipped_reason_content_protected)

    // *A failure with no sentence written for it*: a translated general refusal, rather than
    // text produced for a maintainer. The maintainer's copy is the diagnostic export, which
    // is English by explicit design.
    SkipReason.Unknown -> stringResource(R.string.library_skipped_reason_unknown)
}
