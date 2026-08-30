package app.storyarc.feature.library

import app.storyarc.core.model.Publication
import app.storyarc.core.model.StreamingCapability

/**
 * The one thing this page wants the reader to do.
 *
 * `publication-detail` asks for "exactly one primary action" and for its wording to say
 * "which of those will happen before it is taken". That is an accessibility requirement as
 * much as a layout one: it is the first control after the title in the reading order, and a
 * screen-reader user learns the outcome before taking it. So the label is not a cosmetic
 * choice made at the button and it is not derived twice — it is this value.
 *
 * The last three cases are the delta's "the primary action cannot be honoured": the action
 * "states what it needs in plain language rather than failing when taken".
 */
internal enum class PrimaryAction {
    /** Nothing has been read. Opens at the start. */
    READ,

    /** Something has been read. Opens where the reader stopped. */
    CONTINUE,

    /** Readable, but only once the whole file is local. A solid archive, say. */
    NEEDS_DOWNLOAD,

    /** Not on this device, and the library it lives in is not answering. */
    NEEDS_SOURCE,

    /** No decoder will open this, here or anywhere. Downloading changes nothing. */
    REFUSED,
}

/**
 * Which of the five is true, from what the page already knows.
 *
 * Ordered so that a refusal beats an absence and an absence beats a reading position: a
 * publication the app cannot open must not be offered as *Continue* merely because a
 * position was recorded against it before its container turned out to be unreadable.
 */
internal fun primaryActionOf(
    publication: Publication,
    provenance: Provenance,
    isOnDevice: Boolean,
    hasProgress: Boolean,
): PrimaryAction = when {
    !publication.isOpenable -> PrimaryAction.REFUSED

    isOnDevice -> if (hasProgress) PrimaryAction.CONTINUE else PrimaryAction.READ

    provenance.readiness == Provenance.Readiness.SOURCE_AWAY -> PrimaryAction.NEEDS_SOURCE

    publication.streaming == StreamingCapability.DOWNLOAD_ONLY -> PrimaryAction.NEEDS_DOWNLOAD

    hasProgress -> PrimaryAction.CONTINUE

    else -> PrimaryAction.READ
}

/**
 * Whether taking the primary action opens the book, rather than asking for it.
 *
 * Two of the five states are a sentence with a button beside it rather than a way in, and
 * the screen has to keep the difference: a filled button that reports a problem when it is
 * pressed is the failure the delta names outright.
 */
internal val PrimaryAction.opensTheBook: Boolean
    get() = this == PrimaryAction.READ || this == PrimaryAction.CONTINUE

/** How the primary action is worded. */
internal fun PrimaryAction.label(): Int = when (this) {
    PrimaryAction.READ -> R.string.detail_action_read
    PrimaryAction.CONTINUE -> R.string.detail_action_continue
    PrimaryAction.NEEDS_DOWNLOAD, PrimaryAction.NEEDS_SOURCE -> R.string.detail_action_download
    PrimaryAction.REFUSED -> R.string.detail_action_refused
}

/**
 * The sentence under the action, when it needs one, and none otherwise.
 *
 * `publication-detail`: an action that does not apply is "absent, not shown disabled
 * without explanation". A button that cannot do the obvious thing owes a reason in the
 * same breath, and the two states that owe one are the two the reader did not cause.
 */
internal fun PrimaryAction.explanation(): Int? = when (this) {
    PrimaryAction.READ, PrimaryAction.CONTINUE -> null
    PrimaryAction.NEEDS_DOWNLOAD -> R.string.detail_needs_download
    PrimaryAction.NEEDS_SOURCE -> R.string.detail_needs_source
    PrimaryAction.REFUSED -> R.string.detail_refused_body
}
